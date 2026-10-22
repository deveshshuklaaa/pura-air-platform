'use strict';
const path = require('node:path'), fs = require('node:fs');
const { spawn, execFileSync } = require('node:child_process');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getDatabase } = require('firebase-admin/database');
const { getAuth } = require('firebase-admin/auth');
const { createHttpServer } = require('../server');
const { createTelemetry } = require('../durable-telemetry');
const { createDeviceSecurity } = require('../device-security');
const { generateEvents, sendEvent } = require('./simulator');

async function main() {
  if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080'
      || process.env.FIREBASE_DATABASE_EMULATOR_HOST !== '127.0.0.1:19000'
      || process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:19099') throw Error('local_demo_emulators_required');
  const device = process.env.PURA_PHYSICAL_DEVICE;
  if (!device || !/^[A-Za-z0-9_-]+$/.test(device)) throw Error('explicit_physical_device_required');
  const root = path.resolve(__dirname, '../..'), projectId = 'demo-pura-security';
  const app = initializeApp({ projectId, databaseURL: `https://${projectId}.firebaseio.com` }, 'phone-fixture');
  const services = { firestore: getFirestore(app), rtdb: getDatabase(app), auth: getAuth(app) };
  const telemetry = createTelemetry(services), security = createDeviceSecurity(services);
  const server = createHttpServer(services, { telemetry });
  const backendHandler = server.listeners('request')[0]; server.removeAllListeners('request');
  const key = 'NON_PRODUCTION_SIMULATOR_KEY';
  let sync;
  const reversePorts = [];
  const run = (command, args, env = process.env) => new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: root, stdio: 'inherit', env, shell: process.platform === 'win32' && command.endsWith('.bat') });
    child.on('error', reject); child.on('exit', (code) => code === 0 ? resolve() : reject(Error('physical_command_failed_' + code)));
  });
  try {
    // This explicit demo-only reset never uses configured production credentials.
    const cleared = await fetch(`http://127.0.0.1:18080/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: 'DELETE' });
    if (!cleared.ok) throw Error('fixture_reset_failed');
    await services.rtdb.ref().set(null);
    try { await services.auth.deleteUser('phone-owner'); } catch (e) { if (e.code !== 'auth/user-not-found') throw e; }
    await services.auth.createUser({ uid: 'phone-owner', email: 'phone-owner@example.test', password: 'LocalOnly-1b-Fixture!' });
    await services.firestore.doc('devices/PA-SIM').set({ active: true, owner_uid: null });
    await services.firestore.doc('device_credentials/PA-SIM').set({ ingest_key: key });
    await security.execute('phone-owner', 'POST', '/api/devices/PA-SIM/claim', { name: 'Simulated test device' });
    sync = setInterval(() => security.syncAll().catch(() => console.error('fixture_access_sync_failed')), 20000);
    server.on('request', async (req, res) => {
      if (req.method !== 'POST' || req.url !== '/fixture/run') { backendHandler(req, res); return; }
      try {
        const events = generateEvents({ runId: 'phone-' + Date.now() });
        for (const event of events) {
          await sendEvent('http://127.0.0.1:18088', key, event);
          const deadline = Date.now() + 10000;
          while ((await telemetry.status(event.device_id, event.event_id)).status !== 'completed') {
            if (Date.now() > deadline) throw Error('fixture_processing_timeout');
            await new Promise((resolve) => setTimeout(resolve, 50));
          }
        }
        const state = (await services.rtdb.ref('devices/PA-SIM/state').get()).val();
        const forecast = (await services.rtdb.ref('devices/PA-SIM/forecast').get()).val();
        const rows = await services.firestore.collection('devices/PA-SIM/history').orderBy('timestamp').get();
        const result = { label: 'SIMULATED TEST DATA — physical-phone fixture', events, state, forecast, history: rows.docs.map((d) => d.data()) };
        const out = path.join(root, 'docs/development/artifacts/physical-telemetry-fixture.json');
        fs.mkdirSync(path.dirname(out), { recursive: true }); fs.writeFileSync(out, JSON.stringify(result, null, 2) + '\n');
        res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(result));
      } catch { res.writeHead(500, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ error: 'fixture_failed' })); }
    });
    await new Promise((resolve) => server.listen(18088, '127.0.0.1', resolve)); telemetry.start();
    const existing = execFileSync('adb', ['-s', device, 'reverse', '--list'], { encoding: 'utf8' });
    for (const port of [18080, 19000, 19099, 18088]) {
      const source = 'tcp:' + port;
      const line = existing.split('\n').map(l=>l.trim().split(/\s+/)).find(parts=>parts.at(-2) === source);
      if (line) { if (line.at(-1) !== source) throw Error('usb_reverse_port_in_use'); continue; }
      await run('adb', ['-s', device, 'reverse', source, source]); reversePorts.push(port);
    }
    await run(process.platform === 'win32' ? 'flutter.bat' : 'flutter', ['test', 'integration_test/telemetry_e2e_test.dart', '-d', device,
      '--dart-define=PURA_ISOLATED_TEST=true', '--dart-define=PURA_API_BASE_URL=http://127.0.0.1:18088'], { ...process.env, PURA_ISOLATED_TEST: 'true' });
  } finally {
    clearInterval(sync); await telemetry.stop(); await new Promise((resolve) => server.close(resolve));
    for (const port of reversePorts) { try { await run('adb', ['-s', device, 'reverse', '--remove', `tcp:${port}`]); } catch { /* report is in command output */ } }
    await deleteApp(app);
  }
}
if (require.main === module) main().catch((e) => { console.error(e.message); process.exitCode = 1; });
module.exports = { main };

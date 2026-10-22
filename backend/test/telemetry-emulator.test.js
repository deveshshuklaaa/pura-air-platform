'use strict';
const { test, before, after, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getDatabase } = require('firebase-admin/database');
const { getAuth } = require('firebase-admin/auth');
const { createDeviceSecurity } = require('../device-security');
const { createTelemetry } = require('../durable-telemetry');
const { createHttpServer } = require('../server');
const { generateEvents, sendEvent } = require('../scripts/simulator');
const { calculateAqi } = require('../aqi');
if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080' || process.env.FIREBASE_DATABASE_EMULATOR_HOST !== '127.0.0.1:19000') throw Error('emulator_only');
const projectId = 'demo-pura-security', key = 'NON_PRODUCTION_SIMULATOR_KEY';
let env, app, db, rtdb, telemetry, server, url, services;
before(async () => {
  env = await initializeTestEnvironment({ projectId, firestore: { host: '127.0.0.1', port: 18080, rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8') },
    database: { host: '127.0.0.1', port: 19000, rules: fs.readFileSync(path.join(__dirname, '../../database.rules.json'), 'utf8') } });
  app = initializeApp({ projectId, databaseURL: `https://${projectId}.firebaseio.com` }, 'telemetry-tests');
  db = getFirestore(app); rtdb = getDatabase(app); services = { firestore: db, rtdb, auth: getAuth(app) };
});
beforeEach(async () => {
  await env.clearFirestore(); await env.clearDatabase();
  await db.doc('devices/PA-SIM').set({ active: true, owner_uid: null });
  await db.doc('device_credentials/PA-SIM').set({ ingest_key: key });
  await createDeviceSecurity(services).execute('owner', 'POST', '/api/devices/PA-SIM/claim', { name: 'Simulated test device' });
  telemetry = createTelemetry(services, { backoffMs: 1, leaseMs: 1000 });
  server = createHttpServer(services, { telemetry });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve)); url = `http://127.0.0.1:${server.address().port}`;
});
afterEach(async () => { await telemetry.stop(); await new Promise((resolve) => server.close(resolve)); });
after(async () => { await env.cleanup(); await deleteApp(app); });
const pause = () => new Promise((resolve) => setTimeout(resolve, 5));

test('simulator -> authenticated HTTP -> durable receipt -> exact history/state/forecast -> authorized client reads', { timeout: 45000 }, async () => {
  const events = generateEvents(); const receipts = [];
  for (const event of events) {
    const receipt = await sendEvent(url, key, event); receipts.push(receipt);
    assert.equal(receipt.status, 'accepted');
    assert.equal((await db.collection('telemetry_events').doc(receipt.receipt_id).get()).exists, true);
    await telemetry.processNext();
    const duplicate = await sendEvent(url, key, event); assert.equal(duplicate.duplicate, true); assert.equal(duplicate.status, 'completed');
  }
  const saved = await db.collection('devices').doc('PA-SIM').collection('history').orderBy('timestamp').get();
  assert.equal(saved.size, 3);
  const state = (await rtdb.ref('devices/PA-SIM/state').get()).val();
  const forecast = (await rtdb.ref('devices/PA-SIM/forecast').get()).val();
  for (const field of ['pm1', 'pm25', 'pm10', 'co2', 'temperature', 'humidity', 'gas_index', 'voc_index', 'mq135_raw', 'timestamp', 'event_id']) assert.equal(state[field], events[2][field]);
  assert.equal(state.particulate_indicator, calculateAqi(events[2]).aqi); assert.equal(forecast.source_event_id, events[2].event_id);
  assert.ok(Number.isFinite(forecast.aqi_10min)); assert.ok(Number.isFinite(forecast.aqi_30min));
  assert.equal(new Set(saved.docs.map((d) => d.data().event_id)).size, 3);
  for (const [i, doc] of saved.docs.entries()) {
    assert.equal(doc.data().pm25, events[i].pm25); assert.equal(doc.data().timestamp, events[i].timestamp);
    assert.equal(doc.data().server_received_at, receipts[i].server_received_at);
  }
  const owner = env.authenticatedContext('owner', { firebase: { sign_in_provider: 'password', identities: {} } });
  await assertSucceeds(owner.firestore().collection('devices/PA-SIM/history').orderBy('timestamp', 'desc').limit(60).get());
  await assertSucceeds(owner.database().ref('devices/PA-SIM/state').once('value'));
  const stranger = env.authenticatedContext('stranger', { firebase: { sign_in_provider: 'password', identities: {} } });
  await assertFails(stranger.firestore().collection('devices/PA-SIM/history').get());
  await assertFails(stranger.database().ref('devices/PA-SIM/state').once('value'));
  await assertFails(owner.firestore().doc('telemetry_events/' + receipts[0].receipt_id).get());
  const out = path.join(__dirname, '../../docs/development/artifacts/telemetry-fixture.json');
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, JSON.stringify({ label: 'SIMULATED TEST DATA — saved by emulator integration', events,
    state, forecast, history: saved.docs.map((d) => d.data()) }, null, 2) + '\n');
});
test('real Firestore/RTDB partial failure and restart replay preserve one history and exact optional absence', { timeout: 45000 }, async () => {
  let broken = true;
  const worker = createTelemetry(services, { backoffMs: 1, fault: async (stage) => { if (stage === 'before_rtdb' && broken) { broken = false; throw Error('injected_rtdb_outage'); } } });
  const event = generateEvents()[0]; delete event.co2;
  await telemetry.accept(event, 'PA-SIM'); await worker.processNext();
  assert.equal((await worker.status('PA-SIM', event.event_id)).status, 'retry');
  assert.equal((await db.collection('devices/PA-SIM/history').get()).size, 1);
  assert.equal((await rtdb.ref('devices/PA-SIM/state/pm25').get()).exists(), false);
  await pause(); const restarted = createTelemetry(services, { backoffMs: 1 }); await restarted.processNext();
  assert.equal((await restarted.status('PA-SIM', event.event_id)).status, 'completed');
  assert.equal((await db.collection('devices/PA-SIM/history').get()).size, 1);
  const state = (await rtdb.ref('devices/PA-SIM/state').get()).val(); assert.equal(state.pm25, event.pm25); assert.equal('co2' in state, false);
});
test('invalid/oversized/unauthorized HTTP is rejected before durable acceptance; conflicting retries are 409', { timeout: 45000 }, async () => {
  const event = generateEvents()[0];
  const post = (payload, credential = key) => fetch(url + '/ingest/PA-SIM', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Device-Key': credential }, body: JSON.stringify(payload) });
  assert.equal((await post(event, 'wrong')).status, 401);
  assert.equal((await post({ ...event, pm25: null })).status, 400);
  assert.equal((await post({ padding: 'x'.repeat(17000) })).status, 413);
  assert.equal((await db.collection('telemetry_events').get()).size, 0);
  assert.equal((await post(event)).status, 202);
  assert.equal((await post({ ...event, pm25: 999 })).status, 409);
  assert.equal((await fetch(url + '/ingest/PA-SIM/events/' + event.event_id, { headers: { 'X-Device-Key': key } })).status, 200);
  assert.equal((await fetch(url + '/ingest/PA-SIM/events/' + event.event_id)).status, 401);
});
test('late arrivals, queue saturation and multiple workers retain timestamp/order fencing', { timeout: 45000 }, async () => {
  const events = generateEvents(); const small = createTelemetry(services, { capacity: 1 });
  await small.accept(events[2], 'PA-SIM'); await assert.rejects(small.accept(events[0], 'PA-SIM'), { status: 503 });
  const another = createTelemetry(services); await Promise.all([small.processNext(), another.processNext()]);
  await small.accept(events[0], 'PA-SIM'); await small.processNext();
  assert.equal((await db.collection('devices/PA-SIM/history').get()).size, 2);
  assert.equal((await rtdb.ref('devices/PA-SIM/state/event_id').get()).val(), events[2].event_id);
});

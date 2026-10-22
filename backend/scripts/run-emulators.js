'use strict';
// Invoke the JS entry point directly: Windows .cmd launchers can return before testing.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '../..');
if (process.argv.includes('--physical') && !process.env.PURA_PHYSICAL_DEVICE) throw Error('Set PURA_PHYSICAL_DEVICE to the connected phone ID');
const receipt = path.join(os.tmpdir(), `pura-security-${crypto.randomUUID()}.json`);
const candidates = [process.env.FIREBASE_CLI_JS,
  path.join(root, 'backend/node_modules/firebase-tools/lib/bin/firebase.js'),
  process.env.APPDATA && path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/bin/firebase.js'),
  '/usr/local/lib/node_modules/firebase-tools/lib/bin/firebase.js',
  '/usr/lib/node_modules/firebase-tools/lib/bin/firebase.js'].filter(Boolean);
const cli = candidates.find((file) => fs.existsSync(file));
if (!cli) throw Error('Install firebase-tools@15.6.0 or set FIREBASE_CLI_JS to its JS entry point');
try {
  const result = spawnSync(process.execPath, [cli, 'emulators:exec', '--project', 'demo-pura-security',
    '--config', path.join(root, 'firebase.json'), '--only', 'firestore,database,auth',
    'node backend/scripts/test-emulators.js'], { cwd: root, stdio: 'inherit',
    env: { ...process.env, PURA_TEST_RECEIPT: receipt, ...(process.argv.includes('--physical') ? { PURA_PHYSICAL_DEVICE: process.env.PURA_PHYSICAL_DEVICE } : {}) } });
  if (result.error) throw result.error;
  if (result.status !== 0 || !fs.existsSync(receipt)) {
    console.error('Emulator tests did not complete successfully; no pass claimed.');
    process.exitCode = result.status || 1;
  }
} finally { if (fs.existsSync(receipt)) fs.unlinkSync(receipt); }

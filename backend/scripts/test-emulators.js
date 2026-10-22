'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const result = spawnSync(process.execPath, ['--test', '--test-concurrency=1', 'backend/test/emulator.test.js', 'backend/test/telemetry-emulator.test.js', 'backend/test/firmware-emulator.test.js'],
  { cwd: path.resolve(__dirname, '../..'), stdio: 'inherit', env: process.env });
if (result.error) throw result.error;
if (result.status === 0 && process.env.PURA_PHYSICAL_DEVICE) {
  const phone = spawnSync(process.execPath, ['backend/scripts/physical-vertical-slice.js'], { cwd: path.resolve(__dirname, '../..'), stdio: 'inherit', env: process.env });
  if (phone.status !== 0) process.exit(phone.status || 1);
}
if (result.status === 0 && process.env.PURA_TEST_RECEIPT) fs.writeFileSync(process.env.PURA_TEST_RECEIPT, JSON.stringify({ passed: true }));
process.exitCode = result.status ?? 1;

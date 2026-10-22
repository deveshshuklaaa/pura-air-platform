'use strict';
// Synthetic host-decoder fixtures, never physical sensor verification.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getDatabase } = require('firebase-admin/database');
const { getAuth } = require('firebase-admin/auth');
const { createTelemetry } = require('../durable-telemetry');
const { createHttpServer } = require('../server');
const { validateEvent } = require('../telemetry-contract');
const { sendEvent } = require('../scripts/simulator');

if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080' ||
    process.env.FIREBASE_DATABASE_EMULATOR_HOST !== '127.0.0.1:19000') throw Error('emulator_only');

test('compiled firmware serializer fixtures use the simulator HTTP path and persist exact values idempotently', { timeout: 45000 }, async () => {
  const projectId = 'demo-pura-security';
  const file = path.join(__dirname, '../../firmware/test/fixtures/telemetry.ndjson');
  const events = fs.readFileSync(file, 'utf8').trim().split(/\r?\n/).map((s) => JSON.parse(s));
  assert.equal(events.length, 3);
  const app = initializeApp({ projectId, databaseURL: `https://${projectId}.firebaseio.com` }, 'firmware-fixture');
  const services = { firestore: getFirestore(app), rtdb: getDatabase(app), auth: getAuth(app) };
  // Fixed synthetic fixture measurement times: acceptance uses a controlled clock,
  // not a mutation of producer identity/time or a production clock bypass.
  const telemetry = createTelemetry(services, { now: () => events[2].timestamp + 1000 });
  const server = createHttpServer(services, { telemetry });
  const id = 'PA-FW-FIXTURE', key = 'NON_PRODUCTION_FIRMWARE_TEST_KEY';
  try {
    await services.firestore.doc('devices/' + id).set({ active: true });
    await services.firestore.doc('device_credentials/' + id).set({ ingest_key: key });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const url = `http://127.0.0.1:${server.address().port}`;
    for (const [i, event] of events.entries()) {
      assert.deepEqual(validateEvent(event, id), event);
      assert.equal(event.sequence, i + 1); assert.equal(event.source, 'hardware');
      assert.equal('gas_index' in event, false); assert.equal('voc_index' in event, false);
      const receipt = await sendEvent(url, key, event);
      assert.equal(receipt.status, 'accepted');
      await telemetry.processNext();
      const again = await sendEvent(url, key, event);
      assert.equal(again.duplicate, true); assert.equal(again.status, 'completed');
      assert.equal(again.receipt_id, receipt.receipt_id);
    }
    const rows = await services.firestore.collection(`devices/${id}/history`).orderBy('timestamp').get();
    assert.equal(rows.size, 3);
    rows.docs.forEach((doc, i) => {
      for (const [field, value] of Object.entries(events[i])) assert.equal(doc.data()[field], value);
    });
    const state = (await services.rtdb.ref(`devices/${id}/state`).get()).val();
    for (const [field, value] of Object.entries(events[2])) assert.equal(state[field], value);
    assert.equal(state.pm25, 20); assert.equal(state.pm10, 45); assert.equal(state.co2, 460); assert.equal(state.mq135_raw, 603);
    const forecast = (await services.rtdb.ref(`devices/${id}/forecast`).get()).val();
    assert.equal(forecast.source_event_id, events[2].event_id);
  } finally {
    await telemetry.stop(); await new Promise((resolve) => server.close(resolve)); await deleteApp(app);
  }
});

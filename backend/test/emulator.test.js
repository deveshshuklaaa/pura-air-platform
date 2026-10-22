'use strict';
const { test: nodeTest, before, after, beforeEach } = require('node:test');
const test = (title, body) => nodeTest(title, { timeout: 45000 }, body);
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getDatabase } = require('firebase-admin/database');
const { createDeviceSecurity } = require('../device-security');

// Fail closed: this file can never fall back to production credentials/endpoints.
const projectId = 'demo-pura-security';
if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18080' || process.env.FIREBASE_DATABASE_EMULATOR_HOST !== '127.0.0.1:19000') {
  throw Error('Start isolated demo emulators with npm run test:emulators; production fallback refused');
}
let env, app, db, rtdb, security, clock;
const user = (uid, anonymous = false) => env.authenticatedContext(uid, { firebase: { sign_in_provider: anonymous ? 'anonymous' : 'password', identities: {} } });
const history = (ctx) => ctx.firestore().doc('devices/PA-TEST/history/reading').get();
const state = (ctx) => ctx.database().ref('devices/PA-TEST/state').once('value');
const controls = () => ({ mode: 'MANUAL', fan_level: 2, mist: false, updated_at: Date.now() });
const claim = () => security.execute('owner', 'POST', '/api/devices/PA-TEST/claim', { name: 'Lab' });
const pairing = () => security.execute('owner', 'POST', '/api/devices/PA-TEST/pairing', {});
const redeem = (uid, code) => security.execute(uid, 'POST', '/api/pairing/redeem', { code, name: 'Shared' });
before(async () => {
  env = await initializeTestEnvironment({ projectId,
    firestore: { host: '127.0.0.1', port: 18080, rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8') },
    database: { host: '127.0.0.1', port: 19000, rules: fs.readFileSync(path.join(__dirname, '../../database.rules.json'), 'utf8') } });
  app = initializeApp({ projectId, databaseURL: `https://${projectId}.firebaseio.com` }, 'security-tests');
  db = getFirestore(app); rtdb = getDatabase(app);
});
beforeEach(async () => {
  await env.clearFirestore(); await env.clearDatabase(); clock = Date.now();
  security = createDeviceSecurity({ firestore: db, rtdb, now: () => clock });
  await db.doc('devices/PA-TEST').set({ active: true, owner_uid: null });
  await db.doc('device_credentials/PA-TEST').set({ ingest_key: 'NON_PRODUCTION_TEST_KEY' });
  await db.doc('devices/PA-TEST/history/reading').set({ aqi: 50, pm25: 12, pm10: 54, server_received_at: clock, timestamp: clock });
  await rtdb.ref('devices/PA-TEST').set({ state: { aqi: 50 }, forecast: { aqi_10min: 55 }, raw: { pm25: 12 } });
});
after(async () => { if (env) await env.cleanup(); if (app) await deleteApp(app); });

test('unauthenticated and anonymous clients cannot access device data, registry or controls', async () => {
  await claim();
  for (const ctx of [env.unauthenticatedContext(), user('owner', true)]) {
    await assertFails(history(ctx)); await assertFails(state(ctx));
    await assertFails(ctx.firestore().doc('devices/PA-TEST').get());
    await assertFails(ctx.database().ref('devices/PA-TEST/forecast').once('value'));
    await assertFails(ctx.database().ref('devices/PA-TEST/controls').once('value'));
    await assertFails(ctx.database().ref('devices/PA-TEST/controls').set(controls()));
  }
});
test('User A cannot fabricate membership or ACL via child, sibling, parent or multipath writes', async () => {
  await claim(); const a = user('attacker');
  await assertFails(a.firestore().doc('users/attacker/devices/PA-TEST').set({ role: 'owner' }));
  await assertFails(a.firestore().doc('users/owner/devices/PA-TEST').set({ role: 'owner' }));
  for (const location of ['device_access/attacker/PA-TEST', 'device_access/attacker', 'authorization/PA-TEST/members/attacker', 'authorization/PA-TEST', 'authorization']) {
    await assertFails(a.database().ref(location).set({ read: true, control: true }));
  }
  await assertFails(a.database().ref().update({ 'authorization/PA-TEST/members/attacker': { read: true }, 'devices/PA-TEST/controls': controls() }));
  await assertFails(a.database().ref('devices/PA-TEST').set({ state: { aqi: 1 }, controls: controls() }));
  await assertFails(state(a)); await assertFails(history(a));
});
test('registered owner reads telemetry, forecast, history and membership and writes controls', async () => {
  await claim(); const owner = user('owner');
  await assertSucceeds(state(owner)); await assertSucceeds(history(owner));
  await assertSucceeds(owner.database().ref('devices/PA-TEST/forecast').once('value'));
  await assertSucceeds(owner.firestore().collection('users/owner/devices').get());
  await assertSucceeds(owner.database().ref('devices/PA-TEST/controls').set(controls()));
});
test('shared user reads allowed data but cannot control or escalate role', async () => {
  await claim(); await redeem('shared', (await pairing()).code); const shared = user('shared');
  await assertSucceeds(state(shared)); await assertSucceeds(history(shared));
  await assertSucceeds(shared.database().ref('devices/PA-TEST/forecast').once('value'));
  await assertFails(shared.database().ref('devices/PA-TEST/controls').set(controls()));
  await assertFails(shared.firestore().doc('users/shared/devices/PA-TEST').update({ role: 'owner' }));
  await assert.rejects(security.execute('shared', 'POST', '/api/devices/PA-TEST/pairing', {}), { status: 403 });
  await assert.rejects(security.execute('shared', 'PATCH', '/api/devices/PA-TEST', { name: 'Hijacked' }), { status: 403 });
});
test('revocation immediately denies new history and telemetry reads after success', async () => {
  await claim(); await redeem('shared', (await pairing()).code);
  await security.execute('owner', 'DELETE', '/api/devices/PA-TEST/members/shared', {});
  await assertFails(history(user('shared'))); await assertFails(state(user('shared')));
  await assertSucceeds(history(user('owner')));
});
test('clients cannot read credentials, registry or pairing hashes or mutate server records', async () => {
  await claim(); const owner = user('owner');
  for (const location of ['devices/PA-TEST', 'device_credentials/PA-TEST', 'pairing_codes/anything', 'security_rate_limits/anything']) {
    await assertFails(owner.firestore().doc(location).get());
    await assertFails(owner.firestore().doc(location).set({ owner_uid: 'owner', added_field: 'x' }));
    await assertFails(owner.firestore().doc(location).delete());
  }
  await assertFails(owner.firestore().collection('pairing_codes').get());
  await assertFails(owner.firestore().doc('users/owner/devices/PA-TEST').delete());
  await assertFails(owner.firestore().doc('devices/PA-TEST/history/reading').set({ aqi: 1 }));
});
test('profile stays private and rejects added fields, invalid types and oversized strings', async () => {
  const a = user('a'); const profile = a.firestore().doc('users/a');
  await assertSucceeds(profile.set({ display_name: 'Alice', about: '' }));
  await assertFails(user('b').firestore().doc('users/a').get());
  await assertFails(profile.update({ role: 'owner' }));
  await assertFails(profile.update({ about: 3 }));
  await assertFails(profile.update({ display_name: 'x'.repeat(101) }));
});
test('strict controls reject extra/missing fields, fractional speed, wrong types and invalid time', async () => {
  await claim(); const ref = user('owner').database().ref('devices/PA-TEST/controls');
  for (const patch of [{ fan_level: 1.5 }, { fan_level: 0 }, { fan_level: 6 }, { fan_level: '2' }, { mode: 'BAD' }, { mist: 1 }, { updated_at: 1 }, { updated_at: Date.now() + 120000 }, { extra: true }]) {
    await assertFails(ref.set({ ...controls(), ...patch }));
  }
  await assertFails(ref.set({ mode: 'AUTO', fan_level: 2, mist: false }));
  await assertFails(ref.remove());
  await assertSucceeds(ref.set(controls())); await assertFails(ref.child('mist').remove());
});
test('expired authorization lease denies even owner controls', async () => {
  await claim(); await rtdb.ref('authorization/PA-TEST/expires_at').set(Date.now() - 1);
  await assertFails(state(user('owner'))); await assertFails(user('owner').database().ref('devices/PA-TEST/controls').set(controls()));
});
test('pairing expiry, concurrent redemption and replay use real Firestore transactions', async () => {
  await claim(); const code = (await pairing()).code;
  console.log('Pairing probe: concurrent redemption started');
  const results = await Promise.allSettled([redeem('first', code), redeem('second', code)]);
  console.log('Pairing probe: concurrent redemption completed');
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  await assert.rejects(redeem('replay', code), { status: 409 });
  console.log('Pairing probe: replay denied');
  const expired = (await pairing()).code; clock += 600001;
  await assert.rejects(redeem('new', expired), { status: 410 });
});
test('real transactions limit guessing and reject codes with changed ownership', async () => {
  await claim(); const code = (await pairing()).code;
  await db.doc('devices/PA-TEST').update({ owner_uid: 'different' });
  await assert.rejects(redeem('shared', code), { status: 403 });
  for (let i = 0; i < 5; i++) await assert.rejects(redeem('guesser', 'wrong'), { status: 400 });
  await assert.rejects(redeem('guesser', 'wrong'), { status: 429 });
});
test('owner removal preserves registry and shared access; owner can restore membership', async () => {
  await claim(); await redeem('shared', (await pairing()).code);
  await security.execute('owner', 'DELETE', '/api/devices/PA-TEST', {});
  assert.equal((await db.doc('devices/PA-TEST').get()).data().owner_uid, 'owner');
  await assertSucceeds(history(user('shared'))); await assertFails(history(user('owner')));
  await claim(); await assertSucceeds(history(user('owner')));
  await security.execute('shared', 'DELETE', '/api/devices/PA-TEST', {});
  await assertFails(history(user('shared'))); await assertSucceeds(history(user('owner')));
});

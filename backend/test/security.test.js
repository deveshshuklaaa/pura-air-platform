'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createDeviceSecurity, authenticate, createIpLimiter } = require('../device-security');
const { createUserApiHandler } = require('../user-api');
const { fixture } = require('./helpers');
const claim = (s, uid = 'owner') => s.execute(uid, 'POST', '/api/devices/PA-TEST/claim', { name: 'Lab' });
const generate = (s) => s.execute('owner', 'POST', '/api/devices/PA-TEST/pairing', {});
const redeem = (s, uid, code) => s.execute(uid, 'POST', '/api/pairing/redeem', { code, name: 'Shared' });
const status = (n) => (error) => error.status === n;

test('ID token is verified with revocation checking; caller UID cannot substitute', async () => {
  let args;
  const auth = { verifyIdToken: async (...a) => { args = a; return { uid: 'verified', firebase: { sign_in_provider: 'password' } }; } };
  assert.equal(await authenticate(auth, 'Bearer TOKEN'), 'verified'); assert.deepEqual(args, ['TOKEN', true]);
  await assert.rejects(authenticate(auth, ''), status(401));
  await assert.rejects(authenticate({ verifyIdToken: async () => { throw Error('secret'); } }, 'Bearer bad'), status(401));
  await assert.rejects(authenticate({ verifyIdToken: async () => ({ uid: 'guest', firebase: { sign_in_provider: 'anonymous' } }) }, 'Bearer guest'), status(403));
});
test('claim requires active provisioned registry and is race safe', async () => {
  const f = fixture(), s = createDeviceSecurity(f);
  const claims = await Promise.allSettled([claim(s), claim(s, 'attacker')]);
  assert.equal(claims.filter((r) => r.status === 'fulfilled').length, 1);
  assert.equal(f.records.get('devices/PA-TEST').owner_uid, 'owner');
  assert.equal(f.acl.get('authorization/PA-TEST').members.owner.control, true);
  await assert.rejects(s.execute('owner', 'POST', '/api/devices/MISSING/claim', { name: 'x' }), status(404));
});
test('identity, roles and extra registry fields cannot be injected', async () => {
  const s = createDeviceSecurity(fixture());
  await assert.rejects(s.execute('attacker', 'POST', '/api/devices/PA-TEST/claim', { name: 'x', uid: 'owner' }), status(400));
  await assert.rejects(s.execute('owner', 'POST', '/api/devices/PA-TEST/claim', { name: 'x', ingest_key: 'x' }), status(400));
  await assert.rejects(s.execute('owner', 'POST', '/api/devices/PA-TEST/claim', { name: 'x'.repeat(101) }), status(400));
});
test('secure code is hash-only, expires, and is single-use under concurrent redemption', async () => {
  const f = fixture(), s = createDeviceSecurity(f); await claim(s); const { code } = await generate(s);
  assert.match(code, /^PC-[A-F0-9]{32}$/); assert.equal(JSON.stringify([...f.records]).includes(code), false);
  const result = await Promise.allSettled([redeem(s, 'shared', code), redeem(s, 'other', code)]);
  assert.equal(result.filter((r) => r.status === 'fulfilled').length, 1);
  await assert.rejects(redeem(s, 'replay', code), status(409));
  assert.equal(f.acl.get('authorization/PA-TEST').members.shared.control, false);
});
test('expired, unknown and invalidated pairing codes fail', async () => {
  const f = fixture(), s = createDeviceSecurity(f); await claim(s); const first = await generate(s); const second = await generate(s);
  await assert.rejects(redeem(s, 'a', first.code), status(410));
  f.advance(600001); await assert.rejects(redeem(s, 'a', second.code), status(410));
  await assert.rejects(redeem(s, 'b', 'PC-' + '0'.repeat(32)), status(404));
});
test('pairing binds to current owner; nonowner cannot issue, rename or revoke', async () => {
  const f = fixture(), s = createDeviceSecurity(f); await claim(s); const { code } = await generate(s);
  await assert.rejects(s.execute('other', 'POST', '/api/devices/PA-TEST/pairing', {}), status(403));
  await assert.rejects(s.execute('other', 'PATCH', '/api/devices/PA-TEST', { name: 'x' }), status(403));
  await assert.rejects(s.execute('other', 'DELETE', '/api/devices/PA-TEST/members/owner', {}), status(403));
  f.records.get('devices/PA-TEST').owner_uid = 'changed';
  await assert.rejects(redeem(s, 'shared', code), status(403));
});
test('bounded guesses are durable across service instances and reset after window', async () => {
  const f = fixture(), s = createDeviceSecurity(f);
  for (let i = 0; i < 5; i++) await assert.rejects(redeem(s, 'guess', 'wrong'), status(400));
  await assert.rejects(redeem(createDeviceSecurity(f), 'guess', 'wrong'), status(429));
  f.advance(900001); await assert.rejects(redeem(s, 'guess', 'wrong'), status(400));
});
test('shared leave and owner removal preserve registry and other memberships', async () => {
  const f = fixture(), s = createDeviceSecurity(f); await claim(s); await redeem(s, 'shared', (await generate(s)).code);
  await s.execute('shared', 'DELETE', '/api/devices/PA-TEST', {});
  assert.equal(f.records.get('devices/PA-TEST').members.owner, 'owner');
  await redeem(s, 'shared', (await generate(s)).code);
  await s.execute('owner', 'DELETE', '/api/devices/PA-TEST', {});
  assert.equal(f.records.get('devices/PA-TEST').owner_uid, 'owner');
  assert.deepEqual(f.records.get('devices/PA-TEST').members, { shared: 'shared' });
  await assert.rejects(generate(s), status(403));
  await claim(s); assert.equal(f.records.get('devices/PA-TEST').members.owner, 'owner');
});
test('owner can list and revoke shares; rename updates mirrors; metadata is whitelisted', async () => {
  const f = fixture(), s = createDeviceSecurity(f); await claim(s); await redeem(s, 'shared', (await generate(s)).code);
  await s.execute('owner', 'PATCH', '/api/devices/PA-TEST', { name: 'Renamed' });
  assert.equal(f.records.get('users/shared/devices/PA-TEST').name, 'Renamed');
  assert.equal((await s.execute('owner', 'GET', '/api/devices/PA-TEST/members', {})).members.length, 2);
  await assert.rejects(s.execute('shared', 'GET', '/api/devices/PA-TEST/members', {}), status(403));
  f.records.get('devices/PA-TEST').ingest_key = 'legacy-secret';
  assert.deepEqual(await s.execute('shared', 'GET', '/api/devices', {}), { devices: [{ device_id: 'PA-TEST', name: 'Renamed', role: 'shared' }] });
  await s.execute('owner', 'DELETE', '/api/devices/PA-TEST/members/shared', {});
  assert.equal(f.acl.get('authorization/PA-TEST').members.shared, undefined);
});
test('fabricated legacy membership is never synchronized into an ACL', async () => {
  const f = fixture(), s = createDeviceSecurity(f); await claim(s);
  f.records.set('users/attacker/devices/PA-TEST', { role: 'owner' }); await s.syncAll();
  assert.equal(f.acl.get('authorization/PA-TEST').members.attacker, undefined);
  assert.deepEqual(await s.execute('attacker', 'GET', '/api/devices', {}), { devices: [] });
});
test('sync failure reports pending, retains canonical revocation, and lease expires', async () => {
  const f = fixture(), s = createDeviceSecurity(f); await claim(s); await redeem(s, 'shared', (await generate(s)).code);
  f.rtdb.ref = () => ({ transaction: async () => { throw Error('offline'); } });
  await assert.rejects(s.execute('owner', 'DELETE', '/api/devices/PA-TEST/members/shared', {}), status(503));
  assert.equal(f.records.get('devices/PA-TEST').members.shared, undefined);
  f.advance(90001); assert.ok(f.acl.get('authorization/PA-TEST').expires_at < f.now());
});
test('IP limiter is bounded and does not trust forwarded identity', () => {
  let now = 0; const limit = createIpLimiter(() => now); for (let i = 0; i < 120; i++) limit('address');
  assert.throws(() => limit('address'), status(429)); now = 60001; limit('address');
});
test('HTTP handler maps token errors, API validation and internal failures without leaks', async () => {
  const f = fixture(); const services = { ...f, auth: { verifyIdToken: async (token) => {
    if (token === 'bad') throw Error('SECRET'); return { uid: token, firebase: { sign_in_provider: token === 'guest' ? 'anonymous' : 'password' } };
  } } };
  const handler = createUserApiHandler(services, { readRequestBody: async (req) => req.body || {}, sendJson: (res, status, data) => Object.assign(res, { status, data }) });
  async function call(token, method, path, body) { const res = { setHeader() {} }; await handler({ headers: { authorization: token ? `Bearer ${token}` : '' }, method, body }, res, path); return res; }
  assert.equal((await call(null, 'GET', '/api/devices')).status, 401);
  assert.equal((await call('bad', 'GET', '/api/devices')).data.error, 'invalid_token');
  assert.equal((await call('guest', 'POST', '/api/devices/PA-TEST/claim', { name: 'x' })).status, 403);
  assert.equal((await call('owner', 'POST', '/api/devices/PA-TEST/claim', { name: 'x', uid: 'attacker' })).status, 400);
  assert.equal((await call('owner', 'POST', '/api/devices/PA-TEST/claim', { name: 'x' })).status, 200);
  f.firestore.runTransaction = async () => { throw Error('SECRET'); };
  const result = await call('owner', 'GET', '/api/devices'); assert.equal(result.status, 500); assert.equal(JSON.stringify(result).includes('SECRET'), false);
});

test('delayed ACL synchronization cannot restore an older membership version', async () => {
  const f = fixture(), s = createDeviceSecurity(f); await claim(s);
  const newer = { version: 100, expires_at: f.now() + 90000, members: {} };
  f.acl.set('authorization/PA-TEST', newer); await s.syncDevice('PA-TEST');
  assert.deepEqual(f.acl.get('authorization/PA-TEST'), newer);
});

test('ingestion looks up only the server-only credential collection', async () => {
  const { getDeviceCredentialRecord } = require('../server'); const f = fixture();
  f.records.set('devices/PRIVATE-TEST', { active: true, ingest_key: 'LEGACY_KEY_NOT_ACCEPTED' });
  f.records.set('device_credentials/PRIVATE-TEST', { ingest_key: 'NEW_TEST_KEY' });
  const record = await getDeviceCredentialRecord(f.firestore, 'PRIVATE-TEST');
  assert.equal(record.ingest_key, 'NEW_TEST_KEY'); assert.equal(record.exists, true);
  f.records.set('devices/LEGACY-ONLY', { active: true, ingest_key: 'LEGACY_KEY_NOT_ACCEPTED' });
  assert.equal((await getDeviceCredentialRecord(f.firestore, 'LEGACY-ONLY')).ingest_key, null);
});

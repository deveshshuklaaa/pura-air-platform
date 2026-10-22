'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { fixture } = require('./helpers');
const { createTelemetry } = require('../durable-telemetry');
const { validateEvent } = require('../telemetry-contract');
const { calculateAqi } = require('../aqi');
const { buildForecast } = require('../forecast');
const { generateEvents, sendEvent, destination } = require('../scripts/simulator');
const make = (f, extra = {}) => createTelemetry(f, { now: f.now, backoffMs: 10, leaseMs: 100, ...extra });
const event = (f, index = 0) => generateEvents({ deviceId: 'PA-TEST', start: f.now() - 3000, count: 3 })[index];
const history = (f) => [...f.records.keys()].filter((k) => k.startsWith('devices/PA-TEST/history/'));

test('strict units/types reject null, strings, Booleans, nonfinite, negative, invalid ID/time and unsupported fields', async () => {
  const f = fixture(), e = event(f);
  for (const value of [null, '', false, NaN, Infinity, -1, 5001]) assert.throws(() => validateEvent({ ...e, pm25: value }, 'PA-TEST'));
  for (const patch of [{ event_id: '../x' }, { timestamp: '123' }, { timestamp: 0 }, { sequence: 1.1 }, { humidity: 101 }, { mq135_raw: 2.5 }, { co2: null }, { unknown: 1 }, { device_id: 'OTHER' }]) assert.throws(() => validateEvent({ ...e, ...patch }, 'PA-TEST'));
  const s = make(f); await assert.rejects(s.accept({ ...e, timestamp: f.now() + 300001 }, 'PA-TEST'), { status: 400 });
  await assert.rejects(s.accept({ ...e, timestamp: f.now() - 31 * 86400000 }, 'PA-TEST'), { status: 400 });
});
test('optional absence is retained, not coerced to zero', () => {
  const f = fixture(), e = event(f); delete e.co2; delete e.gas_index;
  const raw = validateEvent(e, 'PA-TEST'); assert.equal('co2' in raw, false); assert.equal('gas_index' in raw, false);
});
test('prototype known values, fractional gaps, saturation and insufficient data', () => {
  for (const [pm25, pm10, expected] of [[0, 0, 0], [12, 54, 50], [12.05, 54.5, 50], [12.1, 55, 51], [35.4, 154, 100], [5000, 5000, 500]]) assert.equal(calculateAqi({ pm25, pm10 }).aqi, expected);
  for (const pm25 of [null, undefined, NaN, -1, '12']) assert.equal(calculateAqi({ pm25, pm10: 1 }), null);
});
test('202 receipt semantics: acceptance is durable before processing and idempotent/conflict-safe', async () => {
  const f = fixture(), s = make(f), e = event(f); const first = await s.accept(e, 'PA-TEST');
  assert.equal(first.status, 'accepted'); assert.equal(history(f).length, 0);
  const again = await s.accept(e, 'PA-TEST'); assert.equal(again.duplicate, true); assert.equal(again.receipt_id, first.receipt_id);
  await assert.rejects(s.accept({ ...e, pm25: 99 }, 'PA-TEST'), { status: 409 });
  await s.processNext(); assert.equal((await s.status('PA-TEST', e.event_id)).status, 'completed'); assert.equal(history(f).length, 1);
  f.advance(31 * 86400000); assert.equal((await s.accept(e, 'PA-TEST')).duplicate, true);
});
for (const stage of ['before_history', 'after_history', 'before_rtdb', 'after_rtdb', 'before_completion']) {
  test(`retries recover ${stage} without lost or duplicate history`, async () => {
    const f = fixture(); let fail = true;
    const s = make(f, { fault: async (at) => { if (at === stage && fail) { fail = false; throw Error('injected_database_error'); } } });
    const e = event(f); await s.accept(e, 'PA-TEST'); await s.processNext();
    assert.equal((await s.status('PA-TEST', e.event_id)).status, 'retry'); f.advance(11); await s.processNext();
    assert.equal((await s.status('PA-TEST', e.event_id)).status, 'completed'); assert.equal(history(f).length, 1);
    assert.equal(f.acl.get('devices/PA-TEST').state.pm25, e.pm25);
  });
}
test('acceptance failure is not acknowledged or deduped', async () => {
  const f = fixture(), run = f.firestore.runTransaction; f.firestore.runTransaction = async () => { throw Error('offline'); };
  const s = make(f), e = event(f); await assert.rejects(s.accept(e, 'PA-TEST'), { status: 503 });
  f.firestore.runTransaction = run; assert.equal((await s.accept(e, 'PA-TEST')).duplicate, false);
});
test('restart and completion-write failure recover expired lease without duplicate history', async () => {
  const f = fixture(), e = event(f); const s = make(f, { fault: async (stage) => { if (stage === 'finish') throw Error('receipt_write_failed'); } });
  await s.accept(e, 'PA-TEST'); await assert.rejects(s.processNext());
  const restarted = make(f); assert.equal(await restarted.processNext(), false); f.advance(101); await restarted.processNext();
  assert.equal((await restarted.status('PA-TEST', e.event_id)).status, 'completed'); assert.equal(history(f).length, 1);
});
test('capacity, terminal failure, FIFO and safe shutdown remain durable', async () => {
  const f = fixture(), a = event(f), b = event(f, 1), s = make(f, { capacity: 1, maxAttempts: 2, fault: async () => { throw Error('offline'); } });
  await s.accept(a, 'PA-TEST'); await assert.rejects(s.accept(b, 'PA-TEST'), { status: 503 });
  // This fault also interrupts finish: exhausted crashed attempts are terminalized on recovery.
  await assert.rejects(s.processNext()); f.advance(101); await assert.rejects(s.processNext()); f.advance(101); await s.processNext();
  assert.equal((await s.status('PA-TEST', a.event_id)).status, 'failed'); assert.equal((await s.metrics()).durable_pending, 0);
  await s.accept(b, 'PA-TEST'); await s.stop(); await assert.rejects(s.accept(a, 'PA-TEST'), { status: 503 });
  const restarted = make(f); await restarted.processNext(); assert.equal((await restarted.status('PA-TEST', b.event_id)).status, 'completed');
});
test('late events persist in history without regressing live state; forecast uses unique raw timestamps', async () => {
  const f = fixture(), s = make(f), a = event(f, 2), b = event(f, 0);
  await s.accept(a, 'PA-TEST'); await s.processNext(); assert.equal(f.acl.get('devices/PA-TEST').forecast, null);
  await s.accept(b, 'PA-TEST'); await s.processNext();
  assert.equal(history(f).length, 2); assert.equal(f.acl.get('devices/PA-TEST').state.event_id, a.event_id);
  const c = { ...event(f, 1), event_id: 'latest', timestamp: f.now() }; await s.accept(c, 'PA-TEST'); await s.processNext();
  const live = f.acl.get('devices/PA-TEST'); assert.equal(live.state.pm25, c.pm25); assert.equal(live.forecast.source_event_id, c.event_id);
  const points = history(f).map((key) => f.records.get(key)).map((p) => ({ timestamp: p.timestamp, aqi: p.particulate_indicator })).sort((a, b) => a.timestamp - b.timestamp);
  assert.equal(live.forecast.aqi_10min, buildForecast(points, c.timestamp, f.now()).aqi_10min);
});
test('deterministic simulator never changes identity across retries and refuses accidental remote targets', async () => {
  const f = fixture(), e = event(f), bodies = []; assert.deepEqual(event(f), e);
  assert.throws(() => destination('https://production.example')); assert.throws(() => destination('https://user:password@localhost'));
  let attempt = 0; await sendEvent('http://127.0.0.1:1', 'NON_PRODUCTION', e, { delay: async () => {}, fetch: async (_, req) => {
    bodies.push(req.body); return { status: ++attempt < 3 ? 503 : 202, json: async () => ({ status: 'accepted' }) };
  } }); assert.equal(new Set(bodies).size, 1);
});
test('terminal failure replay is explicit, preserves raw identity and reuses one history record', async () => {
  const f = fixture(), e = event(f), s = make(f, { maxAttempts: 1, fault: async (stage) => { if (stage === 'after_history') throw Error('offline'); } });
  await s.accept(e, 'PA-TEST'); await s.processNext();
  assert.equal((await s.status('PA-TEST', e.event_id)).status, 'failed');
  assert.equal((await s.accept(e, 'PA-TEST')).status, 'failed');
  const recovered = make(f); await recovered.replayFailed('PA-TEST', e.event_id); await recovered.processNext();
  assert.equal((await recovered.status('PA-TEST', e.event_id)).status, 'completed');
  assert.equal(history(f).length, 1); assert.equal(f.records.get(history(f)[0]).accepted_order, 1);
  await assert.rejects(recovered.replayFailed('PA-TEST', e.event_id), { status: 409 });
});

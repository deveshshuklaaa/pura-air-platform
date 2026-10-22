'use strict';
const crypto = require('node:crypto');
const { ApiError } = require('./device-security');
const { validateEvent, validateTime, identity, fingerprint } = require('./telemetry-contract');
const { calculateAqi, INDICATOR_VERSION } = require('./aqi');
const { buildForecast } = require('./forecast');
const { saveHistoryRecord, getRecentHistory } = require('./firestore');

function createTelemetry({ firestore, rtdb }, options = {}) {
  const now = options.now || Date.now;
  const capacity = options.capacity ?? 5000, maxAttempts = options.maxAttempts ?? 5;
  const leaseMs = options.leaseMs ?? 60000, backoffMs = options.backoffMs ?? 1000;
  const owner = crypto.randomUUID(), queue = firestore.collection('telemetry_queue').doc('runtime');
  const receiptRef = (order) => firestore.collection('telemetry_events').doc(String(order).padStart(16, '0'));
  const identityRef = (id, event) => firestore.collection('telemetry_identities').doc(identity(id, event));
  const empty = () => ({ next_order: 0, cursor: 0, pending_count: 0, lease_version: 0, lease_until: 0 });
  let closing = false, timer, inFlight = null;
  const errors = {};
  const fault = async (stage, data) => { if (options.fault) await options.fault(stage, data); };

  async function accept(body, id) {
    if (closing) throw new ApiError(503, 'shutting_down');
    const event = validateEvent(body, id), key = identityRef(id, event.event_id), print = fingerprint(event);
    try {
      return await firestore.runTransaction(async (tx) => {
        const previous = (await tx.get(key)).data();
        if (previous) {
          if (previous.fingerprint !== print) throw new ApiError(409, 'event_conflict');
          const receipt = (await tx.get(receiptRef(previous.order))).data();
          return { ...publicReceipt(receipt), duplicate: true };
        }
        validateTime(event, now());
        const q = (await tx.get(queue)).data() || empty();
        if (q.pending_count >= capacity) throw new ApiError(503, 'queue_full');
        const order = q.next_order + 1;
        if (!Number.isSafeInteger(order)) throw new ApiError(503, 'queue_unavailable');
        const receipt = { event, order, identity: identity(id, event.event_id), status: 'accepted', attempts: 0,
          server_received_at: now(), next_attempt_at: 0 };
        tx.create(key, { order, fingerprint: print }); tx.create(receiptRef(order), receipt);
        tx.set(queue, { ...q, next_order: order, pending_count: q.pending_count + 1 });
        return { ...publicReceipt(receipt), duplicate: false };
      });
    } catch (e) { if (e instanceof ApiError) throw e; throw new ApiError(503, 'acceptance_unavailable'); }
  }
  function publicReceipt(r) {
    if (!r) throw new ApiError(503, 'receipt_unavailable');
    return { device_id: r.event.device_id, event_id: r.event.event_id, receipt_id: String(r.order).padStart(16, '0'),
      status: r.status, attempts: r.attempts, server_received_at: r.server_received_at,
      next_attempt_at: r.next_attempt_at, ...(r.failure ? { failure: r.failure } : {}) };
  }
  async function status(id, eventId) {
    const key = (await identityRef(id, eventId).get()).data();
    if (!key) throw new ApiError(404, 'event_not_found');
    return publicReceipt((await receiptRef(key.order).get()).data());
  }
  // Trusted operator interface only; deliberately not exposed by the HTTP API.
  async function replayFailed(id, eventId) {
    if (closing) throw new ApiError(503, 'shutting_down');
    return firestore.runTransaction(async (tx) => {
      const key = identityRef(id, eventId), previous = (await tx.get(key)).data();
      if (!previous) throw new ApiError(404, 'event_not_found');
      const old = (await tx.get(receiptRef(previous.order))).data();
      const q = (await tx.get(queue)).data() || empty();
      if (old.status !== 'failed') throw new ApiError(409, 'terminal_failure_required');
      if (q.pending_count >= capacity) throw new ApiError(503, 'queue_full');
      const order = q.next_order + 1;
      const replay = { ...old, order, original_order: old.original_order || old.order,
        replay_of: old.order, status: 'accepted', attempts: 0, next_attempt_at: 0, failure: null };
      tx.create(receiptRef(order), replay); tx.update(key, { order });
      tx.set(queue, { ...q, next_order: order, pending_count: q.pending_count + 1 });
      return publicReceipt(replay);
    });
  }
  async function acquire() {
    return firestore.runTransaction(async (tx) => {
      const q = (await tx.get(queue)).data();
      if (!q || q.cursor >= q.next_order || (q.lease_until > now() && q.lease_owner !== owner)) return null;
      const ref = receiptRef(q.cursor + 1), r = (await tx.get(ref)).data();
      if (!r) throw Error('receipt_missing');
      if (r.next_attempt_at > now()) return null;
      if (r.attempts >= maxAttempts) {
        tx.update(ref, { status: 'failed', failure: 'retry_budget_exhausted', finished_at: now(), next_attempt_at: 0 });
        tx.update(queue, { cursor: r.order, pending_count: q.pending_count - 1, lease_owner: null, lease_until: 0 });
        return null;
      }
      const token = q.lease_version + 1;
      tx.update(queue, { lease_owner: owner, lease_version: token, lease_until: now() + leaseMs });
      tx.update(ref, { status: 'processing', attempts: r.attempts + 1 });
      return { ...r, attempts: r.attempts + 1, token };
    });
  }
  async function finish(r, error) {
    await fault('finish', r);
    await firestore.runTransaction(async (tx) => {
      const q = (await tx.get(queue)).data();
      if (q.lease_owner !== owner || q.lease_version !== r.token) return;
      const terminal = !!error && r.attempts >= maxAttempts;
      const done = !error || terminal;
      tx.update(receiptRef(r.order), { status: error ? (terminal ? 'failed' : 'retry') : 'completed',
        failure: error ? 'persistence_failed' : null,
        next_attempt_at: error && !terminal ? now() + Math.min(60000, backoffMs * 2 ** (r.attempts - 1)) : 0,
        finished_at: done ? now() : null });
      tx.update(queue, { lease_until: 0, lease_owner: null,
        ...(done ? { cursor: r.order, pending_count: q.pending_count - 1 } : {}) });
    });
  }
  async function persist(r) {
    const event = r.event, result = calculateAqi(event);
    if (!result) throw Error('indicator_unavailable');
    const record = { ...event, schema_version: 2, accepted_order: r.original_order || r.order,
      server_received_at: r.server_received_at, particulate_indicator: result.aqi,
      aqi: result.aqi, indicator_version: INDICATOR_VERSION };
    await fault('before_history', r);
    await saveHistoryRecord(firestore, event.device_id, record);
    await fault('after_history', r);
    const history = await getRecentHistory(firestore, event.device_id, 60);
    const points = history.filter((d) => d.indicator_version === INDICATOR_VERSION
      && Number.isFinite(d.particulate_indicator) && Number.isFinite(d.timestamp))
      .map((d) => ({ timestamp: d.timestamp, aqi: d.particulate_indicator }))
      .sort((a, b) => a.timestamp - b.timestamp);
    const forecast = buildForecast(points, event.timestamp, now());
    await fault('before_rtdb', r);
    await rtdb.ref(`devices/${event.device_id}`).transaction((current) => {
      const old = current?.state;
      if (old && (old.timestamp > event.timestamp || (old.timestamp === event.timestamp && old.accepted_order > record.accepted_order))) return;
      // Preserve controls separately; missing optional measurements do not leak from older samples.
      const controls = {};
      for (const key of ['mode', 'fan_level', 'mist', 'controls_updated_at']) if (old?.[key] !== undefined) controls[key] = old[key];
      return { ...current, state: { ...controls, ...record, last_updated: r.server_received_at },
        forecast: forecast ? { ...forecast, indicator_version: INDICATOR_VERSION, source_event_id: event.event_id } : null };
    });
    await fault('after_rtdb', r);
  }
  async function processNext() {
    if (closing || inFlight) return false;
    const task = (async () => {
      const r = await acquire(); if (!r) return false;
      let error;
      try { await persist(r); await fault('before_completion', r); }
      catch (e) { error = e; errors.persistence_failed = (errors.persistence_failed || 0) + 1; }
      await finish(r, error); return true;
    })();
    inFlight = task;
    try { return await task; } finally { inFlight = null; }
  }
  async function metrics() {
    const q = (await queue.get()).data() || empty();
    return { durable_pending: q.pending_count, accepted_total: q.next_order, finished_total: q.cursor,
      worker_active: !!inFlight, accepting: !closing, capacity, errors: { ...errors } };
  }
  function start() {
    if (timer) return;
    timer = setInterval(() => { processNext().catch(() => { errors.worker_error = (errors.worker_error || 0) + 1; }); }, options.pollMs || 250);
    timer.unref?.();
  }
  async function stop(timeoutMs = 15000) {
    closing = true; clearInterval(timer); timer = null;
    if (!inFlight) return;
    let timeout;
    try { await Promise.race([inFlight, new Promise((resolve) => { timeout = setTimeout(resolve, timeoutMs); })]); }
    finally { clearTimeout(timeout); }
  }
  return { accept, status, replayFailed, processNext, metrics, start, stop };
}
module.exports = { createTelemetry };

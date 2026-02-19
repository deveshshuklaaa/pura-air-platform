'use strict';

const crypto = require('node:crypto');
const http = require('node:http');

const { initFirebase } = require('./firebase');
const { calculateAqi, isValidNumber } = require('./aqi');
const {
  saveHistoryRecord,
  getRecentHistory,
  saveDeadLetterRecord,
  cleanupOldHistoryForDevice,
} = require('./firestore');
const { buildForecast } = require('./forecast');

const PORT = Number.parseInt(process.env.PORT || '8080', 10);
const HOST = process.env.HOST || '0.0.0.0';
const BODY_LIMIT_BYTES = Number.parseInt(process.env.BODY_LIMIT_BYTES || '16384', 10);
const WORKER_CONCURRENCY = Math.max(1, Number.parseInt(process.env.WORKER_CONCURRENCY || '4', 10));
const MAX_QUEUE_SIZE = Math.max(10, Number.parseInt(process.env.MAX_QUEUE_SIZE || '5000', 10));
const HISTORY_CACHE_LIMIT = Math.max(10, Number.parseInt(process.env.HISTORY_CACHE_LIMIT || '60', 10));

const ENABLE_DEVICE_DISCOVERY = process.env.ENABLE_DEVICE_DISCOVERY !== 'false';
const ENABLE_RTDB_RAW_LISTENER = process.env.ENABLE_RTDB_RAW_LISTENER === 'true';
const ENABLE_RTDB_CONTROLS_LISTENER = process.env.ENABLE_RTDB_CONTROLS_LISTENER !== 'false';

const INGEST_SHARED_KEY = process.env.INGEST_API_KEY || '';
const ALLOW_UNAUTH_INGEST = process.env.ALLOW_UNAUTH_INGEST === 'true';
const DEVICE_KEY_CACHE_TTL_MS = Math.max(
  30000,
  Number.parseInt(process.env.DEVICE_KEY_CACHE_TTL_MS || '300000', 10)
);

const ACCESS_SYNC_INTERVAL_MS = Math.max(
  0,
  Number.parseInt(process.env.ACCESS_SYNC_INTERVAL_MS || '300000', 10)
);
const HISTORY_RETENTION_DAYS = Math.max(
  0,
  Number.parseInt(process.env.HISTORY_RETENTION_DAYS || '30', 10)
);
const HISTORY_RETENTION_INTERVAL_MS = Math.max(
  0,
  Number.parseInt(process.env.HISTORY_RETENTION_INTERVAL_MS || '3600000', 10)
);

const EVENT_KEY_TTL_MS = Math.max(
  60000,
  Number.parseInt(process.env.EVENT_KEY_TTL_MS || '21600000', 10)
);

const deviceListeners = new Map();
const latestControls = new Map();
const lastRawSignatures = new Map();
const historyCache = new Map();
const errorCounters = new Map();
const deviceKeyCache = new Map();
const seenEventKeys = new Map();

const rawQueue = [];
const busyDevices = new Set();
let activeWorkers = 0;
let runtimeServices = null;
let accessSyncTimer = null;
let historyRetentionTimer = null;
let eventKeyCleanupTimer = null;
let httpServer = null;

function log(level, message, meta = {}) {
  console.log(
    JSON.stringify({
      timestamp: new Date().toISOString(),
      level,
      message,
      ...meta,
    })
  );
}

function incrementError(name) {
  const current = errorCounters.get(name) || 0;
  errorCounters.set(name, current + 1);
}

function toNumberOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function toIntOrNull(value) {
  const parsed = Number.parseInt(String(value), 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeRawPayload(payload) {
  if (!payload || typeof payload !== 'object') {
    return null;
  }

  const normalized = {
    pm1: toNumberOrNull(payload.pm1),
    pm25: toNumberOrNull(payload.pm25),
    pm10: toNumberOrNull(payload.pm10),
    temperature: toNumberOrNull(payload.temperature),
    humidity: toNumberOrNull(payload.humidity),
    co2: toNumberOrNull(payload.co2),
    // Accept multiple producer naming variants for gas/VOC inputs.
    gas_index: toNumberOrNull(payload.gas_index ?? payload.gasIndex ?? payload.mq135_index),
    voc_index: toNumberOrNull(payload.voc_index ?? payload.vocIndex ?? payload.voc ?? payload.tvoc),
    mq135_raw: toNumberOrNull(payload.mq135_raw ?? payload.mq135Raw),
    timestamp: toNumberOrNull(payload.timestamp),
    sequence: toIntOrNull(payload.sequence ?? payload.seq ?? payload.reading_id),
    idempotency_key:
      typeof payload.idempotency_key === 'string' ? payload.idempotency_key.trim() : null,
  };

  if (!isValidNumber(normalized.pm25) || !isValidNumber(normalized.pm10)) {
    return null;
  }

  normalized.timestamp = isValidNumber(normalized.timestamp) ? normalized.timestamp : Date.now();
  normalized.sequence = Number.isInteger(normalized.sequence) ? normalized.sequence : null;

  return normalized;
}

function normalizeControlsPayload(payload) {
  if (!payload || typeof payload !== 'object') {
    return null;
  }

  const mode = typeof payload.mode === 'string' ? payload.mode.toUpperCase() : null;
  const fanLevel = toNumberOrNull(payload.fan_level);
  const mist = typeof payload.mist === 'boolean' ? payload.mist : null;

  return {
    mode: mode === 'MANUAL' ? 'MANUAL' : 'AUTO',
    fan_level: Number.isFinite(fanLevel) ? Math.max(1, Math.min(5, Math.round(fanLevel))) : 1,
    mist: mist ?? false,
    updated_at: Date.now(),
  };
}

function buildRawSignature(raw) {
  return [
    raw.pm1,
    raw.pm25,
    raw.pm10,
    raw.temperature,
    raw.humidity,
    raw.co2,
    raw.gas_index,
    raw.voc_index,
    raw.mq135_raw,
    raw.timestamp,
    raw.sequence,
  ].join('|');
}

function hashPayloadSignature(deviceId, raw) {
  const payload = [
    deviceId,
    raw.pm1,
    raw.pm25,
    raw.pm10,
    raw.temperature,
    raw.humidity,
    raw.co2,
    raw.gas_index,
    raw.voc_index,
    raw.mq135_raw,
    raw.timestamp,
    raw.sequence,
  ].join('|');
  return crypto.createHash('sha1').update(payload).digest('hex');
}

function buildEventKey(deviceId, raw) {
  if (raw.idempotency_key) {
    return `${deviceId}:${raw.idempotency_key}`;
  }

  if (Number.isInteger(raw.sequence)) {
    return `${deviceId}:${raw.timestamp}:${raw.sequence}`;
  }

  return `${deviceId}:sig:${hashPayloadSignature(deviceId, raw)}`;
}

function isSeenEventKey(eventKey, now = Date.now()) {
  const expiresAt = seenEventKeys.get(eventKey);
  if (!Number.isFinite(expiresAt)) {
    return false;
  }
  return expiresAt > now;
}

function rememberEventKey(eventKey, now = Date.now()) {
  seenEventKeys.set(eventKey, now + EVENT_KEY_TTL_MS);
}

function cleanupEventKeys() {
  const now = Date.now();
  for (const [key, expiresAt] of seenEventKeys.entries()) {
    if (expiresAt <= now) {
      seenEventKeys.delete(key);
    }
  }
}

async function getForecastHistory(firestore, deviceId) {
  let cached = historyCache.get(deviceId);
  if (cached) {
    return cached;
  }

  const recent = await getRecentHistory(firestore, deviceId, HISTORY_CACHE_LIMIT);
  cached = recent.map((item) => ({
    timestamp: item.server_received_at,
    aqi: item.aqi,
  }));
  historyCache.set(deviceId, cached);
  return cached;
}

function appendForecastPoint(deviceId, point) {
  let points = historyCache.get(deviceId);
  if (!Array.isArray(points)) {
    points = [];
  }
  points.push(point);
  while (points.length > HISTORY_CACHE_LIMIT) {
    points.shift();
  }
  historyCache.set(deviceId, points);
  return points;
}

async function processRawReading(services, event) {
  const { rtdb, firestore } = services;
  const { deviceId, payload, source = 'unknown', receivedAt = Date.now() } = event;

  const raw = normalizeRawPayload(payload);
  if (!raw) {
    incrementError('invalid_raw_payload');
    await saveDeadLetterRecord(firestore, {
      device_id: deviceId,
      source,
      reason: 'invalid_raw_payload',
      payload,
      received_at: receivedAt,
    });
    return;
  }

  const eventKey = event.eventKey || buildEventKey(deviceId, raw);
  if (isSeenEventKey(eventKey, receivedAt)) {
    return;
  }

  const signature = buildRawSignature(raw);
  if (lastRawSignatures.get(deviceId) === signature) {
    return;
  }

  lastRawSignatures.set(deviceId, signature);
  rememberEventKey(eventKey, receivedAt);

  const aqiResult = calculateAqi({ pm25: raw.pm25, pm10: raw.pm10 });
  if (!aqiResult) {
    incrementError('aqi_calculation_failed');
    await saveDeadLetterRecord(firestore, {
      device_id: deviceId,
      source,
      reason: 'aqi_calculation_failed',
      payload,
      received_at: receivedAt,
    });
    return;
  }

  const serverReceivedAt = Number.isFinite(receivedAt) ? receivedAt : Date.now();
  const historyRecord = {
    pm1: raw.pm1,
    pm25: raw.pm25,
    pm10: raw.pm10,
    gas_index: raw.gas_index,
    voc_index: raw.voc_index,
    mq135_raw: raw.mq135_raw,
    aqi: aqiResult.aqi,
    dominant_pollutant: aqiResult.dominantPollutant,
    timestamp: raw.timestamp,
    server_received_at: serverReceivedAt,
    source,
    sequence: raw.sequence,
    idempotency_key: eventKey,
  };

  await saveHistoryRecord(firestore, deviceId, historyRecord);

  await getForecastHistory(firestore, deviceId);
  const forecastPoints = appendForecastPoint(deviceId, {
    timestamp: serverReceivedAt,
    aqi: aqiResult.aqi,
  });
  const forecast = buildForecast(forecastPoints, serverReceivedAt);

  const state = {
    aqi: aqiResult.aqi,
    dominant_pollutant: aqiResult.dominantPollutant,
    pm1: raw.pm1,
    pm25: raw.pm25,
    pm10: raw.pm10,
    temperature: raw.temperature,
    humidity: raw.humidity,
    co2: raw.co2,
    gas_index: raw.gas_index,
    voc_index: raw.voc_index,
    mq135_raw: raw.mq135_raw,
    device_timestamp: raw.timestamp,
    last_updated: serverReceivedAt,
  };

  const controls = latestControls.get(deviceId);
  if (controls) {
    state.mode = controls.mode;
    state.fan_level = controls.fan_level;
    state.mist = controls.mist;
    state.controls_updated_at = controls.updated_at;
  }

  const updates = {
    state,
  };

  if (forecast) {
    updates.forecast = forecast;
  }

  await rtdb.ref(`devices/${deviceId}`).update(updates);
}

async function processControlUpdate({ rtdb }, deviceId, payload) {
  const controls = normalizeControlsPayload(payload);
  if (!controls) {
    return;
  }

  latestControls.set(deviceId, controls);
  await rtdb.ref(`devices/${deviceId}/state`).update({
    mode: controls.mode,
    fan_level: controls.fan_level,
    mist: controls.mist,
    controls_updated_at: controls.updated_at,
  });
}

function enqueueRawEvent(event) {
  if (rawQueue.length >= MAX_QUEUE_SIZE) {
    incrementError('raw_queue_full');
    if (runtimeServices) {
      saveDeadLetterRecord(runtimeServices.firestore, {
        device_id: event.deviceId,
        source: event.source || 'unknown',
        reason: 'raw_queue_full',
        payload: event.payload,
        received_at: event.receivedAt || Date.now(),
      }).catch((error) => {
        log('error', 'failed to save queue overflow dead-letter', {
          deviceId: event.deviceId,
          error: error.message,
        });
      });
    }
    return false;
  }

  rawQueue.push(event);
  drainRawQueue();
  return true;
}

function drainRawQueue() {
  while (activeWorkers < WORKER_CONCURRENCY) {
    const nextIndex = rawQueue.findIndex((item) => !busyDevices.has(item.deviceId));
    if (nextIndex === -1) {
      return;
    }

    const [event] = rawQueue.splice(nextIndex, 1);
    activeWorkers += 1;
    busyDevices.add(event.deviceId);

    processRawReading(runtimeServices, event)
      .catch((error) => {
        incrementError('raw_processing_error');
        log('error', 'raw processing error', {
          deviceId: event.deviceId,
          error: error.message,
        });
      })
      .finally(() => {
        busyDevices.delete(event.deviceId);
        activeWorkers -= 1;
        setImmediate(drainRawQueue);
      });
  }
}

function attachDeviceListeners(services, deviceId) {
  if (!deviceId || deviceListeners.has(deviceId)) {
    return;
  }

  const listener = {};

  if (ENABLE_RTDB_RAW_LISTENER) {
    const rawRef = services.rtdb.ref(`devices/${deviceId}/raw`);
    const rawHandler = (snapshot) => {
      enqueueRawEvent({
        deviceId,
        payload: snapshot.val(),
        source: 'rtdb_raw',
        receivedAt: Date.now(),
      });
    };

    rawRef.on('value', rawHandler, (error) => {
      incrementError('raw_listener_error');
      log('error', 'raw listener error', {
        deviceId,
        error: error.message,
      });
    });

    listener.rawRef = rawRef;
    listener.rawHandler = rawHandler;
  }

  if (ENABLE_RTDB_CONTROLS_LISTENER) {
    const controlsRef = services.rtdb.ref(`devices/${deviceId}/controls`);
    const controlsHandler = (snapshot) => {
      processControlUpdate(services, deviceId, snapshot.val()).catch((error) => {
        incrementError('controls_processing_error');
        log('error', 'controls processing error', {
          deviceId,
          error: error.message,
        });
      });
    };

    controlsRef.on('value', controlsHandler, (error) => {
      incrementError('controls_listener_error');
      log('error', 'controls listener error', {
        deviceId,
        error: error.message,
      });
    });

    listener.controlsRef = controlsRef;
    listener.controlsHandler = controlsHandler;
  }

  deviceListeners.set(deviceId, listener);
  log('info', 'device listeners attached', {
    deviceId,
    rawEnabled: ENABLE_RTDB_RAW_LISTENER,
    controlsEnabled: ENABLE_RTDB_CONTROLS_LISTENER,
  });
}

function detachDeviceListeners(deviceId) {
  const listener = deviceListeners.get(deviceId);
  if (!listener) {
    return;
  }

  if (listener.rawRef && listener.rawHandler) {
    listener.rawRef.off('value', listener.rawHandler);
  }
  if (listener.controlsRef && listener.controlsHandler) {
    listener.controlsRef.off('value', listener.controlsHandler);
  }

  deviceListeners.delete(deviceId);
  historyCache.delete(deviceId);
  lastRawSignatures.delete(deviceId);
  latestControls.delete(deviceId);
  deviceKeyCache.delete(deviceId);
  log('info', 'device listeners detached', { deviceId });
}

function startDeviceDiscovery(services) {
  if (!ENABLE_DEVICE_DISCOVERY) {
    return;
  }

  const devicesRef = services.rtdb.ref('devices');

  devicesRef.on('child_added', (snapshot) => {
    attachDeviceListeners(services, snapshot.key);
  });

  devicesRef.on('child_removed', (snapshot) => {
    detachDeviceListeners(snapshot.key);
  });

  log('info', 'device discovery started');
}

function timingSafeEqual(left, right) {
  if (typeof left !== 'string' || typeof right !== 'string') {
    return false;
  }
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  if (leftBuffer.length !== rightBuffer.length) {
    return false;
  }
  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

async function getDeviceCredentialRecord(firestore, deviceId) {
  const cached = deviceKeyCache.get(deviceId);
  const now = Date.now();
  if (cached && cached.expiresAt > now) {
    return cached.value;
  }

  const snapshot = await firestore.collection('devices').doc(deviceId).get();
  const data = snapshot.exists ? snapshot.data() || {} : {};
  const value = {
    exists: snapshot.exists,
    ingest_key: typeof data.ingest_key === 'string' ? data.ingest_key : null,
  };
  deviceKeyCache.set(deviceId, {
    expiresAt: now + DEVICE_KEY_CACHE_TTL_MS,
    value,
  });
  return value;
}

function extractProvidedKey(req) {
  const direct = req.headers['x-device-key'];
  if (typeof direct === 'string' && direct.trim()) {
    return direct.trim();
  }

  const authHeader = req.headers.authorization;
  if (typeof authHeader === 'string') {
    const match = authHeader.match(/^Bearer\s+(.+)$/i);
    if (match && match[1]) {
      return match[1].trim();
    }
  }

  return '';
}

async function authenticateIngestRequest(services, deviceId, providedKey) {
  if (ALLOW_UNAUTH_INGEST) {
    return true;
  }

  if (!providedKey) {
    return false;
  }

  const deviceRecord = await getDeviceCredentialRecord(services.firestore, deviceId);
  if (!deviceRecord.exists) {
    return false;
  }

  if (INGEST_SHARED_KEY && timingSafeEqual(providedKey, INGEST_SHARED_KEY)) {
    return true;
  }

  if (deviceRecord.ingest_key && timingSafeEqual(providedKey, deviceRecord.ingest_key)) {
    return true;
  }

  return false;
}

function readRequestBody(req) {
  return new Promise((resolve, reject) => {
    let totalBytes = 0;
    const chunks = [];

    req.on('data', (chunk) => {
      totalBytes += chunk.length;
      if (totalBytes > BODY_LIMIT_BYTES) {
        reject(Object.assign(new Error('request_body_too_large'), { statusCode: 413 }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });

    req.on('end', () => {
      if (chunks.length === 0) {
        resolve({});
        return;
      }

      try {
        const rawBody = Buffer.concat(chunks).toString('utf8');
        const parsed = JSON.parse(rawBody);
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
          reject(Object.assign(new Error('request_body_must_be_json_object'), { statusCode: 400 }));
          return;
        }
        resolve(parsed);
      } catch (error) {
        reject(Object.assign(new Error(`invalid_json: ${error.message}`), { statusCode: 400 }));
      }
    });

    req.on('error', reject);
  });
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify(payload));
}

async function handleIngestRequest(req, res, services, deviceId) {
  const receivedAt = Date.now();
  const providedKey = extractProvidedKey(req);

  const authorized = await authenticateIngestRequest(services, deviceId, providedKey);
  if (!authorized) {
    sendJson(res, 401, { error: 'unauthorized' });
    return;
  }

  let payload;
  try {
    payload = await readRequestBody(req);
  } catch (error) {
    sendJson(res, error.statusCode || 400, { error: error.message });
    return;
  }

  const provisionalRaw = normalizeRawPayload(payload);
  const eventKey = provisionalRaw ? buildEventKey(deviceId, provisionalRaw) : null;

  const accepted = enqueueRawEvent({
    deviceId,
    payload,
    source: 'http_ingest',
    eventKey,
    receivedAt,
  });

  if (!accepted) {
    sendJson(res, 503, { error: 'queue_full' });
    return;
  }

  sendJson(res, 202, {
    status: 'queued',
    device_id: deviceId,
    queue_depth: rawQueue.length,
  });
}

async function syncDeviceAccess(services) {
  const { firestore, rtdb } = services;
  const usersSnapshot = await firestore.collection('users').get();
  let syncedUsers = 0;

  for (const userDoc of usersSnapshot.docs) {
    const uid = userDoc.id;
    const devicesSnapshot = await firestore.collection('users').doc(uid).collection('devices').get();
    const accessMap = {};
    for (const deviceDoc of devicesSnapshot.docs) {
      accessMap[deviceDoc.id] = true;
    }
    await rtdb.ref(`device_access/${uid}`).set(accessMap);
    syncedUsers += 1;
  }

  log('info', 'device access sync completed', { users: syncedUsers });
}

async function runHistoryRetention(services) {
  if (HISTORY_RETENTION_DAYS <= 0) {
    return;
  }

  const cutoffTimestamp = Date.now() - HISTORY_RETENTION_DAYS * 24 * 60 * 60 * 1000;
  const deviceRefs = await services.firestore.collection('devices').listDocuments();
  let totalDeleted = 0;

  for (const deviceRef of deviceRefs) {
    while (true) {
      const deleted = await cleanupOldHistoryForDevice(
        services.firestore,
        deviceRef.id,
        cutoffTimestamp,
        250
      );
      totalDeleted += deleted;
      if (deleted < 250) {
        break;
      }
    }
  }

  log('info', 'history retention run completed', {
    devices: deviceRefs.length,
    deleted: totalDeleted,
    cutoffTimestamp,
  });
}

function buildMetrics() {
  return {
    queue_depth: rawQueue.length,
    active_workers: activeWorkers,
    worker_concurrency: WORKER_CONCURRENCY,
    busy_devices: busyDevices.size,
    seen_event_keys: seenEventKeys.size,
    listeners: deviceListeners.size,
    errors: Object.fromEntries(errorCounters.entries()),
  };
}

function createHttpServer(services) {
  return http.createServer(async (req, res) => {
    const method = req.method || 'GET';
    const rawUrl = req.url || '/';
    const parsedUrl = new URL(rawUrl, `http://${req.headers.host || 'localhost'}`);
    const pathname = parsedUrl.pathname;

    try {
      if (method === 'GET' && pathname === '/health') {
        sendJson(res, 200, {
          ok: true,
          queue_depth: rawQueue.length,
          workers: activeWorkers,
        });
        return;
      }

      if (method === 'GET' && pathname === '/metrics') {
        sendJson(res, 200, buildMetrics());
        return;
      }

      const ingestMatch = method === 'POST' ? pathname.match(/^\/ingest\/([^/]+)$/) : null;
      if (ingestMatch && ingestMatch[1]) {
        const deviceId = decodeURIComponent(ingestMatch[1]);
        await handleIngestRequest(req, res, services, deviceId);
        return;
      }

      sendJson(res, 404, { error: 'not_found' });
    } catch (error) {
      incrementError('http_handler_error');
      log('error', 'http handler error', {
        path: pathname,
        error: error.message,
      });
      sendJson(res, 500, { error: 'internal_error' });
    }
  });
}

function startTimers(services) {
  eventKeyCleanupTimer = setInterval(cleanupEventKeys, 60000);

  if (ACCESS_SYNC_INTERVAL_MS > 0) {
    syncDeviceAccess(services).catch((error) => {
      incrementError('device_access_initial_sync_error');
      log('error', 'initial access sync failed', { error: error.message });
    });

    accessSyncTimer = setInterval(() => {
      syncDeviceAccess(services).catch((error) => {
        incrementError('device_access_sync_error');
        log('error', 'access sync failed', { error: error.message });
      });
    }, ACCESS_SYNC_INTERVAL_MS);
  }

  if (HISTORY_RETENTION_DAYS > 0 && HISTORY_RETENTION_INTERVAL_MS > 0) {
    runHistoryRetention(services).catch((error) => {
      incrementError('history_retention_initial_error');
      log('error', 'initial history retention failed', { error: error.message });
    });

    historyRetentionTimer = setInterval(() => {
      runHistoryRetention(services).catch((error) => {
        incrementError('history_retention_error');
        log('error', 'history retention failed', { error: error.message });
      });
    }, HISTORY_RETENTION_INTERVAL_MS);
  }
}

function stopTimers() {
  if (eventKeyCleanupTimer) {
    clearInterval(eventKeyCleanupTimer);
    eventKeyCleanupTimer = null;
  }
  if (accessSyncTimer) {
    clearInterval(accessSyncTimer);
    accessSyncTimer = null;
  }
  if (historyRetentionTimer) {
    clearInterval(historyRetentionTimer);
    historyRetentionTimer = null;
  }
}

async function shutdown() {
  stopTimers();
  for (const deviceId of deviceListeners.keys()) {
    detachDeviceListeners(deviceId);
  }
  if (httpServer) {
    await new Promise((resolve) => httpServer.close(resolve));
  }
}

async function start() {
  runtimeServices = initFirebase();

  process.on('uncaughtException', (error) => {
    incrementError('uncaught_exception');
    log('error', 'uncaught exception', { error: error.message });
  });

  process.on('unhandledRejection', (error) => {
    incrementError('unhandled_rejection');
    log('error', 'unhandled rejection', {
      error: error instanceof Error ? error.message : String(error),
    });
  });

  process.on('SIGINT', () => {
    shutdown()
      .then(() => process.exit(0))
      .catch(() => process.exit(1));
  });

  process.on('SIGTERM', () => {
    shutdown()
      .then(() => process.exit(0))
      .catch(() => process.exit(1));
  });

  startDeviceDiscovery(runtimeServices);
  startTimers(runtimeServices);

  httpServer = createHttpServer(runtimeServices);
  await new Promise((resolve) => {
    httpServer.listen(PORT, HOST, resolve);
  });

  log('info', 'PURA AIR backend started', {
    host: HOST,
    port: PORT,
    rawListener: ENABLE_RTDB_RAW_LISTENER,
    controlsListener: ENABLE_RTDB_CONTROLS_LISTENER,
    workerConcurrency: WORKER_CONCURRENCY,
    maxQueueSize: MAX_QUEUE_SIZE,
    accessSyncIntervalMs: ACCESS_SYNC_INTERVAL_MS,
    retentionDays: HISTORY_RETENTION_DAYS,
  });
}

start().catch((error) => {
  log('error', 'startup failure', { error: error.message });
  process.exitCode = 1;
});

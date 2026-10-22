'use strict';
const http = require('node:http');
const crypto = require('node:crypto');
const { initFirebase } = require('./firebase');
const { ApiError, identifier, createDeviceSecurity } = require('./device-security');
const { createUserApiHandler } = require('./user-api');
const { createTelemetry } = require('./durable-telemetry');
const BODY_LIMIT_BYTES = 16384;
const INGEST_SHARED_KEY = process.env.INGEST_API_KEY || '';
const DEVICE_KEY_CACHE_TTL_MS = 300000;
const deviceKeyCache = new Map();
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

  identifier(deviceId);
  const registry = await firestore.collection('devices').doc(deviceId).get();
  const snapshot = await firestore.collection('device_credentials').doc(deviceId).get();
  const data = snapshot.exists ? snapshot.data() || {} : {};
  const value = {
    exists: registry.exists && registry.data()?.active === true,
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
    let size = 0, overflow = false; const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > BODY_LIMIT_BYTES) {
        overflow = true; chunks.length = 0;
        reject(Object.assign(new Error('body_too_large'), { statusCode: 413 }));
      } else if (!overflow) chunks.push(chunk);
    });
    req.on('end', () => {
      if (overflow) return;
      try {
        const value = chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {};
        if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error('invalid');
        resolve(value);
      } catch { reject(Object.assign(new Error('invalid_json'), { statusCode: 400 })); }
    });
    req.on('error', reject);
    req.on('aborted', () => reject(Object.assign(new Error('request_aborted'), { statusCode: 400 })));
  });
}
function sendJson(res, status, value) {
  if (res.destroyed || res.headersSent) return;
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(value));
}
function createHttpServer(services, options = {}) {
  const telemetry = options.telemetry || createTelemetry(services);
  const userApi = createUserApiHandler(services, { readRequestBody, sendJson });
  const server = http.createServer(async (req, res) => {
    try {
      const pathname = new URL(req.url || '/', 'http://localhost').pathname;
      if (pathname.startsWith('/api/')) { await userApi(req, res, pathname); return; }
      if (req.method === 'GET' && (pathname === '/health' || pathname === '/metrics')) {
        try { const metrics = await telemetry.metrics(); sendJson(res, 200, pathname === '/health' ? { ok: metrics.accepting, ...metrics } : metrics); }
        catch { sendJson(res, 503, { ok: false, error: 'database_unavailable' }); }
        return;
      }
      const match = pathname.match(/^\/ingest\/([A-Za-z0-9_-]{1,128})(?:\/events\/([A-Za-z0-9_-]{1,96}))?$/);
      if (match && ((req.method === 'POST' && !match[2]) || (req.method === 'GET' && match[2]))) {
        const id = identifier(match[1]);
        if (!await authenticateIngestRequest(services, id, extractProvidedKey(req))) throw new ApiError(401, 'unauthorized');
        if (req.method === 'GET') sendJson(res, 200, await telemetry.status(id, match[2]));
        else sendJson(res, 202, await telemetry.accept(await readRequestBody(req), id));
        return;
      }
      sendJson(res, 404, { error: 'not_found' });
    } catch (e) {
      const status = e instanceof ApiError ? e.status : (e.statusCode || 503);
      if (status === 503) res.setHeader('Retry-After', '1');
      sendJson(res, status, { error: e instanceof ApiError ? e.code : (e.statusCode ? e.message : 'service_unavailable') });
    }
  });
  server.requestTimeout = 15000; server.headersTimeout = 10000;
  server.telemetry = telemetry;
  return server;
}
function attachControls(services) {
  const listeners = new Map(); const devices = services.rtdb.ref('devices');
  const added = (snapshot) => {
    const id = snapshot.key; if (listeners.has(id)) return;
    const ref = services.rtdb.ref('devices/' + id + '/controls');
    const listener = async (snap) => {
      const controls = snap.val(); if (!controls) return;
      // Retained Phase 1A cloud request echo; this is not physical confirmation.
      try { await services.rtdb.ref('devices/' + id + '/state').update({ mode: controls.mode,
        fan_level: controls.fan_level, mist: controls.mist, controls_updated_at: controls.updated_at }); }
      catch { console.error('control_state_update_failed'); }
    };
    ref.on('value', listener); listeners.set(id, { ref, listener });
  };
  devices.on('child_added', added);
  return () => { devices.off('child_added', added); for (const { ref, listener } of listeners.values()) ref.off('value', listener); };
}
async function start() {
  if (process.env.ENABLE_RTDB_RAW_LISTENER === 'true' || process.env.ALLOW_UNAUTH_INGEST === 'true') {
    throw Error('Legacy raw/unauthenticated ingestion is unsupported; use authenticated telemetry v2 HTTP');
  }
  const services = initFirebase(), security = createDeviceSecurity(services);
  const server = createHttpServer(services);
  const interval = Number(process.env.ACCESS_SYNC_INTERVAL_MS || 30000);
  const sync = () => security.syncAll().catch(() => console.error('access_sync_failed'));
  await sync(); const syncTimer = interval > 0 ? setInterval(sync, interval) : null;
  const detach = process.env.ENABLE_RTDB_CONTROLS_LISTENER === 'false' ? () => {} : attachControls(services);
  server.telemetry.start();
  await new Promise((resolve) => server.listen(Number(process.env.PORT || 8080), process.env.HOST || '0.0.0.0', resolve));
  let stopping = false;
  const shutdown = async () => {
    if (stopping) return; stopping = true; clearInterval(syncTimer); detach();
    const stopped = new Promise((resolve) => server.close(resolve));
    await server.telemetry.stop(); await stopped;
    process.exit(0);
  };
  process.on('SIGINT', shutdown); process.on('SIGTERM', shutdown);
  console.log('PURA AIR HTTP backend ready (durable telemetry v2)');
  return server;
}
if (require.main === module) start().catch(() => { console.error('backend_startup_failed'); process.exitCode = 1; });
module.exports = { createHttpServer, getDeviceCredentialRecord, readRequestBody, start };

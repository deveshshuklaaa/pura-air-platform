'use strict';

const { initFirebase } = require('./firebase');
const { calculateAqi, isValidNumber } = require('./aqi');
const { saveHistoryRecord, getRecentHistory } = require('./firestore');
const { buildForecast } = require('./forecast');

const deviceListeners = new Map();
const deviceQueues = new Map();
const lastRawSignatures = new Map();
const latestControls = new Map();

function toNumberOrNull(value) {
  const parsed = Number(value);
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
    timestamp: toNumberOrNull(payload.timestamp),
  };

  if (!isValidNumber(normalized.pm25) || !isValidNumber(normalized.pm10)) {
    return null;
  }

  normalized.timestamp = isValidNumber(normalized.timestamp) ? normalized.timestamp : Date.now();

  return normalized;
}

function buildRawSignature(raw) {
  return [
    raw.pm1,
    raw.pm25,
    raw.pm10,
    raw.temperature,
    raw.humidity,
    raw.co2,
    raw.timestamp,
  ].join('|');
}

function enqueueDeviceWork(deviceId, task) {
  const previous = deviceQueues.get(deviceId) || Promise.resolve();
  const next = previous
    .then(task)
    .catch((error) => {
      console.error(`[${new Date().toISOString()}] device=${deviceId} processing error:`, error);
    })
    .finally(() => {
      if (deviceQueues.get(deviceId) === next) {
        deviceQueues.delete(deviceId);
      }
    });

  deviceQueues.set(deviceId, next);
}

function normalizeControlsPayload(payload) {
  if (!payload || typeof payload !== 'object') {
    return null;
  }

  const mode = typeof payload.mode === 'string' ? payload.mode.toUpperCase() : null;
  const fanLevel = toNumberOrNull(payload.fan_level);
  const mist = typeof payload.mist === 'boolean' ? payload.mist : null;

  const normalized = {
    mode: mode === 'MANUAL' ? 'MANUAL' : 'AUTO',
    fan_level: Number.isFinite(fanLevel) ? Math.max(1, Math.min(5, Math.round(fanLevel))) : 1,
    mist: mist ?? false,
    updated_at: Date.now(),
  };

  return normalized;
}

async function processRawReading({ rtdb, firestore }, deviceId, payload) {
  const raw = normalizeRawPayload(payload);
  if (!raw) {
    console.warn(`[${new Date().toISOString()}] device=${deviceId} invalid raw payload; skipped.`);
    return;
  }

  const signature = buildRawSignature(raw);
  if (lastRawSignatures.get(deviceId) === signature) {
    return;
  }
  lastRawSignatures.set(deviceId, signature);

  const aqiResult = calculateAqi({ pm25: raw.pm25, pm10: raw.pm10 });
  if (!aqiResult) {
    console.warn(`[${new Date().toISOString()}] device=${deviceId} AQI could not be calculated; skipped.`);
    return;
  }

  const historyRecord = {
    pm1: raw.pm1,
    pm25: raw.pm25,
    pm10: raw.pm10,
    aqi: aqiResult.aqi,
    dominant_pollutant: aqiResult.dominantPollutant,
    timestamp: raw.timestamp,
  };

  await saveHistoryRecord(firestore, deviceId, historyRecord);

  const history = await getRecentHistory(firestore, deviceId, 30);
  const forecast = buildForecast(history, raw.timestamp);

  const state = {
    aqi: aqiResult.aqi,
    dominant_pollutant: aqiResult.dominantPollutant,
    pm1: raw.pm1,
    pm25: raw.pm25,
    pm10: raw.pm10,
    temperature: raw.temperature,
    humidity: raw.humidity,
    co2: raw.co2,
    last_updated: Date.now(),
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

function attachDeviceRawListener(services, deviceId) {
  if (!deviceId || deviceListeners.has(deviceId)) {
    return;
  }

  const rawRef = services.rtdb.ref(`devices/${deviceId}/raw`);
  const controlsRef = services.rtdb.ref(`devices/${deviceId}/controls`);
  const handler = (snapshot) => {
    const payload = snapshot.val();
    enqueueDeviceWork(deviceId, () => processRawReading(services, deviceId, payload));
  };
  const controlsHandler = (snapshot) => {
    const payload = snapshot.val();
    enqueueDeviceWork(deviceId, () => processControlUpdate(services, deviceId, payload));
  };

  rawRef.on(
    'value',
    handler,
    (error) => {
      console.error(`[${new Date().toISOString()}] device=${deviceId} raw listener error:`, error);
    }
  );
  controlsRef.on(
    'value',
    controlsHandler,
    (error) => {
      console.error(`[${new Date().toISOString()}] device=${deviceId} controls listener error:`, error);
    }
  );

  deviceListeners.set(deviceId, { rawRef, handler, controlsRef, controlsHandler });
  console.log(`[${new Date().toISOString()}] attached raw and controls listeners for device=${deviceId}`);
}

function detachDeviceRawListener(deviceId) {
  const listener = deviceListeners.get(deviceId);
  if (!listener) {
    return;
  }

  listener.rawRef.off('value', listener.handler);
  listener.controlsRef.off('value', listener.controlsHandler);
  deviceListeners.delete(deviceId);
  deviceQueues.delete(deviceId);
  lastRawSignatures.delete(deviceId);
  latestControls.delete(deviceId);
  console.log(`[${new Date().toISOString()}] detached raw listener for device=${deviceId}`);
}

function startDeviceDiscovery(services) {
  const devicesRef = services.rtdb.ref('devices');

  devicesRef.on('child_added', (snapshot) => {
    attachDeviceRawListener(services, snapshot.key);
  });

  devicesRef.on('child_removed', (snapshot) => {
    detachDeviceRawListener(snapshot.key);
  });

  console.log(`[${new Date().toISOString()}] device discovery listener started`);
}

async function start() {
  const services = initFirebase();

  process.on('uncaughtException', (error) => {
    console.error(`[${new Date().toISOString()}] uncaughtException:`, error);
  });

  process.on('unhandledRejection', (error) => {
    console.error(`[${new Date().toISOString()}] unhandledRejection:`, error);
  });

  startDeviceDiscovery(services);
  console.log(`[${new Date().toISOString()}] PURA AIR backend is running`);
}

start().catch((error) => {
  console.error(`[${new Date().toISOString()}] startup failure:`, error);
  process.exitCode = 1;
});

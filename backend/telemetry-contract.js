'use strict';
const crypto = require('node:crypto');
const { ApiError, identifier } = require('./device-security');
const RANGES = { pm1: [0, 5000], pm25: [0, 5000], pm10: [0, 5000], temperature: [-40, 85],
  humidity: [0, 100], co2: [0, 50000], gas_index: [0, 1000], voc_index: [0, 500], mq135_raw: [0, 4095] };
function validateEvent(body, deviceId) {
  identifier(deviceId);
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new ApiError(400, 'invalid_event');
  const allowed = ['device_id', 'event_id', 'sequence', 'timestamp', 'source', ...Object.keys(RANGES)];
  if (Object.keys(body).some((k) => !allowed.includes(k))) throw new ApiError(400, 'unsupported_field');
  if (body.device_id !== deviceId) throw new ApiError(400, 'device_id_mismatch');
  if (typeof body.event_id !== 'string' || !/^[A-Za-z0-9_-]{1,96}$/.test(body.event_id)) throw new ApiError(400, 'invalid_event_id');
  if (!Number.isSafeInteger(body.timestamp) || body.timestamp <= 0) throw new ApiError(400, 'invalid_timestamp');
  if (body.sequence !== undefined && (!Number.isSafeInteger(body.sequence) || body.sequence < 0)) throw new ApiError(400, 'invalid_sequence');
  if (body.source !== undefined && !['hardware', 'simulator'].includes(body.source)) throw new ApiError(400, 'invalid_source');
  const event = { device_id: deviceId, event_id: body.event_id, timestamp: body.timestamp, source: body.source || 'hardware' };
  if (body.sequence !== undefined) event.sequence = body.sequence;
  for (const [key, [min, max]] of Object.entries(RANGES)) {
    const value = body[key];
    if (value === undefined && !['pm25', 'pm10'].includes(key)) continue;
    if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max
        || (key === 'mq135_raw' && !Number.isInteger(value))) throw new ApiError(400, `invalid_${key}`);
    event[key] = value;
  }
  return event;
}
function validateTime(event, now) {
  if (event.timestamp < now - 30 * 86400000 || event.timestamp > now + 300000) throw new ApiError(400, 'timestamp_out_of_window');
}
const digest = (s) => crypto.createHash('sha256').update(s).digest('hex');
const identity = (deviceId, eventId) => digest(`${deviceId}:${eventId}`);
const fingerprint = (event) => digest(JSON.stringify(Object.fromEntries(Object.entries(event).sort(([a], [b]) => a.localeCompare(b)))));
module.exports = { validateEvent, validateTime, identity, fingerprint, RANGES };

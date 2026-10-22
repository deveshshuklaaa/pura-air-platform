'use strict';
const { setTimeout: delay } = require('node:timers/promises');
const { validateEvent } = require('../telemetry-contract');

function generateEvents({ deviceId = 'PA-SIM', count = 3, start = Date.now() - 2000, interval = 1000, seed = 1, runId = 'fixture' } = {}) {
  if (!Number.isInteger(count) || count < 1 || count > 10000 || !Number.isInteger(interval) || interval < 0) throw Error('invalid_simulator_options');
  return Array.from({ length: count }, (_, i) => {
    const sequence = i + 1, variation = (seed - 1) % 10;
    return validateEvent({ device_id: deviceId, event_id: `${runId}-${String(sequence).padStart(6, '0')}`, sequence,
      timestamp: start + i * interval, source: 'simulator', pm1: 5 + sequence * 2,
      pm25: Number((12.1 + sequence * 2.5 + variation).toFixed(2)), pm10: 30 + sequence * 5,
      temperature: Number((23 + sequence * 0.2).toFixed(2)), humidity: 45 + sequence,
      co2: 400 + sequence * 20, gas_index: Number((1 + sequence * 0.1).toFixed(2)), voc_index: 90 + sequence * 5,
      mq135_raw: 600 + sequence }, deviceId);
  });
}
function destination(url, allowNonlocal = false) {
  const target = new URL(url);
  const local = ['127.0.0.1', 'localhost', '[::1]'].includes(target.hostname);
  if ((!local && !allowNonlocal) || !['http:', 'https:'].includes(target.protocol) || target.username || target.password) throw Error('nonlocal_destination_refused');
  return target;
}
async function sendEvent(url, key, event, options = {}) {
  const target = destination(url, options.allowNonlocal);
  if (!key) throw Error('SIMULATOR_DEVICE_KEY_required');
  const transport = options.fetch || fetch;
  for (let attempt = 0; attempt < (options.attempts || 5); attempt++) {
    try {
      const response = await transport(new URL(`/ingest/${event.device_id}`, target), {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Device-Key': key },
        body: JSON.stringify(event), redirect: 'error', signal: AbortSignal.timeout(10000) });
      if (response.status === 202) return await response.json();
      if (response.status < 500 && response.status !== 429) throw Object.assign(Error('event_rejected'), { terminal: true, status: response.status });
    } catch (e) { if (e.terminal) throw e; }
    if (attempt + 1 < (options.attempts || 5)) await (options.delay || delay)(Math.min(10000, 250 * 2 ** attempt));
  }
  throw Error('simulator_retry_exhausted');
}
async function main(args = process.argv.slice(2)) {
  const flags = new Set(['--dry-run', '--allow-nonlocal']); const values = {};
  for (let i = 0; i < args.length; i++) {
    if (flags.has(args[i])) values[args[i]] = true;
    else {
      if (!['--url', '--device', '--count', '--interval', '--seed', '--start', '--run-id', '--repeat-every', '--disconnect-every', '--disconnect-ms'].includes(args[i]) || args[i + 1] === undefined) throw Error('invalid_argument');
      values[args[i]] = args[++i];
    }
  }
  const interval = Number(values['--interval'] ?? 1000);
  const events = generateEvents({ deviceId: values['--device'] || 'PA-SIM', count: Number(values['--count'] ?? 3),
    start: Number(values['--start'] ?? Date.now()), interval, seed: Number(values['--seed'] ?? 1), runId: values['--run-id'] || 'simulator' });
  if (!values['--dry-run'] && !values['--url']) throw Error('explicit_url_required');
  for (const [i, event] of events.entries()) {
    if (values['--dry-run']) { console.log(JSON.stringify({ label: 'SIMULATED TEST TELEMETRY', event })); continue; }
    if (i && Number(values['--disconnect-every']) && i % Number(values['--disconnect-every']) === 0) await delay(Number(values['--disconnect-ms'] ?? 3000));
    const receipt = await sendEvent(values['--url'], process.env.SIMULATOR_DEVICE_KEY, event, { allowNonlocal: values['--allow-nonlocal'] });
    console.log(JSON.stringify({ label: 'SIMULATED TEST TELEMETRY', event_id: event.event_id, status: receipt.status, duplicate: receipt.duplicate }));
    if (Number(values['--repeat-every']) && (i + 1) % Number(values['--repeat-every']) === 0) await sendEvent(values['--url'], process.env.SIMULATOR_DEVICE_KEY, event, { allowNonlocal: values['--allow-nonlocal'] });
    if (i + 1 < events.length) await delay(interval);
  }
}
if (require.main === module) main().catch((e) => { console.error(e.message); process.exitCode = 1; });
module.exports = { generateEvents, sendEvent, destination, main };

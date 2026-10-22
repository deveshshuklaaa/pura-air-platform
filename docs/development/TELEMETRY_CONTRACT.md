# Telemetry v2 contract — Phase 1B

Decision recorded 21 October 2026, before ingestion changes. This is a local, additive software contract; no production schema/rule deployment, migration or deletion is authorized. Phase 1A ownership and private device credentials remain mandatory. Legacy payloads without stable producer identity must upgrade rather than receive an unsafe synthetic identity.

## Event

`POST /ingest/{device_id}`, JSON object, maximum 16 KiB, `X-Device-Key` from the server-only credential collection. Required: `device_id` (same as URL, 1–128 ASCII letters/digits/underscore/hyphen, excluding prototype-property names), `event_id` (1–96 of the same alphabet), `timestamp` (integer Unix milliseconds), `pm25`, `pm10`. Optional: integer `sequence` in 0..2^53-1 and the measurements below. `source` is optional `hardware` (default) or `simulator`. Simulator data remains visibly labelled test data in storage/UI. No other properties are accepted.

| Field | Unit | Accepted numeric range |
| --- | --- | --- |
| pm1, pm25, pm10 | micrograms/cubic metre | 0..5000 |
| temperature | degrees Celsius | -40..85 |
| humidity | percent relative humidity | 0..100 |
| co2 | ppm, sensor reading (not CPCB CO) | 0..50000 |
| gas_index | producer-defined dimensionless prototype index | 0..1000 |
| voc_index | producer-defined dimensionless prototype index | 0..500 |
| mq135_raw | ESP32 raw ADC counts | integer 0..4095 |

Values must be finite JSON numbers, never strings, Booleans or null. Missing optional fields stay absent in persistence and display “Unavailable”; they never become zero. Numeric zero is valid only when explicitly supplied and within the contract. Ranges are protocol validation limits, not calibration/accuracy claims. New-event timestamps must be within 30 days before to 5 minutes after receipt. Retries of an already accepted identical event remain valid even after that window. The producer keeps the **same payload, event_id, sequence and timestamp** on every retry. A changed payload with the same device/event identity is 409 `event_conflict`.

## Durable acceptance and recovery

Firestore transactionally creates a stable identity record (`telemetry_identities/{sha256(device_id,event_id)}`), a durable receipt (`telemetry_events/{zero-padded-order}`), and advances `telemetry_queue/runtime`. Only then can HTTP 202 be returned. The receipt contains the validated raw event, original server receipt time, status, attempts, next retry time and safe failure code. Client rules default-deny these internal collections. Duplicate requests return the same receipt, without another queue slot/history record. `GET /ingest/{id}/events/{event_id}` requires the same device authentication and returns receipt status/attempts/times, never keys or another device's payload.

202 means **durably accepted**, not persisted to both databases, healthy hardware or actuator execution. The response reports the actual receipt `status` (`accepted`, `processing`, `retry`, `completed`, `failed`) and `duplicate`. 400 invalid schema, 401 bad/missing device key, 409 conflicting identity, 413 oversized body, 503 acceptance unavailable/full/shutting down. Producers retry 503/network uncertainty with bounded exponential backoff and the unchanged event; inspect status on terminal `failed`.

A single versioned, expiring Firestore worker lease serializes the durable FIFO globally (therefore per device). This intentionally favors correctness over throughput; it is not a new external broker. Receipts recover after process restart/expired lease, including processing interrupted by shutdown. Defaults: capacity 5000 outstanding events, lease 60 seconds, five processing attempts, exponential retry starting at 1 second capped at 60 seconds. Head-of-line retries preserve acceptance order; after five failures the receipt becomes terminal `failed`, frees capacity, and the FIFO advances. No raw event is erased. Manual replay is an explicit trusted operator action through `replayFailed(deviceId, eventId)` in the service module, deliberately absent from HTTP routes. After inspecting and repairing the persistence cause, a trusted operator can invoke it against the deliberately selected environment. It requires terminal `failed`, appends a new receipt, points the stable identity to that receipt, retains the original failed receipt, event, server time and acceptance order, and resets only the new receipt retry budget. Resubmitting a terminal event through HTTP never silently resets attempts. Replay must not be automated against production as part of this milestone.

History is idempotent by the identity hash. History may succeed before RTDB or receipt completion; retry writes the same history document, rebuilds the forecast from unique persisted records, and retries the projection. There is no cross-database transaction and **no exactly-once claim**. RTDB compares measurement timestamps and acceptance order before replacing state/forecast atomically; older measurements remain in history but do not roll live state backwards. Lease fencing protects receipt completion; timestamp/order fencing protects RTDB from delayed workers. Shutdown refuses new acceptance, stops polling and waits a bounded interval for active work; any interrupted receipt remains durable and lease-recoverable.

Existing `devices/{id}/history`, RTDB `devices/{id}/state` and `forecast` paths are retained. v2 records add `schema_version`, `event_id`, `accepted_order`, `indicator_version`, `particulate_indicator`, `source`, original `timestamp`, original `server_received_at` and optional raw measurements. `aqi` is a deprecated compatibility alias for the prototype indicator, never an official AQI claim. No old records are rewritten. Automated retention/deletion is not enabled in the new pipeline. History sorts by measurement timestamp (then accepted order), not chart sample index. Live freshness is based on both measurement time and server receipt time; data older than two minutes is stale/offline, recomputed in Flutter even if streams are silent.

Health/metrics expose queue counts, worker status and safe error counters, without raw readings, event payloads or credentials. A Firestore outage makes readiness unavailable. Retry state is durable; in-memory metrics are observational only. Full or unavailable acceptance returns 503 without falsely acknowledging an event.

## Isolated simulator and verification

`backend/scripts/simulator.js` defaults to loopback only, requires an explicit URL and a key from `SIMULATOR_DEVICE_KEY` (never prints it), and supports deterministic seed/start time/count/interval/device, dry-run, duplicate submissions, disconnect pauses and retries. Nonlocal URLs require `--allow-nonlocal`; automated integration refuses them regardless. No production destination is guessed. Dry-run prints only labelled synthetic sensor payloads.

The Firebase suites use only `demo-pura-security` and explicit loopback hosts. Physical-phone checks use USB reverse forwarding to those same local services, an emulator-only native Firebase configuration, and a test entry point that refuses production projects. A phone test does not connect fixtures to the deployed Firebase project. Forecasts are prototype regression estimates with explicit 10/30-minute horizons, not measured prediction-quality claims.

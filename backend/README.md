# PURA AIR Backend

## Phase 1A security update

Read [the authorization/API/migration contract](../docs/development/AUTHORIZATION_SECURITY.md) before using this revision. Privileged mobile operations now require verified registered-account ID tokens and the `/api/` endpoints. Credentials live only in `device_credentials/{id}`; client registry/membership/pairing writes and legacy Boolean ACL grants are denied. Existing credentials/memberships need a reviewed **manual** migration; nothing is migrated or deployed automatically.

The access refresh default is now 30 seconds with a 90-second ACL lease. Use `ACCESS_SYNC_INTERVAL_MS=30000`; the old 300000 example is incompatible with continuous access. Flutter requires `--dart-define=PURA_API_BASE_URL=https://your-reviewed-backend.example`.

Validation from `backend/`: `npm ci`, `npm run check`, `npm test`, `npm run test:emulators`. Emulator tests require Node >=24.12, Firebase CLI 15.6.0 and Java 21+, and are locked to `demo-pura-security`. See the contract for loopback ports and Windows Java troubleshooting. `ALLOW_UNAUTH_INGEST=true` and `ENABLE_RTDB_RAW_LISTENER=true` now refuse startup; all telemetry uses authenticated HTTP.

## Phase 1B telemetry

Read [telemetry v2](../docs/development/TELEMETRY_CONTRACT.md), [prototype indicator semantics](../docs/development/AQI_SEMANTICS.md), and [actual validation results](../docs/development/PHASE_1B_RESULTS.md). HTTP 202 requires a durable Firestore receipt. Stable producer event IDs make retries idempotent across restart and partial database failure. This is durable acceptance with retryable processing, with no exactly-once or physical execution claim.

## 1) Install dependencies

```powershell
cd backend
npm install
```

## 2) Add Firebase service account

1. Open Firebase Console -> Project Settings -> Service Accounts.
2. Generate a new private key and download the JSON file.
3. Save it as `backend/serviceAccountKey.json`.

Set environment variables (PowerShell):

```powershell
$env:FIREBASE_SERVICE_ACCOUNT_PATH = "C:\dev\PuraAir\backend\serviceAccountKey.json"
$env:FIREBASE_DATABASE_URL = "https://pura-air-default-rtdb.firebaseio.com"
$env:INGEST_API_KEY = "replace-with-strong-ingest-key"
```

Alternative: If running on Google Cloud with Workload Identity / ADC, skip `FIREBASE_SERVICE_ACCOUNT_PATH` and use default credentials.

## 3) Run locally

```powershell
cd backend
node server.js
```

## 4) HTTP ingestion API

The backend now accepts device telemetry through HTTP:

```http
POST /ingest/{deviceId}
Headers:
  Content-Type: application/json
  X-Device-Key: <INGEST_API_KEY or per-device ingest_key>
Body:
{
  "device_id": "PA-SIM",
  "event_id": "boot-unique-000947",
  "pm1": 8.1,
  "pm25": 16.5,
  "pm10": 31.2,
  "temperature": 27.1,
  "humidity": 52.0,
  "co2": 520,
  "timestamp": 1792585800000,
  "sequence": 947
}
```

Notes:
- `pm25` and `pm10` are required.
- `device_id`, stable producer `event_id`, and integer Unix-millisecond `timestamp` are required; replace the sample timestamp with the measurement time (within the documented acceptance window).
- Keep the entire payload unchanged on retry. `sequence` is optional; identity is `(device_id, event_id)`.
- Missing optional measurements stay absent, never zero. Unknown fields, wrong types, invalid ranges and oversized requests are rejected before acceptance.
- `GET /ingest/{deviceId}/events/{eventId}` uses device authentication and reports receipt status. Identical duplicates share the receipt; changed payloads with the same identity return 409.
- Use `GET /health` for readiness and `GET /metrics` for queue/error metrics.

## 5) Runtime behavior

- **Latest state**: written to RTDB `devices/{id}/state` and `devices/{id}/forecast`.
- **Historical data**: written once per stable identity to Firestore `devices/{id}/history/*`; raw measurements and both device/receipt times are retained.
- **Idempotency**: durable `telemetry_identities` records, with no time-based dedupe expiry.
- **Worker queue**: Firestore receipts and one fenced global FIFO lease; defaults are 5000 pending events, five attempts, exponential backoff, and a 60-second lease. Terminal failures remain inspectable and support trusted manual replay. Legacy `EVENT_KEY_TTL_MS`, `WORKER_CONCURRENCY` and `MAX_QUEUE_SIZE` do not configure this pipeline.
- **Access sync**: Firestore ownership to RTDB `device_access` sync, interval via `ACCESS_SYNC_INTERVAL_MS`.
- **Retention**: no automatic history/receipt deletion is enabled. Plan retention and capacity before production operation; old retention environment flags are inactive.

## 6) Optional environment flags

```powershell
$env:ENABLE_RTDB_RAW_LISTENER = "false"      # default false
$env:ENABLE_RTDB_CONTROLS_LISTENER = "true"  # default true
$env:ACCESS_SYNC_INTERVAL_MS = "30000"
```

## Isolated simulator and physical-phone check

Dry-run from `backend/` (prints synthetic payloads, performs no network request):

```powershell
node scripts/simulator.js --url http://127.0.0.1:18088 --device PA-SIM --count 3 --seed 1 --run-id local-demo --dry-run
```

Sending requires `SIMULATOR_DEVICE_KEY` and an explicitly provisioned isolated API. See `backend/scripts/simulator.js` for interval, start, duplicate, disconnect and retry options. Loopback is required unless `--allow-nonlocal` is explicitly supplied; production use is outside this milestone.

`npm run test:emulators` exercises real local Firebase persistence and security. For the physical phone, set `PURA_PHYSICAL_DEVICE` to the explicit connected device ID and run `npm run test:physical`. The wrapper starts only project `demo-pura-security`, runs all backend integration cases, then builds/installs the isolated debug test app on that phone. It requires Android tools, Flutter and USB debugging. It uses Auth 19099, Firestore 18080, RTDB 19000 and fixture API 18088 on loopback, temporary USB reverse forwards, a demo-only native Firebase configuration and a runtime project guard. Only this isolated test build uses system fonts to avoid font downloads. It never starts an Android emulator. Do not run `node server.js` to execute this fixture: normal startup loads your configured Firebase credentials.

## 7) Run continuously with PM2

Install PM2 globally:

```powershell
npm install -g pm2
```

Start service:

```powershell
cd C:\dev\PuraAir\backend
pm2 start server.js --name pura-air-backend
```

Set required env vars in PM2 before start (Windows PowerShell):

```powershell
$env:FIREBASE_SERVICE_ACCOUNT_PATH = "C:\dev\PuraAir\backend\serviceAccountKey.json"
$env:FIREBASE_DATABASE_URL = "https://pura-air-default-rtdb.firebaseio.com"
$env:INGEST_API_KEY = "replace-with-strong-ingest-key"
pm2 start server.js --name pura-air-backend
```

Useful PM2 commands:

```powershell
pm2 status
pm2 logs pura-air-backend
pm2 restart pura-air-backend
pm2 stop pura-air-backend
pm2 delete pura-air-backend
```

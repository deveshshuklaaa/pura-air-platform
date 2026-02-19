# PURA AIR Backend

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
  "pm1": 8.1,
  "pm25": 16.5,
  "pm10": 31.2,
  "temperature": 27.1,
  "humidity": 52.0,
  "co2": 520,
  "timestamp": 1739855092000,
  "sequence": 947
}
```

Notes:
- `pm25` and `pm10` are required.
- `timestamp` defaults to server time if missing.
- `sequence` enables deterministic idempotency per device.
- Use `GET /health` for readiness and `GET /metrics` for queue/error metrics.

## 5) Runtime behavior

- **Latest state**: written to RTDB `devices/{id}/state` and `devices/{id}/forecast`.
- **Historical data**: written to Firestore `devices/{id}/history/*`.
- **Idempotency**: event-key dedupe window controlled by `EVENT_KEY_TTL_MS`.
- **Worker queue**: concurrency controlled by `WORKER_CONCURRENCY`.
- **Access sync**: Firestore ownership to RTDB `device_access` sync, interval via `ACCESS_SYNC_INTERVAL_MS`.
- **Retention**: old history cleanup via `HISTORY_RETENTION_DAYS` and `HISTORY_RETENTION_INTERVAL_MS`.

## 6) Optional environment flags

```powershell
$env:ENABLE_RTDB_RAW_LISTENER = "false"      # default false
$env:ENABLE_RTDB_CONTROLS_LISTENER = "true"  # default true
$env:WORKER_CONCURRENCY = "4"
$env:MAX_QUEUE_SIZE = "5000"
$env:HISTORY_RETENTION_DAYS = "30"
$env:ACCESS_SYNC_INTERVAL_MS = "300000"
```

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

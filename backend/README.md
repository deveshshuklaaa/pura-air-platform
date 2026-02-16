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
```

Alternative: If running on Google Cloud with Workload Identity / ADC, skip `FIREBASE_SERVICE_ACCOUNT_PATH` and use default credentials.

## 3) Run locally

```powershell
cd backend
node server.js
```

## 4) Run continuously with PM2

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

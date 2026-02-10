# PuraAir

Flutter app for the PURA AIR IoT dashboard (dark futuristic UI).

## Setup

1. Install Flutter SDK and Android Studio.
2. Place `google-services.json` at `android/app/google-services.json`.
3. Run:

```bash
flutter pub get
flutter run
```

## Firebase data model (recommended)

```
/users/{uid}/devices/{device_id}
  name: "Living Room"
  online: true
  last_seen: <Timestamp or epoch>
  state:
    aqi: 68
    aqi_category: "Moderate"
    aqi_trend: 12
    co2: 980
    pm25_avg: 42
    gas_index: 1.3
    fan_level: 2
    mist: false
    mode: "AUTO"
    humidity: 44.5
    temperature: 23.4
```

## Notes

- The app signs in anonymously by default when Firebase is available.
- If Firebase is not configured, it falls back to mock data.

## Authentication

Supported:
- Email/password
- Google Sign-In
- Anonymous guest

For Google Sign-In on Android:
1. Add your SHA-1 to Firebase (Project settings > Your apps).
2. Download and replace `android/app/google-services.json`.

## Notifications

- Uses FCM + local notifications for foreground alerts.
- Android channel: `alerts` (Device Alerts).

## Notes for iOS

If you later add iOS, place `GoogleService-Info.plist` in `ios/Runner/` and run `pod install`.


## Database

This app uses **Cloud Firestore**.

## Device Registry (validation)

The app validates device IDs against a backend registry:

```
/devices/{device_id}
  active: true
  model: "PURA AIR"
```

If the device ID is not present, the app will refuse to add it.

## Pairing Codes

Pairing codes are read from:

```
/pairing_codes/{code}
  device_id: "PA-012"
```

When a pairing code is used, it is deleted after pairing.

## Add Device Flows

- Manual device ID + name
- QR scan (camera)
- Pairing code + name

## Theme

- Light and dark modes available
- Toggle via the sun/moon button in the app bar or on the auth screen

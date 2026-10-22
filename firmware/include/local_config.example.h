#pragma once
// REPORTED MAP ONLY, not measured/approved wiring. Actual local_config.h is ignored.
// WROOM-DA reserves GPIO25 internally: enabling this reported combination must fail.
#define PURA_SENSOR_IO_ENABLED false
#define PURA_REPORTED_WROOM_DA true
#define PURA_PMS_RX 25  // PMS7003 TX -> ESP1 RX; conflicts with reported DA module.
#define PURA_PMS_TX 26  // ESP1 TX -> PMS7003 RX; no sensor commands are implemented.
#define PURA_I2C_SDA 21
#define PURA_I2C_SCL 22
#define PURA_MQ135_ENABLED false
#define PURA_MQ135_ADC 34
// Reserved wiring only: no ESP2 driver, initialization or messages exist.
#define PURA_ESP2_RX 16 // <- ESP2 TX17, common GND, reported 115200 baud.
#define PURA_ESP2_TX 17 // -> ESP2 RX16. UART1 reservation, not native-pin ownership.
#define PURA_WIFI_SSID ""
#define PURA_WIFI_PASSWORD ""
#define PURA_DEVICE_ID "" // Must match trusted backend provisioning.
#define PURA_INGEST_KEY "" // Per-device private ingest key, never a mobile ID token.
#define PURA_API_HOST "" // Host only, no URL/path; never guessed.
#define PURA_API_PORT 443
#define PURA_API_TLS true
// PEM root CA for the deliberately selected HTTPS endpoint (hostname verified).
#define PURA_TLS_ROOT_CA ""
#define PURA_ALLOW_PRIVATE_HTTP false
#define PURA_NTP_SERVER "pool.ntp.org"

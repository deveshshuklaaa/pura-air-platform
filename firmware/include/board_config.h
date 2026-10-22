#pragma once
#if __has_include("local_config.h")
#include "local_config.h"
#endif

// No inferred wiring. Copy local_config.example.h only after board/electrical review.
#ifndef PURA_SENSOR_IO_ENABLED
#define PURA_SENSOR_IO_ENABLED false
#endif
#ifndef PURA_PMS_RX
#define PURA_PMS_RX -1
#endif
#ifndef PURA_PMS_TX
#define PURA_PMS_TX -1
#endif
#ifndef PURA_ESP2_RX
#define PURA_ESP2_RX -1
#endif
#ifndef PURA_ESP2_TX
#define PURA_ESP2_TX -1
#endif
#ifndef PURA_REPORTED_WROOM_DA
// Conservative restriction for the reported module; not hardware identification.
#define PURA_REPORTED_WROOM_DA true
#endif
#ifndef PURA_I2C_SDA
#define PURA_I2C_SDA -1
#endif
#ifndef PURA_I2C_SCL
#define PURA_I2C_SCL -1
#endif
#ifndef PURA_MQ135_ENABLED
#define PURA_MQ135_ENABLED false
#endif
#ifndef PURA_MQ135_ADC
#define PURA_MQ135_ADC -1
#endif
#ifndef PURA_WIFI_SSID
#define PURA_WIFI_SSID ""
#endif
#ifndef PURA_WIFI_PASSWORD
#define PURA_WIFI_PASSWORD ""
#endif
#ifndef PURA_DEVICE_ID
#define PURA_DEVICE_ID ""
#endif
#ifndef PURA_INGEST_KEY
#define PURA_INGEST_KEY ""
#endif
#ifndef PURA_API_HOST
#define PURA_API_HOST ""
#endif
#ifndef PURA_API_PORT
#define PURA_API_PORT 443
#endif
#ifndef PURA_API_TLS
#define PURA_API_TLS true
#endif
#ifndef PURA_TLS_ROOT_CA
#define PURA_TLS_ROOT_CA ""
#endif
#ifndef PURA_ALLOW_PRIVATE_HTTP
#define PURA_ALLOW_PRIVATE_HTTP false
#endif
#ifndef PURA_NTP_SERVER
#define PURA_NTP_SERVER "pool.ntp.org"
#endif

namespace board {
constexpr bool sensorIo = PURA_SENSOR_IO_ENABLED;
constexpr int pmsRx = PURA_PMS_RX, sda = PURA_I2C_SDA, scl = PURA_I2C_SCL;
constexpr int pmsTx = PURA_PMS_TX, esp2Rx = PURA_ESP2_RX, esp2Tx = PURA_ESP2_TX;
constexpr bool reportedWroomDa = PURA_REPORTED_WROOM_DA;
// Keep the existing PMS UART2 owner. UART1 is reserved, NOT initialized or implemented.
constexpr int pmsUart = 2, esp2ReservedUart = 1, consoleUart = 0;
constexpr int pmsBaud = 9600, esp2ReservedBaud = 115200;
constexpr bool esp2Implemented = false;
static_assert(pmsUart != esp2ReservedUart && pmsUart != consoleUart && esp2ReservedUart != consoleUart, "UART owners must differ");
constexpr bool mqEnabled = PURA_MQ135_ENABLED;
constexpr int mqAdc = PURA_MQ135_ADC;
// Conservative post-power warm-up gates, not calibration guarantees.
constexpr unsigned long pmsWarmupMs = 30000;
constexpr unsigned long mqWarmupMs = 48UL * 60 * 60 * 1000;
constexpr unsigned long eventIntervalMs = 10000;
static_assert(!sensorIo || (pmsRx >= 0 && sda >= 0 && scl >= 0), "Review/configure sensor pins first");
static_assert(!sensorIo || (pmsRx != sda && pmsRx != scl && sda != scl), "Sensor pins must differ");
// Restrict this provisional classic ESP32 build to ADC1 inputs; ADC2 conflicts with Wi-Fi.
static_assert(!mqEnabled || (sensorIo && mqAdc >= 32 && mqAdc <= 39 && mqAdc != pmsRx && mqAdc != sda && mqAdc != scl), "MQ requires reviewed ADC1 pin and sensor I/O");
constexpr bool pinsDistinct() {
  const int pins[] = {pmsRx, pmsTx, sda, scl, mqEnabled ? mqAdc : -1, esp2Rx, esp2Tx};
  for (unsigned i = 0; i < 7; ++i)
    for (unsigned j = i + 1; j < 7; ++j)
      if (pins[i] >= 0 && pins[i] == pins[j]) return false;
  return true;
}
constexpr bool usesDaRfPins() {
  const int pins[] = {pmsRx, pmsTx, sda, scl, mqEnabled ? mqAdc : -1, esp2Rx, esp2Tx};
  for (int pin : pins) if (pin == 2 || pin == 25) return true;
  return false;
}
static_assert(!sensorIo || pinsDistinct(), "Sensor and reserved ESP2 pins must not overlap");
static_assert(!sensorIo || !reportedWroomDa || !usesDaRfPins(), "WROOM-DA GPIO2/25 are RF-switch pins: resolve reported board/wiring before enabling");
}

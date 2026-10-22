#include <Arduino.h>
#include <esp_system.h>
#include <cstdio>
#include "board_config.h"
#include "sensor_acquisition.h"
#include "connectivity.h"
#include "http_transport.h"

namespace {
SensorAcquisition sensors;
EspWifi wifi;
pura::WifiRecovery wifiRecovery;
TimeSync timeSync;
EspHttpTransport http;
pura::Outbox outbox;
std::string bootId;
uint64_t sequence = 0, nextEvent = 0, nextDiagnostics = 0, lastLoop = 0;
bool configured = false;
}
void setup() {
  Serial.begin(115200);
  configured = runtimeConfigured();
  if (!configured) { Serial.println("PURA telemetry disabled: review board pins/network/private configuration"); return; }
  wifi.begin();
  // Wi-Fi radio is initialized before obtaining the 128-bit per-boot entropy.
  uint8_t random[16]; esp_fill_random(random, sizeof(random)); char hex[33];
  for (unsigned i = 0; i < sizeof(random); ++i) std::snprintf(hex + 2 * i, 3, "%02x", random[i]);
  bootId = hex; timeSync.begin(); sensors.begin();
  Serial.println("PURA sensor-only provisional firmware; RAM outbox; no physical validation");
}
void loop() {
  if (!configured) { delay(100); return; }
  const uint64_t now = uptimeMs();
  // Network calls are bounded but synchronous. Discard pre-call UART bytes so an
  // old queued frame cannot appear newly sampled after a slow HTTP/TLS request.
  if (lastLoop && now - lastLoop > 500) uart_flush_input(pmsUartPort);
  lastLoop = now;
  wifiRecovery.tick(wifi, now); timeSync.tick(now); sensors.tick(now);
  if (now >= nextEvent) {
    nextEvent = now + board::eventIntervalMs;
    pura::Event event;
    if (now >= board::pmsWarmupMs && sequence < pura::kMaxSafeInteger &&
        pura::assemble(PURA_DEVICE_ID, bootId, sequence + 1, sensors.pm(), sensors.scd(), sensors.mqRaw(), sensors.mqReady(now), timeSync.clock(), now, event)) {
      if (outbox.enqueue(event)) ++sequence;
    }
  }
  outbox.tick(http, wifi.connected(), timeSync.valid(now), now);
  if (now >= nextDiagnostics) {
    nextDiagnostics = now + 30000;
    Serial.printf("telemetry wifi=%u time=%u pm_fresh=%u scd_fresh=%u queued=%u accepted=%lu dropped=%lu exhausted=%lu rejected=%lu auth_blocked=%u pms_errors=%lu scd_errors=%lu\n",
      wifi.connected(), timeSync.valid(now), sensors.pm().valid && pura::fresh(sensors.pm().sampled, now, 10000),
      sensors.scd().valid && pura::fresh(sensors.scd().sampled, now, 15000), static_cast<unsigned>(outbox.size()),
      static_cast<unsigned long>(outbox.accepted), static_cast<unsigned long>(outbox.dropped), static_cast<unsigned long>(outbox.exhausted),
      static_cast<unsigned long>(outbox.rejected), outbox.unauthorized(), static_cast<unsigned long>(sensors.pmsErrors()), static_cast<unsigned long>(sensors.scdErrors()));
  }
  delay(5);
}

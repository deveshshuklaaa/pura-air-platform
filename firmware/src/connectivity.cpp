#include "connectivity.h"
#include "board_config.h"
#include <WiFi.h>
#include <esp_timer.h>
#include <esp_sntp.h>
#include <sys/time.h>
#include <atomic>

namespace { std::atomic<bool> synchronized{false}; }
uint64_t uptimeMs() { return esp_timer_get_time() / 1000; }
bool runtimeConfigured() {
  const bool tls = PURA_API_TLS;
  return board::sensorIo && pura::identifier(PURA_DEVICE_ID, 128) &&
    std::string(PURA_WIFI_SSID).size() > 0 && std::string(PURA_INGEST_KEY).size() > 0 &&
    pura::validHost(PURA_API_HOST) && PURA_API_PORT > 0 && PURA_API_PORT <= 65535 &&
    (tls ? std::string(PURA_TLS_ROOT_CA).find("-----BEGIN CERTIFICATE-----") != std::string::npos
         : (PURA_ALLOW_PRIVATE_HTTP && pura::privateIpv4(PURA_API_HOST)));
}
void EspWifi::begin() { WiFi.persistent(false); WiFi.mode(WIFI_STA); WiFi.setAutoReconnect(false); }
bool EspWifi::connected() { return WiFi.status() == WL_CONNECTED; }
void EspWifi::reconnect() { WiFi.disconnect(false, false); WiFi.begin(PURA_WIFI_SSID, PURA_WIFI_PASSWORD); }
void TimeSync::begin() {
  sntp_set_time_sync_notification_cb([](struct timeval*) { synchronized.store(true); });
  configTime(0, 0, PURA_NTP_SERVER);
}
void TimeSync::tick(uint64_t now) {
  if (synchronized.exchange(false)) {
    timeval tv{}; gettimeofday(&tv, nullptr);
    clock_.synchronize(static_cast<uint64_t>(tv.tv_sec) * 1000 + tv.tv_usec / 1000, now);
  }
}
bool TimeSync::valid(uint64_t now) const { uint64_t epoch; return clock_.at(now, now, epoch); }

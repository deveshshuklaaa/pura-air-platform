#include "http_transport.h"
#include "board_config.h"
#include <HTTPClient.h>
#include <WiFiClientSecure.h>

int EspHttpTransport::post(const std::string& id, const std::string& json) {
  WiFiClient plain;
  WiFiClientSecure tls;
  HTTPClient http; // Destroy the HTTP wrapper before its referenced clients.
  if (PURA_API_TLS) { tls.setCACert(PURA_TLS_ROOT_CA); tls.setHandshakeTimeout(5); }
  WiFiClient& client = PURA_API_TLS ? static_cast<WiFiClient&>(tls) : plain;
  const String url = String(PURA_API_TLS ? "https://" : "http://") + PURA_API_HOST + ":" + String(PURA_API_PORT) + "/ingest/" + id.c_str();
  http.setConnectTimeout(5000); http.setTimeout(5000); http.setReuse(false);
  http.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
  if (!http.begin(client, url)) return -1;
  http.addHeader("Content-Type", "application/json"); http.addHeader("X-Device-Key", PURA_INGEST_KEY);
  // Never print key, Wi-Fi password, raw payload or response body.
  const int result = http.POST(String(json.c_str()));
  http.end(); return result;
}

#include "pura_core.h"
#include <algorithm>
#include <cmath>
#include <cstdio>

namespace pura {
bool identifier(const std::string& v, size_t limit) {
  if (v.empty() || v.size() > limit || v == "__proto__" || v == "constructor" || v == "prototype") return false;
  for (char c : v) if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-')) return false;
  return true;
}
bool validHost(const std::string& host) {
  if (host.empty() || host.size() > 253 || host == "localhost" || host == "127.0.0.1") return false;
  for (char c : host) if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '.')) return false;
  return true;
}
bool privateIpv4(const std::string& host) {
  unsigned a, b, c, d; char tail;
  if (std::sscanf(host.c_str(), "%u.%u.%u.%u%c", &a, &b, &c, &d, &tail) != 4 || a > 255 || b > 255 || c > 255 || d > 255) return false;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}
bool fresh(uint64_t sampled, uint64_t now, uint64_t maxAge) { return sampled <= now && now - sampled <= maxAge; }
static uint16_t word(const uint8_t* p) { return static_cast<uint16_t>((p[0] << 8) | p[1]); }
bool PmsDecoder::feed(uint8_t byte, uint64_t now) {
  if (used_ && now - lastByte_ > 500) { used_ = 0; ++errors_; }
  lastByte_ = now;
  if (used_ == 0) { if (byte == 0x42) bytes_[used_++] = byte; return false; }
  if (used_ == 1 && byte != 0x4d) { used_ = byte == 0x42 ? 1 : 0; return false; }
  bytes_[used_++] = byte;
  if (used_ == 4 && word(bytes_.data() + 2) != 28) { used_ = 0; ++errors_; return false; }
  if (used_ < bytes_.size()) return false;
  used_ = 0;
  uint16_t sum = 0; for (size_t i = 0; i < 30; ++i) sum += bytes_[i];
  // PMS7003 v2.5 reserves bytes 28/29; do not reinterpret them as an error flag.
  if (sum != word(bytes_.data() + 30) || (model_ == PmsModel::Pms5003 && bytes_[29] != 0)) { ++errors_; return false; }
  PmReading next{word(bytes_.data() + 10), word(bytes_.data() + 12), word(bytes_.data() + 14), now, true};
  if (next.pm1 > 5000 || next.pm25 > 5000 || next.pm10 > 5000) { ++errors_; return false; }
  reading_ = next; return true;
}
uint8_t crc8(const uint8_t* data, size_t size) {
  uint8_t crc = 0xff;
  for (size_t i = 0; i < size; ++i) {
    crc ^= data[i];
    for (unsigned bit = 0; bit < 8; ++bit) crc = (crc & 0x80) ? static_cast<uint8_t>((crc << 1) ^ 0x31) : static_cast<uint8_t>(crc << 1);
  }
  return crc;
}
bool decodeScd(const uint8_t* bytes, size_t size, uint64_t now, ScdReading& out) {
  if (size != 9) return false;
  for (size_t i = 0; i < 9; i += 3) if (crc8(bytes + i, 2) != bytes[i + 2]) return false;
  ScdReading next{static_cast<double>(word(bytes)), -45.0 + 175.0 * word(bytes + 3) / 65535.0,
                  100.0 * word(bytes + 6) / 65535.0, now, true};
  // CO2=0 is the SCD4x invalid-measurement sentinel, not genuine zero ppm.
  if (next.co2 == 0 || next.co2 > 50000 || next.temperature < -40 || next.temperature > 85 || next.humidity < 0 || next.humidity > 100) return false;
  out = next; return true;
}
void Scd40::fail(uint64_t now) { ++errors_; state_ = State::Stop; due_ = now + 10000; }
void Scd40::tick(I2cBus& bus, uint64_t now) {
  if (now < due_) return;
  uint8_t bytes[9];
  switch (state_) {
    case State::Stop:
      if (!bus.command(0x3f86)) { fail(now); break; }
      state_ = State::Start; due_ = now + 500; break;
    case State::Start:
      if (!bus.command(0x21b1)) { fail(now); break; }
      state_ = State::Wait; due_ = now + 5000; lastSuccess_ = now; break;
    case State::Wait:
      if (now - lastSuccess_ > 20000 || !bus.command(0xe4b8)) { fail(now); break; }
      state_ = State::Ready; due_ = now + 1; break;
    case State::Ready:
      if (!bus.read(bytes, 3) || crc8(bytes, 2) != bytes[2]) { fail(now); break; }
      if ((word(bytes) & 0x7ff) == 0) { state_ = State::Wait; due_ = now + 1000; break; }
      if (!bus.command(0xec05)) { fail(now); break; }
      state_ = State::Read; due_ = now + 1; break;
    case State::Read:
      if (!bus.read(bytes, 9) || !decodeScd(bytes, 9, now, reading_)) { fail(now); break; }
      lastSuccess_ = now; state_ = State::Wait; due_ = now + 5000; break;
  }
}
bool Clock::synchronize(uint64_t epochMs, uint64_t uptime) {
  if (epochMs < 1735689600000ULL || epochMs > kMaxSafeInteger - 86400000) return false;
  epoch_ = epochMs; anchor_ = uptime; return true;
}
bool Clock::at(uint64_t sampled, uint64_t now, uint64_t& epochMs) const {
  if (!epoch_ || sampled < anchor_ || !fresh(anchor_, now, 86400000) || sampled > now) return false;
  epochMs = epoch_ + sampled - anchor_; return true;
}
static bool range(double n, double lo, double hi) { return std::isfinite(n) && n >= lo && n <= hi; }
bool valid(const Event& e) {
  return identifier(e.deviceId, 128) && identifier(e.eventId, 96) && e.sequence <= kMaxSafeInteger &&
    e.timestamp > 0 && e.timestamp <= kMaxSafeInteger && range(e.pm1, 0, 5000) && range(e.pm25, 0, 5000) && range(e.pm10, 0, 5000) &&
    (!e.scdAvailable || (range(e.co2, 1, 50000) && range(e.temperature, -40, 85) && range(e.humidity, 0, 100))) &&
    (!e.mqAvailable || (e.mq135Raw >= 0 && e.mq135Raw <= 4095));
}
bool serialize(const Event& e, std::string& json) {
  json.clear(); if (!valid(e)) return false;
  char base[640];
  std::snprintf(base, sizeof(base), "{\"device_id\":\"%s\",\"event_id\":\"%s\",\"sequence\":%s,\"timestamp\":%s,\"source\":\"hardware\",\"pm1\":%.2f,\"pm25\":%.2f,\"pm10\":%.2f",
      e.deviceId.c_str(), e.eventId.c_str(), std::to_string(e.sequence).c_str(), std::to_string(e.timestamp).c_str(), e.pm1, e.pm25, e.pm10);
  json = base;
  if (e.scdAvailable) { char fields[160]; std::snprintf(fields, sizeof(fields), ",\"co2\":%.0f,\"temperature\":%.4f,\"humidity\":%.4f", e.co2, e.temperature, e.humidity); json += fields; }
  if (e.mqAvailable) json += ",\"mq135_raw\":" + std::to_string(e.mq135Raw);
  json += '}'; return true;
}
bool assemble(const std::string& id, const std::string& bootId, uint64_t sequence, const PmReading& pm,
              const ScdReading& scd, int mqRaw, bool mqReady, const Clock& clock, uint64_t now, Event& event) {
  if (!identifier(bootId, 64) || !pm.valid || !fresh(pm.sampled, now, 10000)) return false;
  Event next; next.deviceId = id; next.eventId = bootId + "-" + std::to_string(sequence);
  next.sequence = sequence; if (!clock.at(pm.sampled, now, next.timestamp)) return false;
  next.pm1 = pm.pm1; next.pm25 = pm.pm25; next.pm10 = pm.pm10;
  next.scdAvailable = scd.valid && fresh(scd.sampled, now, 15000);
  if (next.scdAvailable) { next.co2 = scd.co2; next.temperature = scd.temperature; next.humidity = scd.humidity; }
  next.mqAvailable = mqReady && mqRaw >= 0 && mqRaw <= 4095; next.mq135Raw = mqRaw;
  if (!valid(next)) return false;
  event = next; return true;
}
void WifiRecovery::tick(WifiLink& link, uint64_t now) {
  if (link.connected()) { failures_ = 0; due_ = now; return; }
  if (now < due_) return;
  link.reconnect(); due_ = now + std::min<uint64_t>(60000, 1000ULL << std::min(failures_++, 6U));
}
void Outbox::pop() { entries_[head_] = Pending{}; head_ = (head_ + 1) % capacity; --count_; }
bool Outbox::enqueue(const Event& e) {
  if (count_ == capacity || unauthorized_) { ++dropped; return false; }
  std::string json; if (!serialize(e, json)) { ++rejected; return false; }
  entries_[(head_ + count_) % capacity] = {e.deviceId, json, 0, 0}; ++count_; return true;
}
void Outbox::tick(HttpTransport& http, bool wifi, bool timeValid, uint64_t now) {
  if (!count_ || unauthorized_ || !wifi || !timeValid) return;
  auto& p = entries_[head_]; if (now < p.due) return;
  const int status = http.post(p.deviceId, p.json); ++p.attempts;
  if (status == 202) { ++accepted; pop(); return; }
  if (status == 401 || status == 403) { unauthorized_ = true; return; }
  if (!(status <= 0 || status == 408 || status == 429 || status >= 500)) { ++rejected; pop(); return; }
  if (p.attempts >= 8) { ++exhausted; pop(); return; }
  p.due = now + std::min<uint64_t>(60000, 1000ULL << (p.attempts - 1));
}
}

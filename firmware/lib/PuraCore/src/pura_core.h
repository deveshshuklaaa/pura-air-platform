#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

namespace pura {
constexpr uint64_t kMaxSafeInteger = 9007199254740991ULL;
bool identifier(const std::string& value, size_t limit);
bool privateIpv4(const std::string& host);
bool validHost(const std::string& host);
bool fresh(uint64_t sampled, uint64_t now, uint64_t maxAge);

struct PmReading { uint16_t pm1 = 0, pm25 = 0, pm10 = 0; uint64_t sampled = 0; bool valid = false; };
enum class PmsModel { Pms5003, Pms7003 };
class PmsDecoder {
 public:
  explicit PmsDecoder(PmsModel model = PmsModel::Pms5003) : model_(model) {}
  bool feed(uint8_t byte, uint64_t now);
  const PmReading& reading() const { return reading_; }
  uint32_t errors() const { return errors_; }
 private:
  PmsModel model_;
  std::array<uint8_t, 32> bytes_{};
  size_t used_ = 0;
  uint64_t lastByte_ = 0;
  uint32_t errors_ = 0;
  PmReading reading_;
};

struct ScdReading { double co2 = 0, temperature = 0, humidity = 0; uint64_t sampled = 0; bool valid = false; };
uint8_t crc8(const uint8_t* data, size_t size);
bool decodeScd(const uint8_t* bytes, size_t size, uint64_t now, ScdReading& out);
class I2cBus {
 public:
  virtual ~I2cBus() = default;
  virtual bool command(uint16_t word) = 0;
  virtual bool read(uint8_t* bytes, size_t size) = 0;
};
class Scd40 {
 public:
  void tick(I2cBus& bus, uint64_t now);
  const ScdReading& reading() const { return reading_; }
  uint32_t errors() const { return errors_; }
 private:
  enum class State { Stop, Start, Wait, Ready, Read };
  State state_ = State::Stop;
  uint64_t due_ = 0, lastSuccess_ = 0;
  uint32_t errors_ = 0;
  ScdReading reading_;
  void fail(uint64_t now);
};

class Clock {
 public:
  bool synchronize(uint64_t epochMs, uint64_t uptime);
  bool at(uint64_t sampled, uint64_t now, uint64_t& epochMs) const;
 private:
  uint64_t epoch_ = 0, anchor_ = 0;
};
struct Event {
  std::string deviceId, eventId;
  uint64_t sequence = 0, timestamp = 0;
  double pm1 = 0, pm25 = 0, pm10 = 0;
  bool scdAvailable = false, mqAvailable = false;
  double co2 = 0, temperature = 0, humidity = 0;
  int mq135Raw = 0;
};
bool valid(const Event& event);
bool serialize(const Event& event, std::string& json);
bool assemble(const std::string& id, const std::string& bootId, uint64_t sequence,
              const PmReading& pm, const ScdReading& scd, int mqRaw, bool mqReady,
              const Clock& clock, uint64_t now, Event& event);

class WifiLink {
 public:
  virtual ~WifiLink() = default;
  virtual bool connected() = 0;
  virtual void reconnect() = 0;
};
class WifiRecovery {
 public: void tick(WifiLink& link, uint64_t now);
 private: uint64_t due_ = 0; unsigned failures_ = 0;
};
class HttpTransport {
 public:
  virtual ~HttpTransport() = default;
  // Negative = network/TLS/timeout error. Implementations must not follow redirects.
  virtual int post(const std::string& deviceId, const std::string& json) = 0;
};
class Outbox {
 public:
  static constexpr size_t capacity = 4;
  bool enqueue(const Event& event);
  void tick(HttpTransport& http, bool wifi, bool timeValid, uint64_t now);
  size_t size() const { return count_; }
  bool unauthorized() const { return unauthorized_; }
  uint32_t accepted = 0, dropped = 0, exhausted = 0, rejected = 0;
 private:
  struct Pending { std::string deviceId, json; uint8_t attempts = 0; uint64_t due = 0; };
  std::array<Pending, capacity> entries_{};
  size_t head_ = 0, count_ = 0;
  bool unauthorized_ = false;
  void pop();
};
}

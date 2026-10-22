#pragma once
#include <pura_core.h>

class EspWifi : public pura::WifiLink {
 public:
  void begin();
  bool connected() override;
  void reconnect() override;
};
class TimeSync {
 public:
  void begin();
  void tick(uint64_t now);
  const pura::Clock& clock() const { return clock_; }
  bool valid(uint64_t now) const;
 private: pura::Clock clock_;
};
bool runtimeConfigured();
uint64_t uptimeMs();

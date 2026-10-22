#pragma once
#include <pura_core.h>
class EspHttpTransport : public pura::HttpTransport {
 public: int post(const std::string& deviceId, const std::string& json) override;
};

#pragma once
#include <Wire.h>
#include <driver/uart.h>
#include <pura_core.h>
#include "board_config.h"

constexpr uart_port_t pmsUartPort = static_cast<uart_port_t>(board::pmsUart);
static_assert(pmsUartPort == UART_NUM_2, "Preserve existing PMS UART2 ownership");

class SensorAcquisition : public pura::I2cBus {
 public:
  bool begin();
  void tick(uint64_t now);
  bool command(uint16_t word) override;
  bool read(uint8_t* bytes, size_t size) override;
  const pura::PmReading& pm() const { return pms_.reading(); }
  const pura::ScdReading& scd() const { return scd_.reading(); }
  int mqRaw() const { return mqRaw_; }
  bool mqReady(uint64_t now) const { return board::mqEnabled && now >= board::mqWarmupMs && mqRaw_ >= 0; }
  uint32_t pmsErrors() const { return pms_.errors(); }
  uint32_t scdErrors() const { return scd_.errors(); }
 private:
  pura::PmsDecoder pms_{pura::PmsModel::Pms7003};
  pura::Scd40 scd_;
  bool initialized_ = false;
  uint64_t nextInit_ = 0, nextAdc_ = 0;
  int mqRaw_ = -1;
};

#include "sensor_acquisition.h"
#include <Arduino.h>

bool SensorAcquisition::begin() {
  if (!board::sensorIo) return false;
  // Optional TX is routed only by explicit local configuration; no PMS commands.
  uart_config_t cfg{};
  cfg.baud_rate = board::pmsBaud; cfg.data_bits = UART_DATA_8_BITS;
  cfg.parity = UART_PARITY_DISABLE; cfg.stop_bits = UART_STOP_BITS_1;
  cfg.flow_ctrl = UART_HW_FLOWCTRL_DISABLE; cfg.source_clk = UART_SCLK_APB;
  if (uart_param_config(pmsUartPort, &cfg) != ESP_OK ||
      uart_set_pin(pmsUartPort, board::pmsTx, board::pmsRx, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE) != ESP_OK ||
      uart_driver_install(pmsUartPort, 2048, 0, 0, nullptr, 0) != ESP_OK) {
    uart_driver_delete(pmsUartPort); return false;
  }
  if (!Wire.begin(board::sda, board::scl, 100000)) { uart_driver_delete(pmsUartPort); return false; }
  Wire.setTimeOut(50);
  if (board::mqEnabled) { analogReadResolution(12); analogSetPinAttenuation(board::mqAdc, ADC_11db); }
  initialized_ = true; return true;
}
bool SensorAcquisition::command(uint16_t word) {
  Wire.beginTransmission(0x62); Wire.write(static_cast<uint8_t>(word >> 8)); Wire.write(static_cast<uint8_t>(word));
  return Wire.endTransmission() == 0;
}
bool SensorAcquisition::read(uint8_t* bytes, size_t size) {
  if (Wire.requestFrom(static_cast<uint8_t>(0x62), static_cast<uint8_t>(size)) != size) {
    while (Wire.available()) Wire.read(); return false;
  }
  for (size_t i = 0; i < size; ++i) { if (!Wire.available()) return false; bytes[i] = Wire.read(); }
  return true;
}
void SensorAcquisition::tick(uint64_t now) {
  if (!board::sensorIo) return;
  if (!initialized_) { if (now >= nextInit_) { begin(); nextInit_ = now + 10000; } return; }
  // Network-stalled buffers are flushed by the main loop before this read.
  uint8_t bytes[256];
  const int count = uart_read_bytes(pmsUartPort, bytes, sizeof(bytes), 0);
  for (int i = 0; i < count; ++i) pms_.feed(bytes[i], now);
  // Allow at least the datasheet power-up interval before the first I2C command.
  if (now >= 1000) scd_.tick(*this, now);
  if (board::mqEnabled && now >= board::mqWarmupMs && now >= nextAdc_) {
    mqRaw_ = analogRead(board::mqAdc); nextAdc_ = now + 1000;
  }
}

# PURA AIR sensor-only ESP32 firmware

This is a compile/test implementation for an **explicitly provisional classic ESP32** (`esp32dev`, 4 MB flash). Phase 2C records a user-reported WROOM-DA/PMS7003 wiring map; the exact module marking, carrier board and physical connections remain unverified. Reported PMS RX25 conflicts with the WROOM-DA module design. Do not enable that map or select another pin until identification and schematic review resolve it. No board was flashed, no serial sensor data was read, and no calibration or bench-test result is claimed. ESP32-S2/S3/C3/C6 boards require a separately reviewed target and pin map.

The default build is deliberately unconfigured: all real pins are -1, sensor I/O and MQ sampling are off, and Wi-Fi/SNTP/HTTP do not start. The debug console still initializes. No blower, sprayer, pump, relay, MOSFET, PWM or actuator GPIO implementation exists. The PMS sensor's internal sampling fan is part of that sensor, not blower control.

## Layout and reproducible build

- `include/board_config.h`: configurable pins, explicit I/O opt-in and safe empty defaults.
- `lib/PuraCore/src/`: portable C++ PMS decoder, SCD40 state machine, model/JSON, clock policy, Wi-Fi recovery and four-event RAM FIFO.
- `src/sensor_acquisition.*`: PMS7003 UART reception (optional configured TX, no commands), bounded I2C and optional ADC adapters.
- `src/connectivity.*`, `http_transport.*`: Wi-Fi/SNTP and authenticated verified-TLS HTTP.
- `test/host_tests.cpp`: independent mocked bus/network tests and synthetic decoder/serializer fixture generator.
- `scripts/test_host.py`, `scripts/test_config.py`: portable core tests and compile-only configuration guard probes, no serial access.

From repository root in PowerShell:

```powershell
python -m venv firmware\.venv
firmware\.venv\Scripts\python.exe -m pip install -r firmware\requirements-lock.txt
$env:PLATFORMIO_CORE_DIR = "$PWD\firmware\.platformio"
$env:PIP_CONSTRAINT = "$PWD\firmware\requirements-lock.txt"
firmware\.venv\Scripts\python.exe -m platformio run --project-dir firmware -e esp32_provisional
python firmware\scripts\test_host.py --compiler C:\MinGW\bin\g++.exe --emit
```

On other hosts set `CXX` or pass the installed GCC/Clang C++ compiler path. The host script treats warnings as errors. `--emit` generates three **synthetic** JSON lines from mocked packets through the same decoder/serializer used by firmware; it does not read a device. The fixed fixture is committed under `test/fixtures/telemetry.ndjson` so backend regression checks require no C++ compiler. Regenerate/check it whenever the portable core changes.

Pins: PlatformIO Core 6.1.18; `platformio/espressif32` 6.12.0; Arduino-ESP32 2.0.17 (`3.20017.241212+sha.dcc1105b`); Xtensa compiler `8.4.0+2021r2-patch5`; esptool package `2.40900.250804`; SCons `4.40801.0`. No external sensor/JSON libraries or app dependency upgrades are needed. The platform's exact manifest and framework package tie the built-in Wire, WiFi, HTTPClient, WiFiClientSecure and SNTP APIs to these versions. Resolved Python tooling versions, including esptool's package-local `_contrib` helpers, are recorded in `requirements-lock.txt`. The process-local `PIP_CONSTRAINT` bounds the tool package's own post-install resolution on subsequent fresh installs. Nothing is installed into application packages or the global Python environment.

No upload command is part of these instructions. The build produces firmware only; flashing requires later explicit authorization after hardware review.

## Hardware review: reported map, not verified wiring

| Interface | Default | User-reported connection only | Must verify |
| --- | --- | --- | --- |
| PMS7003 TX → ESP1 RX | disabled, pin -1 | GPIO25, UART2, 9600 8N1 | **Blocked for reported WROOM-DA**; module identity and exact header connection unresolved |
| ESP1 TX → PMS7003 RX | disabled, pin -1 | GPIO26, same UART2 | Carrier schematic, connector and logic levels; no PMS command implementation |
| PMS7003 SET/RESET | no controller output configured | unspecified | Active/awake state and actual connector; no SET/RESET control is implemented |
| SCD40 SDA/SCL | disabled, pins -1 | GPIO21/GPIO22, 100 kHz I2C, address 0x62 | Actual board pins; pull-ups and logic rails |
| MQ-135 analog | disabled, pin -1 | GPIO34, ADC1, 12-bit, 11 dB attenuation | Input voltage/divider, load, reference, module and ground |
| ESP1 RX/TX ↔ ESP2 TX/RX | disabled, pins -1 | ESP1 RX16/TX17, crossed with ESP2 TX17/RX16; 115200 | Common ground/levels; **UART1 reservation only, no communication implemented** |

The example records the reported map with both enable flags false; it is not approved wiring. No local header is created by a build. `PURA_REPORTED_WROOM_DA` defaults true as a conservative restriction: enabling sensor I/O with GPIO2/25 fails compilation even if that flag is omitted. Setting it false is not board identification or electrical approval. The example cannot be enabled as supplied. No replacement GPIO is selected. Check actual module/carrier flash, boot strapping, PSRAM and reserved pins before any future configuration. The ADC1-only guard (GPIO32–39) does not establish safe AO voltage or pin availability. See the [GPIO25 conflict audit and electrical prerequisites](../docs/development/PHASE_2B_PREFLIGHT.md#gpio25-hardware-conflict-audit).

PMS retains the existing UART2 peripheral; all configuration/read/flush operations share one constant. UART1 is reserved for a possible later ESP2 implementation and is never initialized here; console UART0 remains distinct. GPIO16/17 native function labels do not assign peripheral ownership. Optional PMS TX26 would be routed only after explicit local configuration and sensor enable; no UART command writes exist.

Electrical requirements to verify before connecting anything:

- Classic ESP32 uses 3.3 V I/O; it is not a 5 V-tolerant ADC/input. Use one board supply method and a common signal ground. Confirm regulator/USB/power capacity for all sensors and radio current; do not feed a heater from a GPIO or assume the board 3.3 V rail can supply it.
- PMS7003: manufacturer specifies 4.5–5.5 V supply (typical 5 V), up to 100 mA active, 3.3 V UART logic. Verify the actual connector/adapter rather than reusing a PMS5003 connector diagram. The adapter selects PMS7003 decoding: atmospheric PM1/PM2.5/PM10, valid header/length/checksum; reserved bytes 28/29 may be nonzero. Portable PMS5003 mode preserves its previous error-byte behavior for existing fixtures. Partial packets expire after 500 ms, startup is gated for 30 seconds, and valid packets age out after 10 seconds. Passive-mode control is unimplemented; active output is required.
- SCD40: bare sensor supply range 2.4–5.5 V; select a supply and I2C pull-ups compatible with 3.3 V ESP32 inputs (or appropriate level conversion). A breakout may have different power/pull-up requirements. **Power only one supported breakout supply input at a time.** Budget datasheet peak current, decoupling and power-up timing; an I2C address alone does not establish electrical compatibility. Periodic CO2 is ppm; temperature °C and relative humidity %. Self-heating, enclosure offset, pressure/altitude and automatic self-calibration assumptions need bench review; no calibration configuration is written by this code.
- MQ-135: typical heater/circuit supply 5 V, heater up to 950 mW. Module analog output can exceed the ESP32 limit: verify and design a divider/buffer/protection before enabling the ADC. Attenuation is **not** overvoltage protection. Only integer `mq135_raw` 0–4095 is reported, after a conservative 48-hour uptime gate matching initial conditioning guidance; this is not a substitute for conditioning after storage, stable power, environmental compensation or reference-gas calibration. Reboot restarts the gate. Raw zero is a literal ADC result, not a claim of clean air. No gas concentration, VOC concentration or `gas_index` is inferred. A floating/disconnected input cannot reliably be detected in software; keep it disabled until the analog circuit is verified.

## SCD40 acquisition and unavailable readings

The custom driver follows the manufacturer's command protocol, so there is no unverified third-party sensor library. It sends stop-periodic (0x3f86), waits 500 ms, starts periodic measurement (0x21b1), waits five seconds, checks data-ready (0xe4b8), then reads (0xec05). Read commands wait at least 1 ms and verify each word's CRC-8 (poly 0x31, initial 0xff). CO2 zero is an invalid sensor sentinel; corrupt, short or contract-out-of-range measurements are rejected. Temperature and humidity use the datasheet 16-bit conversion formulas; JSON rounds them to four decimal places.

I2C transactions time out after 50 ms; NACK/CRC/short-read failure restarts initialization after ten seconds. Missing ready data for over 20 seconds also restarts. Previous valid data is retained only for freshness evaluation: SCD values older than 15 seconds are omitted together. PMS errors do not renew its previous timestamp; stale/missing PM suppresses the entire event because PM2.5/PM10 are required. Sensor transport initialization is retried every ten seconds. The main loop flushes buffered UART data after a network stall over 500 ms so those bytes cannot be timestamped as new samples. Bounded synchronous HTTP may therefore drop sensor frames; subsequent active frames recover. No missing sensor is replaced with zero or random data.

## Telemetry, clock and delivery policy

The unchanged [telemetry v2 contract](../docs/development/TELEMETRY_CONTRACT.md) is the wire contract. Device ID must match an explicitly active provisioned registry record and private per-device credential. Generated JSON contains exactly `device_id`, `event_id`, `sequence`, `timestamp`, `source: hardware`, `pm1`, `pm25`, `pm10`, and available SCD fields/`mq135_raw`. Firmware computes no official AQI, gas index or local particulate indicator; the existing backend does that.

Wi-Fi initializes before generating a 128-bit random boot nonce. Event ID is `<boot nonce>-<sequence>`, generated once on enqueue. Sequence starts at one each boot; a new random boot nonce separates sessions. It is not persisted or globally monotonic. No probabilistic uniqueness is described as an absolute guarantee. JSON bytes, original measurement timestamp and sequence are frozen in the pending entry through every retry.

SNTP is required before creating/sending telemetry. Time is UTC Unix milliseconds anchored to 64-bit monotonic uptime; the event timestamp represents the last valid PMS packet arrival, not the send time. Optional SCD/ADC values are recent asynchronous sensor samples (no per-field timestamps are added to v2). Before the first confirmed SNTP callback, for a pre-anchor PMS packet, or after 24 hours without a successful sync, event creation/transmission pauses. There is no invented epoch or fallback to uptime. SNTP retries are provided by the pinned framework, and new samples resume after synchronization. SNTP itself is unauthenticated and clock accuracy/host reachability need bench verification; TLS certificate validity also relies on a correct wall clock.

The four-event FIFO is **RAM only**, approximately four bounded JSON records (each under 1 KiB), with drop-new on full. Reboot/power loss loses unsent data; no local durable-delivery or exactly-once claim is made. Samples are attempted every ten seconds. Wi-Fi reconnect attempts back off 1/2/4/8/16/32/60 seconds, then remain capped at 60 seconds. Offline or unsynchronized periods do not consume HTTP attempts. Per-event HTTP attempts are capped at eight, with 1/2/4/8/16/32/60-second backoff for network/TLS/timeout errors, 408, 429 and 5xx. On exhaustion that event is dropped and counted so the FIFO can advance. A 401/403 latches an authentication fault, stops all sends/new enqueueing, and requires correcting credentials and rebooting; it never storms the server. Other non-202 statuses (including conflicts, validation errors and redirects) are terminal rejected events. Diagnostics are counters/health flags only, not keys, passwords, tokens, sensor payloads or response bodies. Backoff is deterministic; fleet jitter and durable offline storage are future work.

HTTP **202 means durable backend acceptance**, not completion in both databases or physical actuation. Firmware releases that pending event after 202; it does not poll completion or automatically replay backend terminal failures. Operators can use the authenticated status endpoint and documented trusted recovery procedure separately. Timeout or a lost 202 retries the identical event safely with backend identity deduplication.

## Local network, credentials and TLS

Local configuration remains on hold until the GPIO25/module conflict and electrical review are resolved. A later separately authorized setup must deliberately select Wi-Fi/device/API settings. No production URL or secret is supplied. Secrets would be compiled into the device image in this initial implementation, so protect any future ignored header, build directory and binary; secure provisioning/flash encryption is follow-up work. Never paste a real key into a tracked example or ordinary logs.

HTTPS is the default and requires a selected root CA PEM. WiFiClientSecure verifies the CA chain and host; the firmware never calls `setInsecure`. TLS handshake, connect and socket read timeouts are set to five seconds each. These are individual operation bounds, not a guarantee of a five-second total request under all server behavior. HTTP redirects are disabled to prevent forwarding the ingestion key to another destination. CA expiry/rotation and real TLS failures require a bench test.

For deliberately isolated LAN development only, `PURA_API_TLS=false` additionally requires `PURA_ALLOW_PRIVATE_HTTP=true` and a numeric RFC1918 API host such as `192.168.1.20`, with an explicit port such as 18088. This sends the fixture ingestion key in cleartext; use only isolated demo credentials/network. ESP32 `localhost` refers to the ESP32, not the developer PC; loopback/URLs in the host field are refused. Confirm Wi-Fi routing, the PC's selected listener address and a narrowly scoped firewall rule yourself. No LAN listener, firewall rule, production provisioning or network exposure is created automatically. The existing emulator fixture API binds loopback; its successful phone USB test does not make it reachable from ESP32 over Wi-Fi.

Run the integrated software checks from `backend/` with the existing documented Java workaround if needed: `npm run check`, `npm test`, `npm run test:emulators`. The additional Firebase case reads the C++ serializer fixture, validates the exact backend schema, uses the existing simulator's authenticated HTTP sender, asserts saved fields and duplicates, and refuses all nonlocal databases. The fixed fixture uses a controlled acceptance clock in this isolated test only; production acceptance policy is unchanged. The `source: hardware` field exercises the real firmware schema, but the test data remains synthetic and must not be described as sensor evidence.

## Verified API/license sources

No source was copied from a sensor driver. Custom protocol implementation/tests use these manufacturer references. PlatformIO's platform is Apache-2.0; the pinned Arduino built-in libraries reviewed here carry LGPL-2.1-or-later notices. Retain upstream notices in redistributed dependencies and review binary distribution obligations before publishing firmware.

- [PlatformIO esp32dev target](https://docs.platformio.org/en/stable/boards/espressif32/esp32dev.html) and [pinned platform manifest](https://github.com/platformio/platform-espressif32/blob/v6.12.0/platform.json).
- [Espressif DevKitC V4 guide](https://docs.espressif.com/projects/esp-dev-kits/en/latest/esp32/esp32-devkitc/user_guide.html) — candidate board reference, not identification of the user's hardware.
- [Plantower PMS5003 v2.3 manufacturer manual, hosted by Adafruit](https://cdn-shop.adafruit.com/product-files/3686/plantower-pms5003-manual_v2-3.pdf).
- [Plantower PMS7003 v2.5 manufacturer manual, hosted by Espruino](https://www.espruino.com/datasheets/PMS7003.pdf), Appendix I (PDF pages 13–14).
- [Espressif ESP32-WROOM-DA v0.7 datasheet](https://www.espressif.com/sites/default/files/documentation/esp32-wroom-da_datasheet_en.pdf), section 3.2, Table 2 note 2 / Table 3, printed page 11: GPIO2/25 are internal RF-switch controls; the generic build target does not identify this module.
- [Sensirion SCD4x datasheet v1.3](https://sensirion.com/en/media/documents/E0F04247/631EF271/CD_DS_SCD40_SCD41_Datasheet_D1.pdf).
- [Winsen MQ-135 manufacturer manual](https://www.winsen-sensor.com/manual/mq135.html).
- Pinned Arduino [HTTPClient API/license](https://github.com/espressif/arduino-esp32/blob/2.0.17/libraries/HTTPClient/src/HTTPClient.h) and [WiFiClientSecure API/license](https://github.com/espressif/arduino-esp32/blob/2.0.17/libraries/WiFiClientSecure/src/WiFiClientSecure.h).

See [Phase 2A actual results and next bench steps](../docs/development/PHASE_2A_RESULTS.md).

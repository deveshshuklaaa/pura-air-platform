# Phase 2A — ESP32 sensor firmware and telemetry integration

Work and validation: 21–22 October 2026, Asia/Calcutta. Repository `C:\dev\PuraAir`, branch `feat/pura-air-stabilization`, HEAD `e5ec5da2ed325be411ea3c2bbf9129f9d75e36c4`.

## Outcome and evidence boundaries

The sensor-only firmware architecture compiles for an **explicitly provisional classic ESP32 target**. Portable sensor/telemetry/recovery tests and the real local Firebase integration pass. The owner confirmed that the exact board variant and wiring have not been identified; no attached ESP32/sensor was read, flashed, reset, calibrated or bench-tested. Hardware operation remains unverified. Software build/test evidence must not be described as real sensor evidence.

The target is PlatformIO `esp32dev`, ESP32 240 MHz, 320 KiB RAM, 4 MB flash, Arduino-ESP32 2.0.17. This is a compilation assumption, not identification of the actual board. No fan, mist sprayer, pump, relay, MOSFET, PWM or actuator GPIO code was added. The default configuration disables sensor I/O and networking; explicit reviewed pins and private network/credential configuration are required before operation.

Read [firmware setup, protocol, wiring and electrical requirements](../../firmware/README.md). Candidate classic ESP32 pins are UART2 RX GPIO16, SCD40 SDA/SCL GPIO21/22, and MQ-135 ADC1 GPIO34. Actual defaults are disabled/pin -1. Those candidates are not verified assignments, do not apply automatically to other ESP32 variants, and are configurable in ignored `firmware/include/local_config.h`.

## Implementation

- Separate `firmware/` PlatformIO/Arduino project; no replacement of Flutter, Node or Firebase architecture.
- PMS5003 streaming decoder checks framing, 28-byte declared length, 32-byte packet, checksum, sensor-error byte and protocol ranges. It uses atmospheric-environment PM1/PM2.5/PM10 words, µg/m³, rather than CF=1/particle-count words. Noise, truncated/corrupt frames and packet timeouts do not renew valid-reading timestamps. UART is RX-only, no default TX output. Startup gate is 30 seconds, stale cutoff 10 seconds; missing/stale required PM suppresses an event.
- Custom SCD40 I2C driver at 0x62 uses stop/start/ready/read commands, datasheet waits, CRC-8 and temperature/humidity conversion. CO2 zero is invalid sensor data. NACK, short data, CRC error and missing-ready timeout trigger bounded reinitialization; stale optional SCD values are omitted after 15 seconds. Adapter calls are bounded and the initial power-up interval is observed. No third-party sensor library or calibration write is used.
- Optional MQ-135 uses reviewed ADC1 input, 12-bit resolution, 11 dB attenuation and raw integer `mq135_raw` only. It is disabled by default, with a conservative 48-hour uptime conditioning gate if enabled. No gas/VOC concentration or validated gas index is invented. The electrical review must protect the ADC from a module output above the ESP32 input limit; attenuation is not overvoltage protection. Floating-input detection/calibration cannot be established from software tests.
- The portable C++ model validates and serializes the existing v2 fields with no contract revision. Device ID must match trusted provisioning. A per-boot 128-bit random nonce plus monotonic session sequence identifies an event; sequence resets after reboot under a new nonce. Pending JSON bytes, event ID and original timestamp are retained during retries.
- UTC time requires a confirmed SNTP synchronization and uses 64-bit monotonic uptime for sample timestamps. Missing/invalid initial sync, pre-anchor samples and over 24 hours without a successful sync suppress creation/sending. Device timestamps represent PMS packet arrival, not HTTP send time. Optional sensor values are recent asynchronous samples; v2 has no per-field timestamps. No uptime-as-Unix-time fallback is used.
- Wi-Fi retries with bounded exponential spacing. Four-event RAM FIFO, drop-new on full; eight transient HTTP attempts per event with capped exponential backoff. Network/TLS/timeout failures, 408, 429 and 5xx retry the same bytes. 401/403 latch an authentication fault until corrected reboot; other non-202 statuses are terminal rejected events. HTTP 202 releases an event as durably accepted, not fully processed or physically executed. Counter-only diagnostics omit secrets, raw payloads and response bodies.
- HTTPS uses a configured CA and hostname verification, never `setInsecure`; redirects are disabled. Connect, read and TLS handshake operations have individual timeouts. Plain HTTP requires explicit isolated-development opt-in and numeric RFC1918 host. No production endpoint/secret is supplied or guessed. The ESP32 cannot use its own localhost to reach the PC; LAN listener/routing/firewall changes require deliberate setup and were not performed.

## Dependencies and hardware references

PlatformIO Core 6.1.18 is installed only in the ignored repository-local virtual environment. `platformio.ini` pins platform `espressif32` 6.12.0, framework `3.20017.241212+sha.dcc1105b`, Xtensa compiler `8.4.0+2021r2-patch5`, esptool `2.40900.250804` and SCons `4.40801.0`. Built-in Wire/WiFi/HTTPClient/WiFiClientSecure report library version 2.0.0 inside the pinned Arduino-ESP32 2.0.17 framework. Resolved Python tooling and package-local esptool helpers are recorded in `firmware/requirements-lock.txt`; setup instructions apply those pins as install constraints. These helpers live in the ignored tool package `_contrib`, not global Python or the app. No npm/Flutter dependency versions or application lockfiles changed.

Manufacturer protocol/electrical documentation and pinned framework APIs/licenses were reviewed before implementation; links are in the firmware README. Sensor drivers are original protocol implementations without external sensor/JSON library dependencies. The referenced platform carries Apache-2.0 and the reviewed Arduino built-in libraries carry LGPL-2.1-or-later notices. Board-specific electrical compatibility, supply capability, pull-ups, analog scaling, thermal behavior and calibration remain bench prerequisites.

## Actual checks

| Check | Actual outcome |
| --- | --- |
| Host C++ tests: `python firmware/scripts/test_host.py --compiler C:\MinGW\bin\g++.exe --emit` | Exit 0, **15 passed**; GCC 6.3.0, C++17, `-Wall -Wextra -Werror` |
| Firmware: local venv `python -m platformio run --project-dir firmware -e esp32_provisional` with workspace-local core directory | Exit 0, firmware ELF/bin generated; final rebuild **26.20 s** |
| Firmware size | RAM 47,728 / 327,680 bytes (14.6%); flash 936,365 / 1,310,720-byte app partition (71.4%); unconfigured default build |
| Backend `npm run check` and new integration-file syntax check | Exit 0 |
| Backend `npm test` | Exit 0, **30 passed**, unchanged Phase 1A/1B cases |
| `npm run test:emulators` | Exit 0, **17 passed**: unchanged Phase 1A 12 + Phase 1B 4 + firmware fixture integration 1 |
| Focused app listener regression | Exit 0, 1 passed |
| Final Flutter analysis/tests | Exit 0, no analysis issues; **23 tests passed**, the original 22 plus the listener regression |
| Final physical Samsung regression | Exit 0, **1 passed** after all 17 Firebase tests reran; isolated debug APK built/installed on SM-S928B, Android 16 / API 36 |
| `git diff --check` | Passed; final preservation/status check recorded below |
| Actual ESP32/sensor bench read | **Not performed**; board/wiring unknown, not authorized to flash |
| Real Wi-Fi/TLS/ADC/sensor electrical validation | **Not performed**; host mocks/build checks are not hardware validation |

Host cases cover valid/invalid PMS packets, atmosphere vs CF=1 selection, incomplete-frame recovery, known SCD CRC, physical conversions and sentinel/range rejection, I2C init failure, malformed/missing responses, timeout/recovery, invalid/expired clock, stale required/optional readings, MQ raw bounds, exact allowed JSON and omission, Wi-Fi recovery, HTTP timeout/overload/authorization/redirect handling, byte-identical retries and bounded FIFO exhaustion.

The three fixed **synthetic** fixture lines at [firmware/test/fixtures/telemetry.ndjson](../../firmware/test/fixtures/telemetry.ndjson) are generated by compiled C++ through mocked sensor packets and the production decoder/serializer module. They contain PM2.5 `[14,17,20]`, PM10 `[45,45,45]`, CO2 460 ppm, temperature 23.6007 °C, humidity 48.0003%, MQ raw 603, stable nonce/sequence IDs and fixed Unix-millisecond timestamps. The real emulator test validates these exact payloads against the unchanged backend contract, submits through the existing simulator's authenticated HTTP sender, verifies durable receipts, exact history/RTDB fields, forecast source and duplicate receipt/history identity. Its controlled fixture acceptance clock is test injection, not a production timestamp-policy change. `source: hardware` exercises the real wire format but does not turn mocked sensor data into physical evidence.

The first phone rerun found a pre-existing `HomeShell` issue: raw `ProviderSubscription` return context inferred dynamic callback values, so `next.whenData(...)` attempted an instance call to an extension method. It failed when a live device update arrived during that startup timing. Both subscriptions now retain their typed `AsyncValue` parameters, with one delayed-device/sign-out regression. Existing owner/shared authorization and navigation behavior are retained. This narrow app repair is required to keep the simulator-to-dashboard acceptance path functional; firmware did not replace that path.

The final physical-phone run printed `PURA_PHYSICAL_E2E_PASS pm25=19.6 pm10=45 co2=460 history=3 source=simulator`, `All tests passed!` and `physical_suite_exit=0`. It asserted exact dashboard text/units and real history/chart values via native Firebase plugins. Final run event IDs were `phone-1792607575948-000001` through `phone-1792607575948-000003`. It used only demo-project local Firebase services and temporary USB forwarding, which was verified empty after cleanup. No Android emulator or physical sensor was used. Local services shut down successfully.

Failed development checks were not counted as passes: initial host compilation exposed format portability/indentation warnings, corrected before all 15 passed. The first listener test fixture omitted required nullable snapshot arguments; that was corrected. Its first single-subscription mock also hung during intentional provider invalidation and was interrupted; the final test uses broadcast streams and passes. The initial physical-phone rerun failed with the listener exception above; the final rerun is recorded separately. First-time PlatformIO download/extraction completed successfully (767.77 seconds); no missing-tool/dependency result is represented as successful compilation.

## Preservation, final status and exact scope

At entry there were 32 tracked modifications and 29 untracked files from earlier phases. A SHA-256 manifest of all 61 existing changed/untracked files was captured before coding. Earlier reports/contracts, source changes, security rules and tests remain intact. Emulator/phone runs regenerate two prior fixture artifacts; their entry copies are preserved and restored after recording the new run so the Phase 1B report continues to match its original artifacts. Only two entries in that initial manifest are intentionally extended: `backend/package.json` and `backend/scripts/test-emulators.js`, each to include the additional firmware integration test. `lib/screens/home_shell.dart` was clean at entry and receives the narrow listener repair.

Modified existing files in Phase 2A (3):

```text
backend/package.json
backend/scripts/test-emulators.js
lib/screens/home_shell.dart
```

New files in Phase 2A (22):

```text
backend/test/firmware-emulator.test.js
docs/development/PHASE_2A_RESULTS.md
firmware/.gitignore
firmware/platformio.ini
firmware/requirements.txt
firmware/requirements-lock.txt
firmware/README.md
firmware/include/board_config.h
firmware/include/local_config.example.h
firmware/lib/PuraCore/src/pura_core.h
firmware/lib/PuraCore/src/pura_core.cpp
firmware/src/sensor_acquisition.h
firmware/src/sensor_acquisition.cpp
firmware/src/connectivity.h
firmware/src/connectivity.cpp
firmware/src/http_transport.h
firmware/src/http_transport.cpp
firmware/src/main.cpp
firmware/test/host_tests.cpp
firmware/test/fixtures/telemetry.ndjson
firmware/scripts/test_host.py
test/home_shell_test.dart
```

Final preservation check: **59 of the 61 entry files are byte-identical**, including all earlier reports/contracts and both original fixture artifacts. The remaining two are exactly the intentionally extended backend test configuration files above. Final combined Git status is **33 tracked modified files, 51 untracked files, no staged changes and no deletions**, including all earlier-phase work. Branch/HEAD are unchanged, and `git diff --check` passes. The 19 new firmware files also have no trailing whitespace. Tool caches, venv, binaries, local configuration and logs are ignored. No staging, commits, pushes, merges, deployment, production migration or production Firebase writes occurred. No firmware flashing command, sensor port access, firewall change or actuator operation occurred.

## Remaining limits and next bench test

1. Identify the actual ESP32 module/board, flash size and schematic; verify pins and UART/I2C/ADC availability. Inspect exact sensor/breakout connectors, 3.3 V logic, supply/current/decoupling, grounds, pull-ups and MQ analog maximum. Keep actuators disconnected. Do not reuse the candidate pin map without that check.
2. After explicit separate permission to flash, supply local private test configuration, build for the verified board, then perform a sensor-only bench read. Compare PMS serial frames/checksum and SCD CRC/CO2/T/RH to reference instruments; verify warm-up and disconnect/reconnect behavior. Inspect MQ conditioning/input scaling before enabling raw ADC reporting. No calibration result is implied by protocol-valid readings.
3. Test actual Wi-Fi outages, clock failure/adjustment, DNS, TLS valid/wrong-host/untrusted/expired certificate cases, HTTP timeouts, 503 and lost-202 behavior against a deliberately reachable isolated backend. The host tests mock transport outcomes; they do not establish radio or TLS handshake behavior on hardware.
4. The RAM outbox loses unsent events on reboot/power loss and can drop on full/exhaustion. A future durable flash outbox needs a separately designed/tested wear, corruption and replay policy. No exactly-once claim is made. Authentication faults require correction and reboot; firmware does not poll durable backend completion or automatically replay terminal backend failures.
5. Individual HTTP/TLS operations are bounded but synchronous; stalled UART buffers are deliberately discarded rather than labelled fresh. This is not a real-time acquisition guarantee. Field-specific timestamps, fleet retry jitter, long-term retention/storage policy, secure credential provisioning/flash encryption and sensor calibration remain follow-up work. No physical control is enabled by this milestone.

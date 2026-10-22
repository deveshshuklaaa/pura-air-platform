# Phase 2B preflight — hardware identification and bench-test readiness

> Phase 2C reconciliation update: the original Phase 2B observations/status below are historical. The reported ESP1 wiring and current reconciliation findings are recorded in the Phase 2C addendum at the end; reported connections are not measured electrical evidence.

Date: 22 October 2026, Asia/Calcutta. Repository: `C:\dev\PuraAir`. Branch: `feat/pura-air-stabilization`. HEAD: `e5ec5da2ed325be411ea3c2bbf9129f9d75e36c4`.

**Disposition: software preflight passes; physical assembly is not yet cleared for power-on or flashing.** The actual ESP32 board, fitted sensor modules, supply arrangements and wiring remain unidentified. All hardware table entries below are unverified. This document is a plan for a later authorized bench session, not evidence that any wiring or physical test succeeded.

This preflight adds only this report. It does not change firmware, pin settings, credentials, telemetry, security rules, application code or dependencies. No serial port was opened, hardware reset or flash command run, firewall changed, or Firebase service contacted. No local configuration/credential file was created. No commit, push, merge, deployment or production migration occurred.

## 1. Evidence required before selecting a real board target

Record the following in a bench log; leave unknown fields explicitly unverified rather than copying example values:

| Required evidence | Current status / question to resolve |
| --- | --- |
| Controller board | **Unverified:** clear front/back photographs, maker, model, revision and header silkscreen; exact text on the RF module/shield and chip/package where visible |
| Board documentation | **Missing:** schematic/pinout matching that revision, module datasheet, flash/PSRAM details, regulator and power-path ratings; establish whether it is classic ESP32, WROVER, S2, S3, C3, C6 or another variant |
| PMS module | **Unverified:** actual part label, connector pin-1 orientation, cable pin-to-pin continuity and any adapter board; confirm active-mode PMS5003 compatibility |
| CO2 module | **Unverified:** SCD40 vs other SCD4x part, bare sensor vs breakout, breakout revision, regulator/level-shifter/pull-up schematic |
| Analog gas module | **Unverified:** MQ-135 part/module, heater/circuit connections, load resistor, analog output path, potentiometer/comparator circuit if fitted; distinguish AO from DO |
| Supplies | **Unverified:** selected board input, supply ratings/current limit, cables, sensor rails, regulator peak capacity, protection and prevention of USB/external-supply backfeed |
| Physical wiring | **Unverified:** complete power-off wire list/net diagram, header positions, resistor/divider values and tolerances, pull-up rail, common grounds, connector orientation and continuity results |
| Actuator isolation | **Unverified:** photograph/inspection showing blower, pump, sprayer, relay and MOSFET loads disconnected from power and controller signals |
| Instruments and references | **Unverified:** suitable meter, current-limited supply, logic capture equipment if available, reference PM/CO2/T/RH instruments and their calibration/status |
| Bench network | **Unapproved/unconfigured:** isolated non-production destination, verified TLS hostname/CA arrangement, routing and emulator-only backend plan; do not put passwords/keys in this log |

The current `esp32dev` target is only a **provisional classic ESP32, 4 MB flash compilation target**. A successful build cannot identify a board or prove that its pins, power rails or boot behavior match this assumption. Do not use software detection that opens a serial port during this preflight; USB serial tools may toggle reset/download lines.

## 2. Source review and disabled-default confirmation

Reviewed `firmware/platformio.ini`, `include/board_config.h`, `include/local_config.example.h`, every `src/` and `lib/PuraCore/src/` source/header, the host-test runner, and the relevant backend/mobile integration changes and earlier contracts. Platform/framework/tool versions remain pinned as documented in [the firmware guide](../../firmware/README.md).

| Behavior | Current code and review finding |
| --- | --- |
| Sensor I/O | `PURA_SENSOR_IO_ENABLED=false`; `board::sensorIo=false`; actual default UART/I2C/ADC pins are all `-1`. The example's candidate pins do not apply unless separately copied/selected. No local header exists. |
| Networking and sensor startup | `runtimeConfigured()` requires sensor opt-in plus syntactically valid device/network/auth/TLS configuration. With defaults it is false. `setup()` returns before Wi-Fi initialization, SNTP or sensor startup; `loop()` only delays while unconfigured. |
| MQ-135 | `PURA_MQ135_ENABLED=false`; attenuation/ADC setup is behind that opt-in. Sampling additionally requires sensor I/O, successful transport initialization and the 48-hour uptime gate. |
| Credentials and destination | Wi-Fi SSID/password, device ID, ingestion key, API host and root CA are empty. TLS is selected by default, private HTTP opt-in is false. No destination is guessed. |
| Enabled sensor interfaces, if later approved | UART2 is configured RX-only; no TX pin is assigned by the acquisition adapter. I2C uses the selected SDA/SCL at 100 kHz and address 0x62. ADC is input-only. These sensor interfaces must still be electrically reviewed. |
| Actuator implementation | No application `pinMode`/`digitalWrite`, PWM/LEDC, DAC, relay/MOSFET output, actuator subscription or command-execution path exists in firmware. The portable core contains only acquisition/telemetry/clock/retry logic. Existing mobile/backend cloud-control echoes are not consumed by this firmware and do not prove physical execution. |
| Important exception to electrical silence | `Serial.begin(115200)` and a configuration-disabled diagnostic run before the gate. Boot ROM, board pull resistors and debug UART can affect pins. **Disabled telemetry is not a promise that every pin stays electrically quiet.** Unknown external loads must remain disconnected. |

A temporary host-only compile assertion probe also confirmed disabled sensor/MQ flags, unset pins, empty network/device/key/host defaults, TLS selected and private HTTP disabled. It executed no serial, Wi-Fi or GPIO API. Build-flag overrides were cleared only in the build process, and absence of `include/local_config.h` was checked before building. No settings were persisted.

## 3. Pin-verification worksheet — no verified assignments yet

Fill the actual board/module and revision first: **UNVERIFIED**. Record a schematic reference, physical header position and reviewer/date for every approved net. GPIO numbers are not header-pin numbers.

| Net / firmware setting | Code default | Existing example candidate, classic ESP32 only | Required board-specific verification | Physical result |
| --- | --- | --- | --- | --- |
| PMS TX → `PURA_PMS_RX` | -1, disabled | GPIO16 / UART2 RX — **PROVISIONAL** | Exposed RX-capable GPIO; not PSRAM/reserved; exact sensor TX connector pin and logic voltage | **UNVERIFIED** |
| PMS RX/SET/RESET | No controller output assigned | No MCU connection planned — **PROVISIONAL** | Actual adapter pull states and active/awake behavior; do not improvise jumpers | **UNVERIFIED** |
| SCD SDA → `PURA_I2C_SDA` | -1, disabled | GPIO21 — **PROVISIONAL** | Available bidirectional/open-drain-capable net, breakout translation and pull-up rail | **UNVERIFIED** |
| SCD SCL → `PURA_I2C_SCL` | -1, disabled | GPIO22 — **PROVISIONAL** | Available clock/open-drain-capable net, pull-up value/effective parallel resistance | **UNVERIFIED** |
| MQ AO → `PURA_MQ135_ADC` | -1, disabled | GPIO34 / ADC1 — **PROVISIONAL** | Actual chip ADC channel, exposed header, reviewed divider/buffer and voltage limits; not module DO | **UNVERIFIED** |
| Debug serial | Board/framework default, 115200 | UART0 on a classic target — **PROVISIONAL** | Actual USB bridge/USB mode, console routing and reset-line behavior; no shared actuator net | **UNVERIFIED** |
| Board power, sensor rails and return | Not assigned by firmware | None approved | Exact supply pins/polarity, regulator limits, common signal return and no backfeed | **UNVERIFIED** |
| All actuator nets | No firmware assignment | None permitted in this milestone | Disconnect loads and their power/control wiring, including external pulls that could turn them on | **UNVERIFIED / KEEP DISCONNECTED** |

For the reference DevKitC, GPIO16/17 differ in availability between WROOM/SOLO and WROVER modules. The actual board may differ entirely. Check flash/PSRAM, strapping, console/USB and board-reserved nets; the current static assertions only check basic nonnegative/distinct pins and a classic ADC1 numeric range. They are not a schematic verifier. The reference board also has mutually exclusive supply input options. [Espressif DevKitC guide](https://docs.espressif.com/projects/esp-dev-kits/en/latest/esp32/esp32-devkitc/user_guide.html).

## 4. Electrical and power review

These are manufacturer reference requirements, not measurements of the assembled unit. The exact breakout can change the required external supply and logic arrangement.

| Part/interface | Reference requirement | Bench approval needed |
| --- | --- | --- |
| ESP32 board | 3.3 V logic domain; exact chip/board input, regulator and ADC limits must come from its identified documentation | One verified power entry method; budget radio peaks and sensor loads per rail, cable/regulator loss and transient margin. Never use GPIO as a sensor/heater supply or assume 5 V inputs are tolerated. |
| PMS5003 | Typical 5 V, allowed 4.5–5.5 V; active current up to 100 mA; UART logic at 3.3 V | Check connector polarity and adapter signal levels. Provide supply/ground independently of GPIO. Leave intake/exhaust clear. Its internal sampling fan is not the PURA AIR blower. [Plantower manual](https://cdn-shop.adafruit.com/product-files/3686/plantower-pms5003-manual_v2-3.pdf). |
| SCD40 bare sensor | 2.4–5.5 V; peak maxima 205 mA at 3.3 V or 137 mA at 5 V; typical periodic averages 15/11 mA respectively | Dimension for peaks, not averages. Verify decoupling/ripple and bare-sensor VDD/VDDH connections. Confirm breakout power path. [Sensirion electrical specifications, Table 4](https://sensirion.com/en/media/documents/E0F04247/631EF271/CD_DS_SCD40_SCD41_Datasheet_D1.pdf). |
| SCD I2C | External open-drain pull-ups, matching valid input thresholds and controller voltage; standard-mode 100 kHz | Record actual pull-up rail/resistors and any level shifter. Do not allow 5 V pull-ups onto ESP32 pins or assume that 3.3 V pull-ups meet every sensor threshold at 5 V supply. A 3.3 V sensor rail with adequate peak capacity or a properly reviewed translator avoids that assumption. Size effective resistance for bus capacitance/rise time; do not blindly add pull-ups already fitted. [Sensirion interface specifications](https://sensirion.com/en/media/documents/E0F04247/631EF271/CD_DS_SCD40_SCD41_Datasheet_D1.pdf). |
| MQ-135 | Heater/circuit reference 5.0 V ±0.1 V; heater up to 950 mW (about 190 mA at 5 V, heater only); manufacturer initial preheat over 48 hours | Review module total current and heater heat management. Analog output may exceed the MCU limit. Verify divider/buffer, worst-case AO, tolerance/transients and ADC source impedance before connecting. 11 dB attenuation is not overvoltage protection; ADC counts are not calibrated ppm. [Winsen manual](https://www.winsen-sensor.com/manual/mq135.html). |
| Signal grounds | A verified common reference is needed for these direct UART/I2C/analog links | Record continuity and intended return paths; avoid heater current through a thin signal-return jumper. Prevent signal back-powering an unpowered board/sensor. |

Do not sum current numbers across different voltage rails as if they were one supply. Create a rail-by-rail peak-current/power budget using the identified board and modules, then select a reviewed current limit and thermal limits before power-on. No resistor values, regulator suitability, power budget or input ceiling is approved by this report.

## 5. Power-off wiring and inspection procedure — future session only

1. Keep the controller, all sensors and actuator loads unpowered; disconnect USB, external supplies, batteries and other signal sources that could back-power them. Do not reset, reconnect or alter the present hardware during this preflight.
2. Photograph the unpowered assembly and mark connector orientation. Inspect for damaged parts, loose strands, reversed plugs, solder bridges, conductive debris, breadboard split rails and poor contacts. Use ESD precautions appropriate to the actual parts.
3. Produce a net list from the identified schematics. Independently verify every cable conductor; wire color and a generic Internet pinout are not proof. Keep all actuator power/control nets disconnected throughout the sensor milestone.
4. Confirm power is absent before continuity/resistance checks. Check ground continuity, unintended rail-to-rail shorts, pull-up connections, divider values and regulator/polarity paths. Never perform resistance/continuity measurements on an energized assembly.
5. With MCU signal pins still isolated, a later authorized operator can validate each supply/output using appropriately rated instruments and a current-limited source. Record actual rail/AO/logic levels and approved limits. Power off again before making the final signal connections. Do not hot-plug an unknown connector or permit a powered signal to backfeed an unpowered device.
6. Obtain a second check of the pin/power table. Only after the evidence and limits are complete should a separate sensor-only power/flash session be authorized. No upload command is supplied or run in this preflight.

## 6. Bench sequence and evidence to collect

**All stages below are NOT RUN.** Stop at the first failed gate. First collect identification/power evidence, then acquire sensors sequentially, and only afterward validate combined networking/telemetry. Do not substitute fixture values for measurements or use combustion, sprays or hazardous gas exposure to manufacture a response.

### Stage A — board and test-path readiness

Verify the actual target and disabled-default behavior with all external loads disconnected. Record approved rail voltages, idle/peak current, board temperature and reset behavior during the later session. Serial access itself may toggle DTR/RTS; choose a reviewed console connection and obtain authorization before opening it.

The existing application is **not yet a credential-free individual-sensor diagnostic harness**: `runtimeConfigured()` requires network/auth configuration before any acquisition, the shared sensor flag enables both PMS and SCD transport startup, and ordinary logs expose freshness/error counters rather than raw readings. Do not create fake credentials to get past that gate. For an offline sequential test, first use approved measurement equipment, or request a later small diagnostic profile with independent sensor enables and bounded local readings, default off, with networking/actuators disabled. That profile is a proposed next implementation, not code included here. No unverified pin is enabled now.

### Stage B — PMS5003 alone

After its power/interface approval, record actual supply/current and capture TX through a verified 3.3 V-compatible input. Confirm active output at 9600 8N1. Check 0x42/0x4d framing, 28-byte length, 32-byte packet and checksum with the existing decoder; distinguish atmospheric words from CF=1 and particle counts. Allow the current 30-second startup gate, and log actual packet times, error counts and reference-instrument comparison under ordinary ambient conditions. Valid structure/range is not calibration. Disconnect/reconnect tests are later authorized actions; confirm missing data ages out after 10 seconds and no required PM event is fabricated.

### Stage C — SCD40 alone, then alongside PMS

First verify supply and pull-up levels with MCU signals isolated, then power off before approved wiring. Limit communication to the verified interface/address and documented commands, rather than an indiscriminate bus scan. Capture startup/ready/read status, CRC results and actual CO2 ppm, temperature °C and RH %. The current driver waits for power-up, stop/start timing and periodic readiness; no forced recalibration or persistent setting change is requested. Compare against suitable references after stabilization; update cadence is not settling time or accuracy. Record enclosure/self-heating/pressure context without claiming calibration. Verify NACK/short/CRC/timeout recovery and omission of SCD fields when stale over 15 seconds. PMS remains required before combined v2 events can exist.

### Stage D — MQ-135 last

Keep ADC disconnected until heater/circuit supply, actual AO extrema and the protection/scaling network are approved. Condition the identified sensor according to its manufacturer guidance and record elapsed powered time and temperature/current. Expected heater warmth does not justify unexplained board, wire or regulator heating. A separate approved ADC-path check can compare known safe input voltages and raw counts; this is electrical validation, not gas calibration. Power off before connecting the protected AO path.

The present firmware samples only after **48 hours of controller uptime** with MQ enabled; reboot restarts that gate even if the sensor was separately conditioned. Do not bypass the gate or claim readings before it expires. If that policy prevents the intended bench session, request a separately reviewed change rather than inventing data. Confirm raw counts 0–4095 only; persistent endpoint counts need investigation for clipping, wiring or floating input. No gas concentration, VOC or gas-index claim is allowed.

## 7. Later integrated software/network validation

Proceed only after the sensor/electrical gates pass and a separate isolated network/credential setup is approved. No such setup is created in this task.

| Check | Evidence / acceptance behavior to establish |
| --- | --- |
| Isolated destination | Fixed demo/emulator project, explicit loopback database hosts in the backend, reviewed LAN-facing API/TLS endpoint and a distinct provisioned bench device. Backend normal startup loads configured credentials; do not blindly start it for a bench fixture. The current phone harness binds loopback, resets demo fixtures and installs a phone test app, so it is not an ESP32 LAN bench harness. |
| Network reachability | ESP32 localhost is the ESP32. Confirm the deliberately selected host/port is reachable from its network; no guessed production endpoint, no firewall change here. Test Wi-Fi loss/recovery in the approved bench environment; reconnect spacing is bounded and RAM storage is limited. |
| Clock | Confirm a successful SNTP callback, UTC Unix-millisecond measurement times and separate server receipt times. Missing initial sync/pre-anchor samples or over 24 hours without sync must pause telemetry. Test failures without changing the developer PC's system clock. New timestamps must satisfy the unchanged backend window: 30 days old to 5 minutes ahead. |
| Verified TLS | Use a deliberate hostname and trusted CA with correct clock. Establish a successful handshake; then use isolated wrong-host, untrusted/expired-certificate cases and confirm refusal. Never disable certificate verification or follow a redirect with the key. Source review/compilation alone is not handshake evidence. |
| Device authentication | Privately provision an active demo registry/device-specific credential using the existing trusted security model. Keep keys/passwords outside tracked files and ordinary logs. Test unauthorized behavior deliberately in that environment: firmware latches 401/403 rather than retrying continuously. Any subsequent reset/reflash to correct credentials needs separate authorization. |
| Wire event | Record the actual device/event ID, sequence, measurement time and non-secret readings in a controlled bench log. Confirm `source: hardware`, required PM2.5/PM10, correct units and omission of unavailable optional fields. No unsupported fields, fixture IDs, default zeros or uncalibrated gas indices. Sequence is monotonic within a boot; nonce changes after reboot. |
| Durable acceptance and recovery | Observe receipt creation before HTTP 202, then authenticated receipt status reaching `completed`, exact Firestore history and corresponding RTDB state. 202 is not final processing or physical execution. Test transient failures/lost responses with the original bytes/ID/time; history identity must stay unique. Four-entry RAM outbox can drop on full/exhaustion and is lost on reboot; no exactly-once/local durability claim. |
| History and live UI | On the physical phone using the same isolated project and authorized account, compare actual PM2.5/PM10/CO2/T/RH with saved values and explicit measurement/receipt times. Verify unique history ordering, missing/unavailable states and stale/offline transition after two minutes. Do not operate cloud-control buttons. The current UI does not display MQ raw or PM1; inspect those in saved backend data. Gas index should remain unavailable. |
| Authorization and indicator | Unpaired/anonymous access remains denied; ownership/membership is backend-controlled and ACL leases must be refreshed. Keep the custom particulate indicator labelled prototype; sensor readings do not establish official CPCB/EPA AQI or calibration. |

Use [telemetry v2](TELEMETRY_CONTRACT.md) for acceptance/idempotency and [the authorization contract](AUTHORIZATION_SECURITY.md) for roles, private keys and ACLs. Phase 1A's older ingestion wording is superseded by telemetry v2: 202 now means a durable receipt. Existing simulator/host exports remain explicitly synthetic evidence, even where a fixture exercises `source: hardware`.

## 8. Abort criteria and handling

Before each later powered stage, record numerical limits from the identified components and approved circuit; do not invent universal voltage/current/temperature limits from this provisional target. Abort immediately for:

- Any input/rail outside approved operating limits, unexpected polarity, backfeed, 5 V on an unprotected ESP32 signal, or an unverified AO/pull-up level.
- Supply current-limit activation, large unexplained current/ripple/rail drops, smoke/odor, or unexpected/excessive heating of a board, wire, regulator or sensor outside its approved thermal behavior. The MQ heater is intentionally warm, but that is not permission to ignore overheating.
- Incorrect/loose wiring, missing ground, uncertain connector orientation, shorts, condensation/liquid, or any actuator energizing or connected to a controller test net.
- Repeated unexplained resets/brownouts/watchdog events, USB backfeed, boot-mode changes, repeated sensor framing/CRC/NACK/timeout errors, stuck I2C, or readings that cannot be reconciled with the captured bytes/reference checks.
- Incorrect clock, TLS verification bypass/failure, wrong project/destination, exposed credential, unexpected authorization, changed payload on retry, duplicate history, stale data shown current, or missing data represented as healthy zero.

During a later authorized session, remove the approved power source safely, isolate loads and preserve the last non-secret evidence. Do not repeatedly reset, retry at full rate, raise the current limit, move powered wires, disable TLS/rules or bypass a warm-up gate to force a pass. Diagnose power/wiring first; resume only after the failed gate has been reviewed. No such physical action was performed during this preflight.

## 9. Checks actually run in this preflight

| Check | Actual result and evidence limit |
| --- | --- |
| `python firmware\scripts\test_host.py --compiler C:\MinGW\bin\g++.exe` | Exit 0; **15 host tests passed**, including packet corruption, CRC, timeouts, omissions, clock, retries and bounded FIFO. No `--emit`, so the fixture was not rewritten; no hardware access. |
| `firmware\.venv\Scripts\python.exe -m platformio run --project-dir firmware -e esp32_provisional` | Exit 0, **SUCCESS, 14.05 seconds**; incremental/up-to-date build and size check using installed pinned tools. No clean/upload/monitor target. |
| Build configuration | Process-local `PLATFORMIO_CORE_DIR=C:\dev\PuraAir\firmware\.platformio`, `PIP_CONSTRAINT=C:\dev\PuraAir\firmware\requirements-lock.txt`; no local header; build flag overrides removed for that process only. |
| Build size | 47,728 / 327,680 bytes RAM (14.6%); 936,365 / 1,310,720 bytes app flash (71.4%). This does not verify actual board flash size or pin compatibility. |
| Temporary default probe | GCC C++17 with `-Wall -Wextra -Werror`; compile/run exit 0. Assertions verified disabled/unconfigured defaults without Arduino hardware APIs. Files are ignored under `build/phase2b/`. |
| Source/output-path review | Firmware application source has no actuator-output implementation. Serial/debug and enabled sensor-interface caveats are described above. |
| Git whitespace/preservation | `git diff --check` and final entry-hash/status checks recorded below. |
| ESP32/sensors, meter readings, calibration, real Wi-Fi/TLS or ingestion | **Not run / unverified.** No fabricated values and no physical success claim. |
| Flutter/backend/Firebase/phone regression suites | Not rerun in this documentation-only preflight. Their Phase 2A results are historical evidence, not new preflight passes; no firmware/app/backend source changed. |

Evidence categories remain separate: host tests prove mocked portable behavior; an incremental target build proves the current build accepts this provisional configuration; previous simulator/phone tests prove that synthetic software path; only a future observed, logged sensor bench session can establish physical behavior. None establishes calibration by itself.

## 10. Diff review, preservation and next step

At entry: 33 modified tracked files plus 51 expanded untracked files from previous phases, nothing staged. A SHA-256 manifest of all 84 was captured before the checks. The complete preflight change relative to that entry is this one new report; earlier source, fixtures, reports, contracts and dependency locks are to remain byte-identical. Cumulative tracked changes and the expanded untracked inventory were reviewed alongside the firmware/integration source to distinguish old phase work from this report. This is a readiness/preservation review, not a new whole-platform security certification.

**Next step:** collect the evidence in section 1 and complete the actual board-specific pin/power worksheet. Then review a narrowly scoped offline diagnostic profile with independent PMS/SCD enables, no credentials/network requirement and all I/O default off, before authorizing any real sensor power/flash session. Do not select pins, create secrets or implement that profile merely from the example map. Physical testing remains on hold until those questions are answered.

Only authored file: `docs/development/PHASE_2B_PREFLIGHT.md`. Final exact Git status and preservation results follow.

### Final preservation check and exact Git status

All 84 entry files are byte-identical to their preflight hashes. The only new nonignored file is this report. Final expanded counts: **33 modified tracked files, 52 untracked files, 0 staged, 0 deleted**. `git diff --check` passed. Branch and HEAD are unchanged. The complete preflight diff was reviewed as a single document addition, with no changes to earlier work.

Verbatim `git status --short --branch` (Git aggregates existing untracked directories):

```text
## feat/pura-air-stabilization
 M README.md
 M android/app/build.gradle.kts
 M android/app/src/debug/AndroidManifest.xml
 M backend/README.md
 M backend/aqi.js
 M backend/firestore.js
 M backend/forecast.js
 M backend/package-lock.json
 M backend/package.json
 M backend/server.js
 M database.rules.json
 M firebase.json
 M firestore.rules
 M lib/data/mock_data.dart
 M lib/models/device.dart
 M lib/models/device_snapshot.dart
 M lib/repositories/firestore_device_repository.dart
 M lib/screens/auth_screen.dart
 M lib/screens/control_panel_screen.dart
 M lib/screens/device_dashboard_screen.dart
 M lib/screens/device_list_screen.dart
 M lib/screens/history_screen.dart
 M lib/screens/home_shell.dart
 M lib/screens/splash_screen.dart
 M lib/state/device_state.dart
 M lib/theme/app_theme.dart
 M lib/utils/aqi_utils.dart
 M lib/widgets/aqi_indicator.dart
 M lib/widgets/device_card.dart
 M lib/widgets/history_chart.dart
 M pubspec.lock
 M pubspec.yaml
 M test/widget_test.dart
?? android/app/src/debug/res/
?? android/app/src/emulator/
?? backend/device-security.js
?? backend/durable-telemetry.js
?? backend/scripts/
?? backend/telemetry-contract.js
?? backend/test/
?? backend/user-api.js
?? docs/
?? firmware/
?? integration_test/
?? lib/models/telemetry_reading.dart
?? lib/services/device_api_client.dart
?? test/device_api_client_test.dart
?? test/device_permissions_test.dart
?? test/home_shell_test.dart
?? test/telemetry_test.dart
```

## Phase 2C — reported ESP1 wiring reconciliation (22 October 2026)

### Reported map, not measured wiring

The user reports an ESP32-WROOM-DA controller, SCD40 on SDA21/SCL22, PMS7003 sensor TX to ESP1 RX25 and sensor RX to ESP1 TX26, MQ-135 AO to GPIO34, and a crossed ESP1/ESP2 UART at 115200 baud (ESP1 TX17 → ESP2 RX16; ESP1 RX16 ← ESP2 TX17; common GND). PMS7003 power is reported as 5 V/GND. SCD40 is reported powered through one supported supply input; **only one breakout power input may be powered at a time**, following its actual schematic. None of this establishes continuity, polarity, signal voltage, correct header labels, supply capacity or electrical safety. No hardware access is authorized in this reconciliation.

### Source mismatches and change rationale — recorded before edits

Actual source inspection found PMS on IDF UART2 at 9600 8N1, example RX16, no configurable PMS TX, and no ESP2 driver/object/protocol. SCD21/22 and MQ34 already match the reported example values, while actual defaults are -1/off. The example PMS RX16 would overlap the reported ESP2 RX16 if both were adopted. UART peripheral numbers are independent of GPIO pin numbers; no UART is silently swapped here.

**Board conflict:** the official WROOM-DA datasheet, pin-table note 2 and antenna table, assigns GPIO2/GPIO25 to the internal RF switch and states those pins are not led out as ordinary module I/O. The reported PMS RX25 therefore conflicts with that module identification. Resolve actual shield marking, carrier-board schematic and the meaning of the header label before enabling it; do not assume a generic ESP32 GPIO25 pinout applies. The datasheet also specifies 8 MB flash; `esp32dev` remains a provisional 4 MB build assumption, not a validated DA target or antenna setup. No target/antenna initialization is changed. [Espressif WROOM-DA datasheet](https://www.espressif.com/sites/default/files/documentation/esp32-wroom-da_datasheet_en.pdf).

**Protocol difference:** Plantower PMS7003 v2.5 uses 9600 8N1, 32 bytes, 0x42/0x4d, declared length 28, big-endian atmospheric PM words at offsets 10/12/14, and additive checksum at 30/31. Its word at 28/29 is reserved. The existing decoder additionally rejected any nonzero byte 29 as a PMS5003 error indicator; that is not a justified PMS7003 validation rule. Preserve the existing PMS5003 mode, explicitly select a PMS7003 mode for this acquisition adapter, and test nonzero reserved data without weakening framing/length/checksum checks. Active-mode reception needs no sensor command; passive-mode control is outside this change. [Plantower PMS7003 v2.5 manufacturer manual](https://www.espruino.com/datasheets/PMS7003.pdf).

The smallest justified source/configuration changes are: record the reported example pins with all enable flags still off; add optional PMS TX and disabled ESP2 pin definitions; preserve PMS ownership on UART2 and explicitly reserve unused UART1 for a future ESP2 driver, distinct from console UART0; centralize all PMS operations on that same UART constant; add pin-collision/DA-reserved-pin guards; select/test the PMS7003 parser variant. The example must remain blocked from enabling the reported DA/GPIO25 combination, rather than disguising that contradiction as working wiring. **ESP2 transport, message framing, acknowledgements and any physical control remain unimplemented.** No ESP2 UART is initialized and no bytes are sent to it.

### GPIO25 hardware conflict audit

**Disposition: the reported PMS7003 RX GPIO25 / TX GPIO26 map is not approved. If the fitted module is confirmed as ESP32-WROOM-DA, the reported GPIO25 connection cannot be approved. No alternative GPIO has been selected.** Identification of the actual module and matching development-board schematic/pinout must precede any replacement proposal.

Manufacturer evidence is separate from physical evidence. Espressif's datasheet v0.7, **section 3.2, Table 2 note 2 and Table 3, printed page 11 (PDF page 11, zero-based index 10)**, documents the internal GPIO2/25 RF-switch restriction cited above. Table 2 on printed page 10 lists IO26 as a module I/O; GPIO26 therefore does not have that particular GPIO25 restriction. This does not prove its availability at the actual carrier header or its electrical suitability. The module's listed N8 flash arrangement also does not validate the generic `esp32dev` target against this assembly. No antenna selection code, flash-size change or board substitution is introduced.

The user states that the photographs do not clearly establish the complete module-shield marking or the physical header reached by the PMS wire. **This is a user-reported limitation of the photographs, not an independent visual observation from this audit.** No photograph inspection, continuity measurement, pin tracing, voltage measurement or powered test was performed here. A carrier header label saying “25” cannot resolve the contradiction by itself; establish its actual net against the exact module and board revision.

Actual source/configuration occurrence audit (authored files, excluding generated build artifacts):

| Location / field | Can it activate GPIO25? | Finding and containment |
| --- | --- | --- |
| `firmware/include/local_config.example.h`, `PURA_PMS_RX=25`, `PURA_PMS_TX=26` | The example is not included automatically; it records the reported map. | Both sensor/MQ enables remain false, credentials/destination remain blank, and the DA restriction is true. Enabling sensor I/O with this map fails compilation. The user-reported RX/TX directions are preserved, not silently rewritten. |
| `firmware/include/board_config.h`, `PURA_PMS_RX` → `board::pmsRx` | A future explicit local header or build definition supplies the value consumed by the adapter. | Default RX/TX, SCD, MQ and ESP2 pins are all -1. Previously validation only checked nonnegative/different sensor pins and ADC1; it could accept GPIO25 without recognizing the DA restriction. New `usesDaRfPins()` / static assertion rejects GPIO2/25 when sensor I/O is enabled under the reported DA restriction. |
| `PURA_REPORTED_WROOM_DA` / `board::reportedWroomDa` | Controls the compile-time module restriction, not hardware detection. | Defaults **true** even if a local configuration omits it, because this is the reported module. A deliberate false override can bypass this module-specific check; incorrect identification or editing guards remains a residual risk. Such an override is not authorization, proof of another module, or an approved workaround. No private header exists or is created. |
| `firmware/src/sensor_acquisition.cpp`, `uart_set_pin(pmsUartPort, board::pmsTx, board::pmsRx, ...)` | Would route explicitly configured pins only after enabled startup. | PMS remains UART2. The current default runtime gate returns before sensor initialization. The reported DA/RX25 combination is rejected at compile time before it could reach this call. Optional TX26 has no transmit commands; if later enabled in an approved configuration, routing TX itself can drive its idle level. |
| `firmware/src/sensor_acquisition.h`, `firmware/src/main.cpp` | No independent GPIO25 literal or alternate pin routing. | One PMS UART constant is used by setup, reads, deletion and the post-stall input flush. No second serial object shares it. |
| `firmware/scripts/test_config.py` | Host-only compile probes; no Arduino or hardware APIs. | Tests include reported RX25/TX26 and negative cases. Two key failures are required: enabling the example, and enabling RX25 while omitting the model flag. Some negative collision probes explicitly suppress the DA guard to isolate another error; they must still fail. No passing enabled replacement pin map is supplied. |
| `firmware/README.md`, `firmware/platformio.ini` comments, this addendum | Documentation only. | Mark the GPIO25 conflict and provisional target. Historical Phase 2A/2B RX16 descriptions remain historical, not replacement advice. No other authored firmware GPIO25 activation path was found in the source search. |

These are configuration checks, not a comprehensive electrical pin validator. They cannot inspect a module, determine continuity, detect an adapter's level shifting or establish that an otherwise accepted GPIO is safe. The default disabled build passing is entirely consistent with the reported enabled map failing.

### Current board-specific verification worksheet

Every row remains **PROVISIONAL / PHYSICALLY UNVERIFIED**. The reported map supersedes the older candidate map in the historical Phase 2B sections above; it does not supersede their power-off, sequential-test or abort requirements.

| Interface / direction | Reported map; current example | Actual unconfigured build | Required evidence before any enable |
| --- | --- | --- | --- |
| PMS7003 TX → ESP1 RX | GPIO25, UART2, 9600 8N1 | RX -1; no sensor UART initialization | **BLOCKED if WROOM-DA.** Exact shield text, matching carrier schematic/header net, sensor identity, connector orientation and 3.3 V-compatible TX level |
| ESP1 TX → PMS7003 RX | GPIO26, same UART2 | TX -1; no commands implemented | Module/carrier/header availability, connector RX and logic compatibility; optional TX routing is not needed to send commands because none exist |
| SCD40 SDA/SCL | GPIO21/GPIO22; matches previous example | SDA/SCL -1; no Wire initialization | Actual breakout schematic, supported single supply input, pull-up rail/resistance, voltage compatibility and common ground |
| MQ-135 AO → protected ADC path → ESP1 | Reported GPIO34; matches previous example | ADC -1; MQ disabled | Module AO circuit, maximum output including startup/faults, scaling/buffer/protection, component values/tolerances and power-off continuity; ADC1 capability alone proves none of these |
| ESP1 TX17 → ESP2 RX16; ESP1 RX16 ← ESP2 TX17 | Crossed pair and common GND, reported 115200 | ESP1 RX/TX -1; UART1 unused | Both boards/modules, header nets, levels, ground/backfeed and agreed protocol; no ESP2 communication is currently implemented |
| PMS7003 power | Reported 5 V/GND | Firmware does not switch sensor power | Supply capacity/current limit, polarity, adapter pinout, common ground and measured rails during a later authorized session |
| SCD40 power | Reported one supported input | No firmware power control | Identify breakout; power **only one supported supply input at a time**. Never assume VIN and 3V3 may both be driven |
| Actuators | Must be isolated/disconnected | No actuator GPIO implementation | Physical inspection of blower/pump/mist/relay/MOSFET power and signals; do not attach these to either UART |

UART ownership is explicit: **UART0 console, UART2 PMS, UART1 reserved and uninitialized**. This preserves the existing implemented PMS peripheral rather than inferring ownership from GPIO16/17 labels. No ESP2 `HardwareSerial`, driver install, baud initialization, framing, receive loop, transmit, acknowledgement or actuator-control protocol exists. A future ESP2 implementation must use its distinct reservation and undergo a separate protocol/safety review.

### Electrical and later bench requirements retained

The manufacturer power/current requirements in section 4 and power-off inspection/abort procedures in sections 5–8 remain prerequisites. For the reported PMS7003, use its own connector drawing/manual rather than a PMS5003 cable assumption. Confirm its 5 V supply and 3.3 V serial interface against the actual adapter; shared ground, rail capacity, startup current and backfeed remain unmeasured. For SCD40, identify the actual supply path, regulator and pull-ups; do not connect 5 V pull-ups directly to unprotected ESP32 signals. For MQ-135, **never directly attach unreviewed AO to GPIO34**: its possible maximum voltage and protection/scaling circuit must first be established. ADC attenuation and the ADC1 guard do not protect against overvoltage. Heater/circuit supply and board regulator current/thermal capacity remain unresolved.

The historical PMS-alone stage now refers to **PMS7003 active-mode reception**. Appendix I of the Plantower v2.5 manual (PDF pages 13–14) supports the packet rules in the rationale above. The new tests use synthetic packets; a future bench session must capture actual bytes and compare atmospheric PM words with independent observations/reference equipment. This parser compatibility change is not calibration or proof that the installed sensor is a PMS7003. SCD40 and MQ stages remain sequential, with MQ last and its existing 48-hour uptime gate intact. The current runtime still requires network/auth configuration before acquisition and enables PMS/SCD together; it is not an offline individual-sensor diagnostic harness. Do not invent credentials or bypass that gate for bench readiness.

Later Wi-Fi, clock, verified TLS, authenticated ingestion, durable receipt/history and physical-phone dashboard checks must follow section 7 against an explicitly isolated setup. Those checks were not performed here. The telemetry v2 contract, security model, backend/mobile source, fixture values and actuator scope are unchanged. Any overvoltage, wiring uncertainty, unexplained heating/current, sensor errors or resets keeps the assembly on hold under section 8.

### Phase 2C checks actually executed

Final checks after the source changes:

| Command / review | Actual outcome | Evidence boundary |
| --- | --- | --- |
| `python firmware/scripts/test_host.py --compiler C:\MinGW\bin\g++.exe` | Exit 0; `HOST_TESTS_PASS count=17`, `CONFIG_TESTS_PASS count=11` | Portable C++17 tests compiled with `-Wall -Wextra -Werror`; includes existing 15 cases, two PMS7003 cases and 11 compile-only guard probes. Expected compiler rejections count as guard passes, not usable enabled firmware. No `--emit`; fixture untouched. |
| `firmware\.venv\Scripts\python.exe -m platformio run --project-dir firmware -e esp32_provisional` | Exit 0; **SUCCESS, 25.28 seconds** | Installed pinned tooling, default disabled build; no upload/monitor/clean target. RAM **47,728 / 327,680 bytes (14.6%)**; app flash **936,289 / 1,310,720 bytes (71.4%)**. No physical DA target, antenna, pins or flash size validated. |
| Build environment | `PLATFORMIO_CORE_DIR=C:\dev\PuraAir\firmware\.platformio`; `PIP_CONSTRAINT=C:\dev\PuraAir\firmware\requirements-lock.txt`; process build flag/unflag overrides removed; local header absent | Process-local settings only; no dependency/target upgrades. |
| Source startup / output review | Default sensor/MQ flags false, actual pins -1, credentials/endpoint empty; `runtimeConfigured()` prevents Wi-Fi, SNTP, sensor initialization and HTTP loop | `Serial.begin(115200)` is still the debug-console exception before the gate; no claim that every MCU pin is electrically inert. Enabled SCD I2C/TX would be sensor interfaces, not actuator control. No actuator GPIO/PWM/DAC implementation found. |
| `git diff --check` | Exit 0 | Tracked cumulative changes pass whitespace checks; authored untracked file whitespace reviewed separately. |
| Physical sensor/voltage/continuity/thermal/calibration/network checks | **NOT RUN** | No flash, reset, monitor, serial/GPIO/I2C/ADC access or hardware test. No production/Firebase contact, credentials, local header or firewall changes. |

An earlier iteration also passed 17 portable tests, 11 configuration probes and an incremental build (39.02 seconds, same final size); the final probe set tightens omitted-model rejection and contains no passing enabled replacement-map test. These iterations are software evidence only. No hardware success or measured sensor values are inferred.

### Phase 2C exact change scope, preservation and next step

Twelve existing files were intentionally extended, plus one new host-test script (13 files total):

```text
docs/development/PHASE_2B_PREFLIGHT.md
firmware/README.md
firmware/include/board_config.h
firmware/include/local_config.example.h
firmware/lib/PuraCore/src/pura_core.cpp
firmware/lib/PuraCore/src/pura_core.h
firmware/platformio.ini
firmware/scripts/test_host.py
firmware/scripts/test_config.py                 (new)
firmware/src/main.cpp
firmware/src/sensor_acquisition.cpp
firmware/src/sensor_acquisition.h
firmware/test/host_tests.cpp
```

Entry was **93 existing changed/untracked files: 33 tracked modifications and 60 expanded untracked files**, including the existing Phase 2B report and unrelated `output/` assets. A SHA-256 manifest was captured before edits under ignored `build/phase2c/`. Complete source/configuration/test changes were reviewed against the entry findings and cumulative Git inventory. All 33 prior tracked modifications and all 48 entry files outside the intentional 12-file extension list remain byte-identical (**81 unrelated entry files preserved**), including historical Phase 2A results, both contracts, fixtures, dependency locks and output assets. The only new nonignored path is `firmware/scripts/test_config.py`. Final expanded count is **33 modified tracked files, 61 untracked files, 0 staged, 0 deleted**. Firmware/report paths were already untracked from earlier milestones, so ordinary `git diff` alone does not display this task's changes.

Branch remains `feat/pura-air-stabilization`; HEAD remains `e5ec5da2ed325be411ea3c2bbf9129f9d75e36c4`. No commit, push, merge or deployment occurred.

**Next step:** establish the full fitted shield marking and development-board maker/revision, obtain the matching schematic/pinout, and trace the reported PMS TX wire to its real header/net with all power removed during a separately authorized inspection. Resolve the DA/GPIO25 contradiction before selecting any alternate GPIO or enabling a local map. Also identify the exact sensor/breakout revisions, SCD supply/pull-ups, MQ AO maximum/protection and supply/current budget. Only then review a separate offline sensor diagnostic profile and an eventual authorized bench/flash plan. Neither is authorized or implemented by this reconciliation.

Final preservation/whitespace checks returned:

```text
PRESERVATION_PASS entry=93 intentional_existing_changes=12 unchanged=81 new=1
STATUS_COUNTS tracked_modified=33 untracked_expanded=61 staged=0 deleted=0
AUTHORED_WHITESPACE_PASS files=13
DIFF_CHECK_PASS exit=0
```

Verbatim final `git status --short --branch` (directory aggregation is Git's own output):

```text
## feat/pura-air-stabilization
 M README.md
 M android/app/build.gradle.kts
 M android/app/src/debug/AndroidManifest.xml
 M backend/README.md
 M backend/aqi.js
 M backend/firestore.js
 M backend/forecast.js
 M backend/package-lock.json
 M backend/package.json
 M backend/server.js
 M database.rules.json
 M firebase.json
 M firestore.rules
 M lib/data/mock_data.dart
 M lib/models/device.dart
 M lib/models/device_snapshot.dart
 M lib/repositories/firestore_device_repository.dart
 M lib/screens/auth_screen.dart
 M lib/screens/control_panel_screen.dart
 M lib/screens/device_dashboard_screen.dart
 M lib/screens/device_list_screen.dart
 M lib/screens/history_screen.dart
 M lib/screens/home_shell.dart
 M lib/screens/splash_screen.dart
 M lib/state/device_state.dart
 M lib/theme/app_theme.dart
 M lib/utils/aqi_utils.dart
 M lib/widgets/aqi_indicator.dart
 M lib/widgets/device_card.dart
 M lib/widgets/history_chart.dart
 M pubspec.lock
 M pubspec.yaml
 M test/widget_test.dart
?? android/app/src/debug/res/
?? android/app/src/emulator/
?? backend/device-security.js
?? backend/durable-telemetry.js
?? backend/scripts/
?? backend/telemetry-contract.js
?? backend/test/
?? backend/user-api.js
?? docs/
?? firmware/
?? integration_test/
?? lib/models/telemetry_reading.dart
?? lib/services/device_api_client.dart
?? output/
?? test/device_api_client_test.dart
?? test/device_permissions_test.dart
?? test/home_shell_test.dart
?? test/telemetry_test.dart
```

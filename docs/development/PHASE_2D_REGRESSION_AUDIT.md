# Phase 2D — regression audit and checkpoint readiness

22 October 2026, Asia/Calcutta. Repository: `C:\dev\PuraAir`.
Branch: `feat/pura-air-stabilization`.
HEAD: `e5ec5da2ed325be411ea3c2bbf9129f9d75e36c4` (matches the expected checkpoint base).

## Decision

**The requested software regression suites pass. The accumulated software is ready for a reviewed, explicitly selected source checkpoint with the known dependency advisories recorded.** This is not security-release, production-deployment or hardware approval. Do not stage everything: eight unrelated presentation assets must be excluded, ignored credentials/build products must remain excluded, and the dependency and documentation caveats below need reviewer acknowledgement. Nothing was staged or committed.

Only this report is added by Phase 2D. No product, test, dependency, rule, telemetry-contract or hardware-configuration correction was necessary. The tests temporarily regenerated one existing fixture; its new evidence was retained in ignored audit storage and the original was restored byte-for-byte.

## Repository and inventory evidence

Initial `git status --short --branch` was captured before tests in ignored `build/phase2d/initial-status.txt`. There were **33 modified tracked files, 61 expanded untracked files, zero staged files and zero deletions**. The complete tracked patch was captured in `build/phase2d/tracked-diff.txt`; all 33 tracked changes and all 61 untracked paths were inventoried. Source/configuration changes were reviewed alongside the actual security, delivery, dashboard and firmware implementations and regression cases. The dependency lock diff was parsed structurally across all 82 changed package records, including metadata-only changes, rather than treating added test-SDK transitive packages as new application features.

A SHA-256 manifest covered **all 146 nonignored existing project files**, including unchanged tracked files and unrelated output assets, before running suites. A read-only content scan covered 129 text files; 14 PNGs and three PPTX files were classified separately. Presentation ZIP structure confirmed unrelated 6/7/7-slide decks. This inventory is not a claim to have performed a visual slide review or an exhaustive secret search of binary media.

Ignored directories were inventoried separately: Flutter/Dart/Gradle/IDE caches, backend dependencies, firmware virtual environment/toolchain/build outputs, legacy IDE modernization workspace files, generated Android plugin registration and emulator logs. These are not milestone source. No cleanup, reset, checkout, deletion or ignore-rule change was performed.

## Exact regression commands and outcomes

All commands below used existing documented scripts and installed dependencies. No `npm install`, `npm ci`, `pub upgrade`, `npm audit fix` or tool upgrade was run in this audit. Native test tools ran with the filesystem/process permissions needed by their installed runtimes; no permission failure was counted as a test pass.

| Working directory | Executed command | Actual result |
| --- | --- | --- |
| `backend/` | `npm run check` | Exit **0**; all **10** listed JavaScript syntax checks passed. |
| `backend/` | `npm test` | Exit **0**; **30 passed, 0 failed/cancelled/skipped**. Runs `node --test test/security.test.js test/telemetry.test.js`; transactional doubles and actual handler logic. |
| `backend/` | `npm run test:emulators` | Exit **0**; **17 passed, 0 failed/cancelled/skipped**; test duration 46,907.8013 ms. Twelve security cases, four telemetry integration cases and one firmware-serializer integration case. Wrapper completion receipt was required; emulators shut down normally. |
| Repository root | `flutter analyze` | Exit **0**; **No issues found**, analyzer reported **110.5 s**. |
| Repository root | `flutter test` | Exit **0**; **23 passed**, `All tests passed!`; unit/widget scope under `test/`. |
| Repository root | `python firmware/scripts/test_host.py --compiler C:\MinGW\bin\g++.exe` | Exit **0**; `HOST_TESTS_PASS count=17`, `CONFIG_TESTS_PASS count=11`. The existing runner invokes `test_config.py --compiler C:\MinGW\bin\g++.exe` automatically. Two disabled configurations compile; nine deliberately invalid configurations must be rejected. No `--emit`, so the firmware NDJSON fixture was not regenerated. |
| Repository root | `firmware\.venv\Scripts\python.exe -m platformio run --project-dir firmware -e esp32_provisional` | Exit **0**, **SUCCESS, 14.27 s**; incremental default-disabled build/size check, existing pinned `esp32dev` target. **RAM 47,728 / 327,680 bytes (14.6%); app flash 936,289 / 1,310,720 bytes (71.4%)**. |
| Repository root | `git diff --check` | Exit **0**; cumulative tracked whitespace check passed. Newly authored report whitespace checked separately because Git does not include untracked files in this command. |

Firebase execution used the existing Windows Java workaround from `AUTHORIZATION_SECURITY.md`:

```powershell
# Verified absent; this directory was not created.
Test-Path 'C:\dev\PuraAir\.java-unix-sockets-disabled'
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:\dev\PuraAir\.java-unix-sockets-disabled'
npm run test:emulators
```

These settings applied only to the test process. Inherited `FIREBASE_SERVICE_ACCOUNT_PATH` and `FIREBASE_DATABASE_URL` existed; their **names only** were inspected. They and any Google credential/project overrides, prior emulator-host overrides, `PURA_PHYSICAL_DEVICE` and `PURA_ISOLATED_TEST` were removed in that process before the wrapper ran. The wrapper supplied the fixed **`demo-pura-security`** project and local host settings. No service-account file or normal `node server.js` startup was used. Auth/Firestore/RTDB used loopback ports 19099/18080/19000; hub/logging used 14400/14500. No Firebase production data or rules were contacted or deployed.

The firmware process used `PLATFORMIO_CORE_DIR=C:\dev\PuraAir\firmware\.platformio` and `PIP_CONSTRAINT=C:\dev\PuraAir\firmware\requirements-lock.txt`; inherited build flag/unflag overrides were removed. The private local header was confirmed absent. No clean/upload/monitor target was run. An incremental success proves compatibility with this provisional build configuration, not the physical controller.

Detailed test logs are ignored local evidence under `build/phase2d/`: `backend-check.log`, `backend-tests.log`, `firebase-emulators.log`, `flutter-analyze.log`, `flutter-tests.log`, `firmware-host.log`, `firmware-build.log`. They are not recommended staging inputs.

## Failures, advisories and reviewed behavior

**No requested regression suite failed; no corrective source change was made.** Firebase `PERMISSION_DENIED` warnings came from deliberate negative authorization assertions that passed. Java emulator shutdown SIGINT notices were normal wrapper cleanup. Slow CLI/analyzer startup completed successfully and was not represented as a failed test or used as a reason to change dependencies.

Additional read-only dependency inspection: from `backend/`, **`npm audit --json` exited 1** with **18 affected package entries: 9 high, 8 moderate, 1 low, 0 critical**. This nonzero result is a real advisory finding, not a clean security audit or regression-test failure. The direct cause is the existing installed/locked dependency graph, including Admin SDK transitives and the Firebase test SDK graph; its totals match the recorded Phase 1A/1B findings. No fix or downgrade was applied. Raw JSON and advisory titles/ranges are saved under ignored `build/phase2d/dependency-audit.json` and `advisory-details.json`.

High-rated affected entries: `@fastify/busboy`, `@firebase/firestore`, `@firebase/firestore-compat`, `@firebase/rules-unit-testing`, `@grpc/grpc-js`, `fast-xml-parser`, `firebase`, `form-data`, `node-forge`. Moderate entries: `@google-cloud/firestore`, `@google-cloud/storage`, `firebase-admin`, `gaxios`, `google-gax`, `retry-request`, `teeny-request`, `uuid`. Low: `@tootallnate/once`. These are affected package entries, not 18 distinct vulnerabilities or evidence that every advisory is reachable. Existing reachability/remediation limits in `PHASE_1A_RESULTS.md` remain; passing tests does not clear them. A reviewed checkpoint can record them, but a production release requires separate dependency triage and operational/security approval.

Dependency inventory matches intended milestones: `firebase-admin` remains **13.6.1** within the unchanged production manifest range; exact dev-only `@firebase/rules-unit-testing` **6.0.0** and Firebase JS SDK **13.1.0** were added in Phase 1A, alongside compatible `protobufjs` **7.5.4 → 7.6.6**, `websocket-driver` **0.7.4 → 0.7.5** and related helper updates. Flutter adds the SDK `integration_test` development dependency and its locked transitives in Phase 1B. Firmware toolchain/Python pins belong to Phase 2A. No unexplained new direct product dependency was found, and all manifests/locks remain identical to audit entry.

| Area | Confirmed source/test findings and limits |
| --- | --- |
| Authorization | Token verification includes revocation checking and rejects anonymous management. Canonical owner/shared membership and versioned, expiring RTDB ACLs are used; client registry/credential/pairing/membership writes are denied. Unit/emulator cases cover injection, owner/share separation, expiry, races, guessing, replay, revocation and delayed ACL publication. These tests do not certify deployed rules or production identity-provider configuration. |
| Durable telemetry | 202 follows durable receipt acceptance; identical retries share identity, conflicts return 409, deterministic history IDs prevent duplicate records, and partial failure/restart cases recover. Tests cover saturation, terminal replay and late-arrival/multiworker fencing. Firestore and RTDB still do not provide a cross-database atomic transaction; retention and production capacity review remain outstanding. |
| Dashboard/history | Optional missing readings remain unavailable, sensor zero is not invented, stale/offline and error states are explicit, fixture source stays labelled simulator, and chart coordinates use measured times. The HomeShell typed-listener regression passes. Unit/widgets and local emulator integration passed; no fresh physical-phone integration/APK/release-packaging result is claimed. |
| Firmware safety | All actual pins remain -1 and sensor/MQ flags false without a private header; empty credentials/destination make `runtimeConfigured()` return before Wi-Fi/SNTP/sensor startup/HTTP loop. GPIO25/WROOM-DA and pin collision guards still reject invalid enabled maps. PMS7003 uses UART2 and its documented packet mode; UART1 remains reserved/uninitialized, ESP2 unimplemented. No actuator GPIO/PWM/DAC implementation exists. Debug `Serial.begin(115200)` remains before the gate, so default firmware is not a claim that every MCU pin is electrically inert. |

Evidence categories remain separate: host mocks establish portable behavior; a provisional build establishes compilation/size; local Firebase emulators establish isolated software persistence/rules behavior; Flutter tests establish mocked UI behavior. Synthetic data labelled `source: hardware` in the serializer fixture is still synthetic. **No physical sensor, voltage, continuity, calibration, Wi-Fi radio, real ESP32 TLS, ingestion or dashboard end-to-end hardware evidence was obtained.** No phone/Android emulator/ESP32 was accessed in this audit.

## Sensitive, generated and unrelated files

| Inventory item | Classification and staging recommendation |
| --- | --- |
| `backend/serviceAccountKey.json` | Exists and is ignored/untracked from Git's perspective; treated as a potential private credential. Contents were not read, copied, printed or tested. **Never stage/force-add it.** |
| `firmware/include/local_config.h` | Absent and ignored; was not created. Keep absent for this checkpoint and do not add credentials. |
| `android/app/google-services.json` | Pre-existing tracked, unchanged Firebase Android client configuration. The redacted scan located an API-key-shaped client value; this is not a service-account private key. Confirm intended repository/project scope and API restrictions with the owner before wider publication; no project identifiers or key values are reproduced here, and no remote validation was attempted. |
| `android/app/src/emulator/google-services.json` | Required new demo-only client configuration, fixed project `demo-pura-security`, explicitly fake local API key. Keep with the isolated test harness and Gradle/runtime project guards. |
| Test accounts/keys in security/physical-phone test source | Explicit non-production fixtures, not harvested real accounts/tokens; guarded by demo/emulator startup. The scan's literal-sensitive-field matches were inspected and accounted for. Keep fixture definitions with their tests. Do not reuse them outside the demo setup. |
| `docs/development/artifacts/telemetry-fixture.json`, `physical-telemetry-fixture.json` | Generated **synthetic** evidence deliberately retained by prior milestones; the former is consumed by Flutter regression tests and both are referenced by reports. They are curated fixtures, not general logs. No credential/token field was found. Preserve the historical copies and labels. |
| `firmware/test/fixtures/telemetry.ndjson` | Required fixed synthetic serializer fixture used by backend integration. Keep with its generator/tests; it contains no measured sensor evidence. |
| `output/divya-presentation/` | **Eight unrelated files, 51,540,449 bytes**: three Kerala presentation decks, four PNGs and an animation helper. They are unrelated to PURA AIR and must be excluded. No move/delete or script execution was performed; all eight hashes are preserved. |
| `build/`, firmware `.pio/`, `.platformio/`, `.venv/`, backend `node_modules/`, Flutter/Dart/Gradle caches | Generated tools/binaries/test evidence; ignored. Do not force-add. Firmware ELF/bin and app APK products are not source checkpoint inputs. |
| Root `firestore-debug.log`, `database-debug.log`, IDE files, local Android SDK properties, generated plugin code, legacy `.github/modernize/` workspace | Ignored local/generated material; exclude, preserve in place. Do not confuse ignored generated workspace files with a new project CI configuration. |

The nonignored candidate source inventory contains no ELF/bin/APK/executable/JAR/private-key file added among project sources. A redacted pattern scan found no private-key marker, JWT-shaped bearer token or provider token in the 129 text files. This is bounded scan/source-review evidence, not a guarantee that arbitrary text or binary data can never contain a secret. Ignored credential contents were deliberately not scanned.

### Items to review before selecting a checkpoint

- Exclude the entire eight-file unrelated presentation set using the exact inventory below; do not stage a repository root or directory indiscriminately.
- Keep ignored credentials and generated directories excluded. The existing normal Android client configuration is unchanged, but its publication/project policy needs owner review before sharing beyond the current repository scope.
- Acknowledge the 18 remaining dependency advisories. Dependency remediation belongs in a separate tested change, not an automatic audit fix in this checkpoint.
- Documentation has historical wording: the root README retains pre-migration claims below its warning; the authorization document mentions seven syntax checks and old queued-202 semantics, superseded by the actual ten checks and telemetry v2 durable-acceptance contract; the firmware README calls its currently untracked fixed fixture “committed.” Earlier Phase 2A/2B candidate RX16/model descriptions are historical and explicitly superseded by the Phase 2C addendum. These are documentation follow-ups, not evidence that GPIO16 or another replacement should be enabled. Do not use old instructions for live setup. No documentation was silently rewritten during this audit.

## Unresolved hardware gates

The reported WROOM-DA module identification and PMS TX → ESP1 RX25 header/net remain physically unconfirmed. Genuine WROOM-DA reserves GPIO25 internally; the reported enabled map is blocked. Do not select another pin or change the generic target on the strength of these tests. Confirm the module-shield marking, carrier maker/revision/schematic, actual sensor models/connectors, GPIO availability, power/current limits, grounding and 3.3 V signal/pull-up compatibility during a separately authorized inspection.

MQ-135 AO must not connect directly to GPIO34 without verifying the module's possible output range and protection/scaling circuit. ADC1 capability/attenuation are not protection. SCD40 must use only one supported breakout supply input at a time. ESP2 UART communication and actuator connections/control remain outside the implementation and this checkpoint. No flash, reset, serial monitor, GPIO/UART/I2C/ADC access, rewiring, hardware power test, firewall change or deployment occurred. Physical validation and production rollout remain blocked by these gates and the earlier security/operations requirements.

## Preservation and final status

The emulator test regenerated `docs/development/artifacts/telemetry-fixture.json` with current synthetic run timestamps. Before execution, both prior JSON artifacts were backed up in ignored audit storage. After recording the new generated copy as `build/phase2d/telemetry-fixture.this-run.json`, the original telemetry fixture was restored. The physical-phone fixture was untouched. **All 146 entry-manifest files are byte-identical after the audit**, including all unrelated output, dependency locks, rules, firmware configuration and previous reports.

Only new nonignored file: **`docs/development/PHASE_2D_REGRESSION_AUDIT.md`**. Ignored test/tool logs, caches and ignored audit helpers/evidence were generated/refreshed. Final expanded inventory: **33 modified tracked files, 62 untracked files, zero staged, zero deleted**; branch/HEAD unchanged. The short directory-aggregated Git output is identical to entry because the new report is inside the already-untracked `docs/` directory. No commit, push, merge, deployment or history alteration occurred.

## Exact staging recommendation

Recommendation only; **no staging commands were run**. The inventory below assigns every one of the 94 accumulated changed/untracked entry paths, plus this report, exactly once. Excluding eight unrelated output files leaves **87 intended source/test/doc paths** (33 tracked modifications and 54 untracked files), subject to the reviews above. Shared files contain contributions from several milestones; grouping is a review aid, not a claim that each group is independently buildable. Preserve all cross-file dependencies and review the selected index later before any checkpoint commit. Do not automatically add every file under `docs/`, `firmware/` or `output/`.

The complete grouped path inventory and verbatim Git status follow.

### Phase 0 baseline report (1)

```text
docs/development/BASELINE_AUDIT.md
```

### Phase 1A authorization, rules and app safeguards (18)

```text
README.md
backend/device-security.js
backend/test/emulator.test.js
backend/test/security.test.js
backend/user-api.js
database.rules.json
docs/development/AUTHORIZATION_SECURITY.md
docs/development/PHASE_1A_RESULTS.md
firestore.rules
lib/models/device.dart
lib/screens/auth_screen.dart
lib/screens/control_panel_screen.dart
lib/screens/device_list_screen.dart
lib/screens/splash_screen.dart
lib/services/device_api_client.dart
test/device_api_client_test.dart
test/device_permissions_test.dart
test/widget_test.dart
```

### Shared Phase 1A/1B/2A integration and dependency locks (9)

```text
backend/README.md
backend/package-lock.json
backend/package.json
backend/scripts/run-emulators.js
backend/scripts/test-emulators.js
backend/server.js
backend/test/helpers.js
firebase.json
lib/repositories/firestore_device_repository.dart
```

### Phase 2A/2B/2C firmware, guarded wiring and host coverage (25)

```text
backend/test/firmware-emulator.test.js
docs/development/PHASE_2A_RESULTS.md
docs/development/PHASE_2B_PREFLIGHT.md
firmware/.gitignore
firmware/README.md
firmware/include/board_config.h
firmware/include/local_config.example.h
firmware/lib/PuraCore/src/pura_core.cpp
firmware/lib/PuraCore/src/pura_core.h
firmware/platformio.ini
firmware/requirements-lock.txt
firmware/requirements.txt
firmware/scripts/test_config.py
firmware/scripts/test_host.py
firmware/src/connectivity.cpp
firmware/src/connectivity.h
firmware/src/http_transport.cpp
firmware/src/http_transport.h
firmware/src/main.cpp
firmware/src/sensor_acquisition.cpp
firmware/src/sensor_acquisition.h
firmware/test/fixtures/telemetry.ndjson
firmware/test/host_tests.cpp
lib/screens/home_shell.dart
test/home_shell_test.dart
```

### EXCLUDE unrelated presentation files (8)

```text
output/divya-presentation/Glowing_Waters_of_Kerala_Divya_Shukla.pptx
output/divya-presentation/Glowing_Waters_of_Kerala_Divya_Shukla_Animated.pptx
output/divya-presentation/add_animations.py
output/divya-presentation/kerala-backwaters.png
output/divya-presentation/plankton.png
output/divya-presentation/revised-draft.pptx
output/divya-presentation/village-day.png
output/divya-presentation/village-food.png
```

### Phase 2D audit report (1)

```text
docs/development/PHASE_2D_REGRESSION_AUDIT.md
```

### Phase 1B durable telemetry, simulator, dashboard and evidence (33)

```text
android/app/build.gradle.kts
android/app/src/debug/AndroidManifest.xml
android/app/src/debug/res/xml/pura_debug_network_security.xml
android/app/src/emulator/google-services.json
backend/aqi.js
backend/durable-telemetry.js
backend/firestore.js
backend/forecast.js
backend/scripts/physical-vertical-slice.js
backend/scripts/simulator.js
backend/telemetry-contract.js
backend/test/telemetry-emulator.test.js
backend/test/telemetry.test.js
docs/development/AQI_SEMANTICS.md
docs/development/PHASE_1B_RESULTS.md
docs/development/TELEMETRY_CONTRACT.md
docs/development/artifacts/physical-telemetry-fixture.json
docs/development/artifacts/telemetry-fixture.json
integration_test/telemetry_e2e_test.dart
lib/data/mock_data.dart
lib/models/device_snapshot.dart
lib/models/telemetry_reading.dart
lib/screens/device_dashboard_screen.dart
lib/screens/history_screen.dart
lib/state/device_state.dart
lib/theme/app_theme.dart
lib/utils/aqi_utils.dart
lib/widgets/aqi_indicator.dart
lib/widgets/device_card.dart
lib/widgets/history_chart.dart
pubspec.lock
pubspec.yaml
test/telemetry_test.dart
```

## Verbatim final Git status

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

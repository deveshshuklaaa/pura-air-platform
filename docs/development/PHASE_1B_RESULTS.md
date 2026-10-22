# Phase 1B results — reliable telemetry and physical-phone vertical slice

Validated locally on 21 October 2026. The software milestone passes. The simulator submitted authenticated events to the local backend; durable Firestore receipts preceded acceptance; processing saved the exact raw measurements to Firestore and RTDB; the real Flutter repository displayed them on the user's physical Samsung SM-S928B (Android 16, API 36, ARM64). No Android emulator was used. Firebase emulators are the isolated database/auth services, not an emulated phone.

## Preservation and environment

- Repository: `C:\dev\PuraAir`; branch remains `feat/pura-air-stabilization`; HEAD remains `e5ec5da2ed325be411ea3c2bbf9129f9d75e36c4`.
- The intentionally unstaged Phase 1A working tree was the starting baseline. Its tests, authorization rules, credential isolation, user APIs and security documentation remain. No reset, clean, stash, commit, push, merge, deployment or production migration was performed.
- The original three reports retain their entry SHA-256 hashes: `BASELINE_AUDIT.md` `B6B2B7EF28C72F7F16293FEF428413150A2D308621427CA0DE7DDF6A8828908B`; `AUTHORIZATION_SECURITY.md` `48F9B16A3071041A30AA5F68088A9E092C29BB5E7F25D5737FA4E8841D0C951C`; `PHASE_1A_RESULTS.md` `B7ACEC91B642CAADC76EE9BA01BF16D99D5C53F4B5C73108DE85135165FE6444`.
- Node 24.13.0, npm 11.6.2, Firebase CLI 15.6.0, Flutter 3.38.9 / Dart 3.10.8, Android Studio JBR 21. Temporary process environment used the existing Java socket workaround, with a deliberately nonexistent `C:\dev\PuraAir\.java-unix-sockets-disabled` path. No persistent machine configuration changed.
- No npm dependency/version changes were added in Phase 1B. The npm lockfile change visible against HEAD belongs to Phase 1A. `npm ci` still reports 18 dependency advisories (9 high, 8 moderate, 1 low; no critical), not resolved in this milestone.
- Added only Flutter SDK `integration_test` as a development dependency so the actual native Firebase plugins and screens could run on the physical phone. Its SDK/transitive lock additions are `flutter_driver`, `fuchsia_remote_debug_protocol`, `process` 5.0.6, `sync_http` 0.3.1 and `webdriver` 3.2.0. Existing package versions were not upgraded.

## Implemented behavior

The [telemetry contract](TELEMETRY_CONTRACT.md) and [indicator decision](AQI_SEMANTICS.md) were written before changing ingestion/calculations. Telemetry v2 requires a producer event ID, matching device ID, Unix-millisecond measurement time and valid PM2.5/PM10. Optional values remain absent. Wrong types, unsupported fields, non-finite/out-of-range numbers and oversized requests fail before durable acceptance.

A Firestore transaction writes the identity, raw receipt and queue position before HTTP 202. Identical retries reuse the current receipt; changed payloads with the same identity conflict. A globally serial, fenced worker lease processes durable FIFO receipts with bounded exponential backoff. Shutdown refuses new acceptance and leaves interrupted work recoverable. Stable history identity makes partial history/RTDB/completion failures retryable without duplicate history. Late records remain in history while timestamp/order fencing prevents live-state regression. A trusted module method can explicitly replay a terminal failure; HTTP resubmission cannot silently reset its retry budget. Metrics expose counts and safe error codes, not credentials or sensor bodies.

The custom `pura-particulate-v1` indicator is explicitly a prototype, not official CPCB or current EPA AQI. Fractional gaps are removed by documented calculation-only truncation; raw PM readings remain intact. Forecasts use unique persisted samples and distinct measurement times; their horizons are labelled 10/30 minutes. The fixture's steep short trend saturates the forecast at 500; that is a clipped regression output, not a measurement or demonstrated prediction accuracy.

Flutter now maps nullable measurements, timestamps and named indicator versions strictly, reads actual recent history, and ages live status even if no new stream event arrives. Missing/error/loading/stale states are visible. The dashboard's fabricated trend path is removed. History uses measurement times and raw PM2.5/PM10 plus the named indicator. Synthetic demo/simulator data carries an explicit test-data label. The current design and Phase 1A owner/shared controls remain.

## Actual verification

| Check | Result |
| --- | --- |
| `flutter pub get` | Exit 0; SDK test dependency added for the reason above |
| `flutter analyze` | Exit 0, no issues; rerun after final theme/test changes |
| `flutter test` | Exit 0, 22 passed: original Phase 1A 14 plus 8 new telemetry cases |
| `npm ci` | Exit 0; same advisories described above |
| `npm run check` | Exit 0; backend source syntax checks |
| `npm test` | Exit 0, 30 passed: original Phase 1A 15 plus 15 telemetry/recovery cases |
| `npm run test:emulators` | Exit 0, 16 passed: original Phase 1A 12 plus 4 real telemetry integration cases |
| `npm run test:physical` with explicit phone ID | Exit 0; reran all 16 Firebase integration cases, then 1 native Flutter integration test on the physical SM-S928B |
| Android debug build/install | Passed in the physical suite; `assembleDebug`, APK build and installation succeeded |
| Simulator dry-run | Exit 0; labelled deterministic payloads, no network request |
| `git diff --check` | Passed; no whitespace errors |
| USB reverse cleanup | Verified empty after the successful phone run |

New backend coverage includes strict validation, units and missing values; known/fractional indicator boundaries; durable acceptance and conflicts; acceptance-write failure; faults before/after history and RTDB plus completion; restart/lease recovery; saturation; retry exhaustion; explicit terminal replay; FIFO; shutdown; late events; unique-history forecasting; and simulator retry identity/destination guards. The five persistence-stage fault cases account for five of the 15 new tests.

Real Firebase tests exercise authenticated HTTP and durable receipts, exact persisted fields/times, duplicate history prevention, recovery after partial success/restart, unauthorized reads/writes, private receipts, malformed/oversized requests, queue capacity, competing workers and late-arrival fencing. Phase 1A's unchanged rules cases still cover anonymous/stranger denial, membership/ACL fabrication, owner/shared permissions, pairing expiry/concurrency/replay/guessing, revocation and credential privacy.

Flutter cases cover the actual exported Firebase schema, exact measurements, malformed/missing values, legacy undocumented indicators, stale/offline state, loading/error/empty history, forecast horizons and timestamp-based measured charts. The phone test uses real Firebase client plugins and the normal application/provider/screens, rather than provider fixtures.

### Physical-phone evidence

The final successful run printed:

```text
PURA_PHYSICAL_E2E_PASS pm25=19.6 pm10=45 co2=460 history=3 source=simulator
00:04 +1: All tests passed!
physical_suite_exit=0
```

Actual exported saved fixture: [physical-telemetry-fixture.json](artifacts/physical-telemetry-fixture.json). Event IDs are `phone-1792605704190-000001`, `phone-1792605704190-000002`, `phone-1792605704190-000003`. The saved PM2.5 history is `[14.6, 17.1, 19.6]` µg/m³ and PM10 history is `[35, 40, 45]` µg/m³. Final state has CO2 460 ppm, indicator 67, `source: simulator`, measurement timestamp `1792605704190` and distinct server receipt time `1792605704755`. The test asserted the dashboard's exact text/units, test label, real repository state and three unique chart/history readings. [telemetry-fixture.json](artifacts/telemetry-fixture.json) is a separate actual export consumed by Flutter regression tests. These files contain synthetic measurements and no real account credentials or tokens.

Isolation: hardcoded demo project `demo-pura-security`, exact loopback host guards, no production service-account loader, demo-only native Android configuration, and a runtime native-project guard before sign-in or fixture requests. USB reverse links the phone to Auth 19099, Firestore 18080, RTDB 19000 and fixture API 18088. The fixture API is confined to the test harness and loopback; it is absent from normal server startup. Only its demo data is reset. Existing identical forwards are preserved, conflicting ones refused, and newly created forwards removed. The successful run left no reverse entries. Local services were shut down afterward.

Earlier phone attempts did not count as passes: the first native build retained the normal Firebase resource and the project guard refused it before sign-in/fixture calls; Gradle selection was corrected and the generated demo resource verified. The next attempt reached the demo fixture but failed on an unavailable offline custom font; isolated test builds now use Android system typography while the normal theme retains its font. A later attempt lost the USB device after installation; reconnecting and rerunning produced the successful result above. A sandboxed final Flutter invocation stalled before producing results and was interrupted; the subsequent final host invocation completed analysis and all 22 tests. No unsuccessful attempt was reported as passed.

## Exact Phase 1B file scope

Paths below are repository-relative. Git's diff against HEAD also contains pre-existing Phase 1A changes; it is not a Phase 1B-only diff.

25 existing files were extended/changed in Phase 1B (three were already untracked Phase 1A files):

```text
android/app/build.gradle.kts
android/app/src/debug/AndroidManifest.xml
backend/README.md
backend/aqi.js
backend/firestore.js
backend/forecast.js
backend/package.json
backend/server.js
backend/scripts/run-emulators.js
backend/scripts/test-emulators.js
backend/test/helpers.js
firebase.json
lib/data/mock_data.dart
lib/models/device_snapshot.dart
lib/repositories/firestore_device_repository.dart
lib/screens/device_dashboard_screen.dart
lib/screens/history_screen.dart
lib/state/device_state.dart
lib/theme/app_theme.dart
lib/utils/aqi_utils.dart
lib/widgets/aqi_indicator.dart
lib/widgets/device_card.dart
lib/widgets/history_chart.dart
pubspec.yaml
pubspec.lock
```

16 new Phase 1B files:

```text
android/app/src/debug/res/xml/pura_debug_network_security.xml
android/app/src/emulator/google-services.json
backend/durable-telemetry.js
backend/telemetry-contract.js
backend/scripts/physical-vertical-slice.js
backend/scripts/simulator.js
backend/test/telemetry.test.js
backend/test/telemetry-emulator.test.js
docs/development/TELEMETRY_CONTRACT.md
docs/development/AQI_SEMANTICS.md
docs/development/PHASE_1B_RESULTS.md
docs/development/artifacts/telemetry-fixture.json
docs/development/artifacts/physical-telemetry-fixture.json
integration_test/telemetry_e2e_test.dart
lib/models/telemetry_reading.dart
test/telemetry_test.dart
```

No Phase 1B edits to `database.rules.json`, `firestore.rules`, `backend/device-security.js`, `backend/user-api.js`, the existing security/emulator test files, or Phase 1A Flutter permission/API test files. Other Phase 1A modifications visible in status remain unstaged. Final combined status: 32 tracked modified files, 29 untracked files, no staged changes, no deletions; branch/HEAD unchanged. Generated build/emulator logs are ignored.

## Limits and follow-up

- No production Firebase writes, rule deployment, migration, history deletion, cloud deployment or firmware work occurred. Normal server startup still requires reviewed credentials/membership migration from Phase 1A before production use.
- Delivery is durable acceptance plus idempotent processing with eventual recovery, not exactly-once delivery or a cross-database transaction. Terminal failures require inspection and deliberate trusted replay after fixing the cause. Recovery from a killed process may wait for the 60-second lease.
- The single global queue counter/lease deliberately serializes work and creates head-of-line blocking during retries. This needs workload/cost testing and a retention/archival plan before production scale; receipts/identities are not automatically expired. Queue defaults currently come from module options, not the removed in-memory queue environment knobs.
- Forecast regression is a prototype with no accuracy validation; raw device clock quality, real sensor calibration and physical hardware reliability remain unverified. CO2/MQ-135 do not establish official overall AQI. No actuator acknowledgements or notification delivery was added.
- The Android debug-only cleartext exception is limited to loopback/test hosts. The isolated phone test installs a debug test app and uses a public demo-only account/key; it does not validate production sign-in/network operation or release packaging. The test theme avoids remote font fetching; normal app font packaging remains outside this telemetry milestone.
- Node emitted a Windows `.bat` shell deprecation warning during the harness run. The command/arguments are fixed apart from a validated explicit device identifier. It did not prevent successful checks; broader process-launch portability remains follow-up work.

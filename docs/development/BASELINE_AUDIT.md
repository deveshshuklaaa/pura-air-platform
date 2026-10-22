# PURA AIR — Phase 0 baseline audit

Audit date: **21 October 2026 (Asia/Calcutta)**. Scope: repository inspection, existing checks, isolated local probes, and this report only. No production behavior, schemas, rules, dependency versions, or firmware changed.

## 1. Repository protection and provenance

- Repository: `C:\dev\PuraAir`; user-specified upstream: `https://github.com/deveshshuklaaa/pura-air-platform`.
- Baseline commit: `e5ec5da2ed325be411ea3c2bbf9129f9d75e36c4`.
- Initial status: `## main...origin/main`, no modified or untracked files; only local branch was `main`.
- Created and switched to **`feat/pura-air-stabilization`**, starting at that commit. Initial sandbox attempt failed because `.git` was read-only; the elevated retry succeeded. No branch was overwritten.
- Ran the four requested Git inspections. The repository has only four commits, so `git log -5 --oneline` returned four: `e5ec5da` (cloud readiness), `c0bf904` (test001 backend), `3f8d1b6` (authentication/logout), `4ea2868` (initial application). Commit messages are not verification evidence. Inspected their change summaries.
- No commits, pushes, merges, resets, cleans, stashes, history rewrites, or deployed changes. Final intended Git diff is this new report only; generated build/cache files are distinguished from source changes.

## 2. Executive assessment

**The application is not established as a working end-to-end platform.** Significant mobile and backend code exists, and source analysis and syntax checks pass, but authorization rules contain direct privilege-escalation paths, failed ingestion retries can be silently discarded, and the UI represents generated trends and requested actuator settings as meaningful device state. No firmware or simulator closes the hardware loop.

Keep Flutter/Riverpod, the Node HTTP service, and Firebase. The evidence supports targeted repair of authorization, ingestion reliability, and data presentation; it does not justify a framework or database rewrite. A durable acceptance/recovery mechanism is needed inside the ingestion component, with its design chosen after defining delivery guarantees.

## 3. Inspection coverage and repository structure

Reviewed `lib/main.dart`, all Dart files in `screens/`, `repositories/`, `state/`, `services/`, `models/`, `utils/`, `widgets/`, plus `theme/` and `data/`; all five backend JavaScript modules; manifests and lockfiles; both READMEs; Firebase configuration/rules; the sole test; Android build/settings/manifests; web bootstrap/manifest; ignore rules; tracked-file inventory and Git history summaries.

| Area | Actual contents |
| --- | --- |
| `lib/screens/` | Authentication, splash, device management, QR display/scan, dashboard, controls, history, notifications, profile, navigation shell |
| `lib/repositories/` | Firebase device/profile repositories, interfaces, in-memory mock repositories |
| `lib/state/` | Riverpod auth, device selection/history, profile and theme providers |
| `lib/models/`, `utils/`, `widgets/` | Device/profile models, AQI display categories/colors, charts, controls and shared UI |
| `backend/` | Built-in HTTP server, Firebase Admin initialization, particulate sub-index calculation, regression forecast, history/dead-letter/retention helpers |
| Firebase | `firestore.rules`, `database.rules.json`; `firebase.json` references rules only |
| Platforms | Android and web scaffolding; no tracked iOS application |
| Automated checks | One Flutter widget smoke test; backend `check` script checks only `server.js` syntax |
| `.github/` | Local Java-modernization hook scripts; **no CI workflow** found and no tracked workflow |
| Hardware/simulation | **No ESP32 firmware, PMS5003/SCD40/MQ-135 drivers, actuator firmware, device simulator, or acknowledgement protocol found** in source/tracked inventory |
| Deployment | Local/PM2 instructions; no container, deployment workflow, emulator test setup, or reproducible cloud release procedure found |

Android Google services client configuration is tracked. Its presence does not prove configured authentication providers or working cloud services. A local service-account file exists and is ignored by `backend/.gitignore`; its contents were not printed. Root ignore rules do not generally exclude `.env` files or alternate credential filenames. No complete historical secret scan was performed.

## 4. Commands and actual results

Commands ran from the root except backend checks from `backend/`. No dependency upgrade or audit fix was run. Permission-limited attempts are recorded separately from completed checks.

| Check | Exit / outcome | Evidence and limits |
| --- | --- | --- |
| `flutter --version` | 0, pass | Flutter 3.38.9 stable; Dart 3.10.8; DevTools 2.51.1 |
| `flutter pub get` | 0, pass | Dependencies resolved; reports 60 newer incompatible package versions, not a failure or permission to upgrade |
| `flutter analyze` | 0, pass | No issues found; reported duration 120.5 seconds |
| `flutter test` | 1, fail | 0 passed, 1 failed: `App boots`; `Bad state: No ProviderScope found`, followed by missing `PURA AIR` text assertion |
| `flutter build apk --debug` | 1, blocked | Gradle `assembleDebug` failed with `java.io.IOException: Unable to establish loopback connection`; compilation/APK success not established |
| `node --version` | 0, pass | v24.13.0; manifest requires >=20 |
| `npm --version` | 0, pass | 11.6.2 |
| `npm ci` | 0, pass after elevated retry | Added 163 packages, audited 164; lockfile unchanged |
| `npm run check` | 0, pass | Syntax only, `node --check server.js` |
| `node --check server.js` | 0, pass | Syntax only |
| `node --check aqi.js` | 0, pass | Syntax only |
| `node --check forecast.js` | 0, pass | Syntax only |
| `node --check firebase.js` | 0, pass | Syntax only |
| `node --check firestore.js` | 0, pass | Syntax only |
| Dependency advisory inspection | Findings, not clean | `npm ci` reported 17 vulnerable packages: 2 critical, 5 high, 9 moderate, 1 low. Parsed `npm audit --json` summary pipeline exited 0; this is the summarizer's exit, not an assertion of a clean audit |
| Isolated backend probes | 0, assertions passed | Known arithmetic/HTTP cases and defect reproductions below; no cloud or hardware contacted |
| Firebase/rules/device end-to-end | Not run / unverified | No emulator integration setup; no cloud writes or live backend startup performed |

Initial sandbox Flutter invocation produced no output and was interrupted (exit 1); it is not a code failure. The initial sandbox backend install reported `Exit handler never called!` from npm; its chained shell ended 0 after independent syntax checks, so that shell exit must not be reported as a successful install. Repeated install/checks with cache/network access succeeded. Native process inspection was unavailable in the sandbox and succeeded with elevated read access.

### Isolated probe method and results

Used ephemeral Node scripts passed through standard input, leaving no test files in the repository. Loaded `aqi.js` and `forecast.js` directly. For private server helpers, evaluated the existing `server.js` source in a Node VM after omitting its final `start().catch(...)` call, with Firebase initialization stubbed. Database writes were stubbed; HTTP handler probes used in-memory request/response objects. This verifies helper behavior, **not a listening HTTP server, Admin SDK persistence, deployed rules, or production delivery**.

- AQI input `(pm25=12, pm10=54)` returns 50; assertion passed for current code's table.
- Forecast points at one-minute intervals with AQI 10, 11, 12 yield 22 at +10 minutes and 42 at +30 minutes; assertions passed. Empty history returns null. These are mathematical smoke cases, not measured forecast accuracy.
- Missing ingestion key returns 401; authenticated valid payload returns 202 with `status: queued` while workers are blocked; full queue returns 503. Assertions passed.
- Authenticated `{}` sensor payload also returns 202: reproduced deferred sensor validation.
- Null/null and empty-string/false PM inputs normalize to 0/0; negative PM values are accepted and clamp to AQI zero: reproduced.
- `(12.05,54)` and `(12,54.5)` return null AQI because of breakpoint gaps: reproduced.
- Injected first history-write failure, then retried identical event: only one write was attempted. The second call returned without retrying persistence: reproduced.

## 5. Architecture and integration contracts

### Telemetry path

1. **Producer: missing.** No hardware firmware or simulator produces this repository's ingestion contract.
2. **HTTP authentication: implemented, locally probed, cloud integration unverified.** `POST /ingest/{deviceId}` accepts `X-Device-Key` or Bearer key, checks registry existence and either a shared or device-specific key (`server.js:523-582`). It does not use mobile Firebase ID tokens for device ingestion. `ALLOW_UNAUTH_INGEST=true` explicitly bypasses authentication. No endpoint rate limiting is implemented.
3. **Acceptance: partial.** JSON object parsing/body limit exists. Sensor validation is repeated in the worker, after a 202 response (`server.js:631-669`). 202 explicitly means **queued**, not persisted; this distinction is correct. No durable receipt/status lookup is returned.
4. **Processing: defective under failure.** Bounded in-memory queue, per-device serialization, worker concurrency, dedupe and dead letters exist, but no durable queue/replay or retry on write failure.
5. **AQI: implemented with defects and undefined intended standard.** Calculates maximum of two particulate sub-indices from one reading; see finding D6.
6. **Firestore then RTDB:** history is written to `devices/{id}/history/{eventKey}` with numeric `timestamp`, `server_received_at`, AQI/PM fields, then forecast and live state are updated at RTDB `devices/{id}` (`server.js:283-340`). The two databases do not share a transaction. Temperature, humidity and CO2 are live fields but are not stored in the history record.
7. **Flutter live subscription: implemented but unverified.** Watches user Firestore device membership and RTDB state plus forecast (`firestore_device_repository.dart:24-137`). Listener errors remove live values and silently fall back to stored/default values. Missing readings can display zero/Good rather than unavailable.
8. **History contract matches for current records.** Flutter queries `devices/{id}/history` ordered by `server_received_at`, limit 30, then sorts numeric `timestamp` for display (`device_state.dart:42-84`); backend writes those fields. Legacy records without the ordering field are excluded. Device-clock order can differ from arrival order. Charts plot sample index, not elapsed time (`history_chart.dart:34-36`). No live query/rules/index test passed.
9. **Forecast consumed partially.** Flutter subscribes to `forecast`, reads `aqi_10min`, subtracts current AQI and uses that delta as a trend. `aqi_30min` and `calculated_at` are not consumed. The dashboard labels a generated chart “15-min Trend”, so neither the curve nor label correctly represents that 10-minute prediction (`firestore_device_repository.dart:375-377`; `device_dashboard_screen.dart:52-81`).

### Command path

Flutter controls write Firestore per-user cached state and RTDB `devices/{id}/controls` concurrently (`firestore_device_repository.dart:141-172`). The backend RTDB listener normalizes the request and writes mode/fan/mist straight into live `state` (`server.js:343-355,440-462`). **The path ends there:** no device consumer, command ID, acknowledgement, execution timeout, reported actuator feedback, physical interlock or tested automatic-control policy was found. AUTO/MANUAL are stored modes, not proof of implemented automatic actuation. UI writes have no visible failure/rollback handling (`control_panel_screen.dart:49-72`), and cached values only synchronize when device ID changes.

## 6. Feature status

Statuses: Verified working = repeatable local evidence for the stated narrow behavior; Implemented but unverified = code exists without the necessary integration pass; Partially implemented = important pieces absent; Missing = none found; Defect = incorrect/risky behavior demonstrated by code or probe; Blocked = identified environment prevents a required check.

| Feature | Status | Evidence / limit |
| --- | --- | --- |
| Flutter dependency resolution/static analysis | Verified working | Completed checks, exit 0 |
| Backend syntax | Verified working | All five modules, exit 0; no runtime implication |
| Email/password, Google, anonymous auth | Implemented but unverified | `auth_state.dart:18-28`, `google_auth_service.dart:12-30`, auth screen; no real sign-in test |
| Profile editing | Implemented but unverified | Firestore profile repository; no save/reload or account-switch test |
| Registry claim, QR management | Implemented but unverified | Client transactions and scanner/display exist; not ownership security proof |
| Pairing/share lifecycle | Defect | Predictable non-expiring codes, rule bypass, cross-database side effect inside transaction |
| User/device authorization | Defect | Direct self-grant and fabricated membership paths |
| HTTP key check/202/queue-full handling | Verified working | Only isolated handler cases; actual service and persistence unverified |
| Input validation/idempotency/recovery | Defect | Coercion, breakpoint gaps, retry suppression; volatile queue |
| History persistence and RTDB state | Implemented but unverified | Real persistence not tested; non-atomic writes |
| History UI | Partially implemented | Correct current schema query; synthetic empty-history fallback and sample-index axis |
| Dashboard trend | Defect | `_fakeTrend` is used in normal Firebase path |
| Regression arithmetic | Verified working | One known straight-line case and empty input; no accuracy claim |
| Forecast feature | Partially implemented | 10-minute delta consumed, 30-minute value/freshness unused; cold-cache bias |
| Fan/mist cloud controls | Partially implemented | Cloud request/state echo; no hardware completion |
| Automatic control/failsafes/acknowledgement | Missing | No policy/device execution evidence |
| Notification delivery client | Partially implemented | Foreground FCM/local display; no end-to-end delivery |
| Preferences and alert policies | Missing | Switches local only; no token registration/refresh persistence or backend policy sender found |
| Accurate offline detection | Defect | Stored true flag wins after stale timestamp; no periodic recomputation |
| Mock/demo fallback | Defect | Firebase auth/history still required; broadcast initial values emitted before subscribers |
| Firmware, sensor drivers, simulator | Missing | Repository inventory/search |
| CI and backend automated suite | Missing | No workflow or backend test script/files |
| Repeatable cloud deployment | Partially implemented | PM2/local run notes only |

## 7. Concrete findings, ordered by severity

### D1 — Critical: client-controlled authorization and exposed device credentials

- `database.rules.json:6-12` permits a user to write **any** device entry beneath their own `device_access/{uid}`. Setting an arbitrary entry to true satisfies the state/forecast read and control write predicates (`:15-30`). No actual ownership check exists there.
- `firestore.rules:4-9` lets a user create arbitrary documents in their own device subcollection. History access only tests that such a document exists (`:24-28`). `server.js:672-684` later copies those untrusted memberships into RTDB ACLs. Fixing only the direct RTDB write rule would leave this second bypass.
- Registry documents are readable by every authenticated user (`firestore.rules:14-15`) while ingestion reads plaintext `ingest_key` from the same registry document (`server.js:530-534,578-579`). **If per-device keys are provisioned as implemented, authenticated clients can read them.** This is a schema/rules exposure risk, not a claim that a live key was observed.
- Registry claim uses `changedKeys()` rather than added/removed/changed-field validation (`firestore.rules:16-20`); adding/removing unrelated fields during a claim is not excluded by that field-change test.
- Findings are source-proven authorization defects, not live exploit tests. Deployed rules and their revision were not read. Anonymous Firebase users also satisfy `request.auth != null` when that provider is enabled.

### D2 — High: accepted readings can be lost and retries suppressed

`server.js:256-267` marks signatures/event keys seen **before** AQI/history/RTDB success. Worker failure at `:394-405` logs and drops the event without retry, dead-letter persistence, or clearing dedupe. Isolated failure injection proved that a retry after history write failure makes no second write attempt. If RTDB fails after Firestore succeeds, history exists while current state/forecast can remain stale and the retry is suppressed.

The queue and dedupe maps exist only in process memory (`:52-63,358-408`); restart loses queued accepted work and dedupe state. Shutdown closes listeners/HTTP but does not drain active/queued processing (`:822-829`). Full queue produces 503 and attempts a best-effort dead letter, whose failure is only logged. A producer retry protocol is absent. Without a stable explicit idempotency key, sequence alone is insufficient: event key also includes timestamp, and missing timestamps are regenerated on retries (`:121,178-187`). Invalid sensor objects receive 202 and may fail only later.

### D3 — High: vulnerable locked dependencies require controlled remediation

`backend/package-lock.json` locks `firebase-admin` 13.6.1, `protobufjs` 7.5.4 and `websocket-driver` 0.7.4. On audit date npm reported 17 vulnerable package entries, including critical `protobufjs` and `websocket-driver`, and high-rated gRPC, XML parsing, crypto and multipart dependencies. This is an advisory inventory, **not proof each issue is remotely exploitable through this app**. Assess reachable paths and upgrade in a separately tested change; no `npm audit fix` or dependency mutation was performed.

Representative advisory sources returned by npm: [protobufjs code execution](https://github.com/advisories/GHSA-xq3m-2v4x-88gg), [websocket-driver compression resource limits](https://github.com/advisories/GHSA-mp7j-qc5w-4988). Some suggested remediation requires a major Firebase Admin update; do not apply blindly.

### D4 — High: cloud control state is presented without physical confirmation

The backend writes requested controls into live state immediately (`server.js:343-355`), and telemetry processing copies cached requested controls into state (`:324-329`). There is no evidence of hardware execution. UI claims “Auto logic active”/“paused” (`lib/widgets/control_panel.dart:32-33,73-78`) without an implemented policy. Any operational/safety claim must wait for a command/acknowledgement protocol and tested hardware/failsafes.

### D5 — High: fabricated and stale data can look real

- Dashboard calls `_fakeTrend` unconditionally (`device_dashboard_screen.dart:62,72-81`), including the real-data path.
- History synthesizes seven identical values when history is empty (`history_screen.dart:82-94`), without labeling them as unavailable/sample.
- Live read errors are swallowed (`firestore_device_repository.dart:75-78,89-92`), and mapping supplies zero/default sensor values (`:375,393-403`). Missing AQI can appear Good.
- Stale timestamps fall back to the stored `online` flag, default true (`:379-385`); new membership initializes true (`:321-325`). Missing last-seen becomes now (`:415-419`). No timer forces reevaluation when telemetry stops.

### D6 — High: input validation and AQI semantics are not reliable

`server.js:85-125` uses JavaScript numeric coercion: null, blank strings and false become zero. It checks finite PM values, not sensor types/ranges, positive timestamps, humidity bounds, plausible temperatures or integer sequences (`parseInt` accepts numeric prefixes). Negative PM values produce AQI zero. Arbitrary idempotency keys become Firestore document paths (`server.js:178-180,296`; `firestore.js:9-19`), without length/path validation.

`aqi.js:3-19,34-55` has discontinuities (12.0–12.1 for PM2.5; 54–55 for PM10) without concentration truncation, causing null results for valid fractional inputs. It clamps all values to 0–500 behavior and requires both particulate sub-indices. It processes each raw observation without an averaging/completeness window.

**Intended standard is not declared in repository documentation.** The table and UI categories resemble older US particulate AQI conventions; they are not Indian CPCB AQI and do not match current US guidance. The [EPA May 2026 technical assistance document, Table 6 and calculation section](https://document.airnow.gov/technical-assistance-document-for-the-reporting-of-daily-air-quailty.pdf) specifies a PM2.5 Good boundary of 9.0, concentration truncation and defined averaging/NowCast procedures. The [Indian Economic Service government explanation](https://ies.gov.in/arthapedia/concept/national-air-quality-index) describes different breakpoints/categories, at least three pollutants including PM, and completeness requirements. CO2 and an uncalibrated MQ-135 gas index do not establish those pollutant requirements. Choose and document an intended particulate indicator or standard before changing calculations. Neither official CPCB nor official US EPA compliance is verified.

### D7 — Medium: pairing is predictable, non-expiring and not rate-limited

`firestore_device_repository.dart:308-318` deterministically derives six characters from the current microsecond timestamp, without cryptographic randomness. Codes store creation time but no expiry (`:291-302`); redemption never checks age (`:233-270`). Rules allow authenticated direct code lookup, without expiry or per-user guessing controls (`firestore.rules:34-54`). Creation checks for an existing code then writes outside a transaction, leaving a collision race. Deleting on redemption is implemented, but is not sufficient authorization because D1 permits arbitrary membership.

The RTDB ACL grant is awaited **inside** the Firestore transaction callback (`:270`), so callback retries/commit failures can leave cross-database side effects. Revocation/removal similarly spans databases independently (`:350-363`); removed membership does not transfer/release registry ownership, and server ACL sync does not clean users absent from its user-document listing. No share revocation role model found.

### D8 — Medium: forecast quality and history retention have gaps

- Cold-cache processing saves current history before loading recent history, then appends the same point (`server.js:299-305`, `getForecastHistory:211-223`), double-weighting the first point after cache initialization. This is source evidence, not a measured accuracy result.
- Regression has fallback/clamping but no quality/confidence/minimum time coverage checks (`forecast.js:55-75`). No held-out data, MAE/RMSE, drift/staleness evaluation or measured error report found.
- Retention's legacy query filters **all** old device timestamps without restricting to records missing `server_received_at` (`firestore.js:61-73`), so newly received records with bad/old device clocks may be deleted despite recent arrival. Two query batches can combine to more than 250 deletions; the loop stops only below 250 (`server.js:700-711`). Verify behavior/scale against the target SDK before relying on retention.

### D9 — Medium: notification and fallback promises exceed implementation

`notifications_screen.dart:12-42` keeps switches only in widget state; leaving/recreating the screen resets them. `notification_service.dart` receives/display foreground notifications and exposes `getToken()`, but no caller persists tokens or refreshes them, and no backend alert evaluator/sender was found. Preferences cannot govern a policy that is absent.

`main.dart:15-20` swallows Firebase/notification initialization errors and comments that mocks will work, but `auth_state.dart:5-6` immediately needs Firebase Auth, and the history provider always uses Firestore. Mock repositories emit initial values on a broadcast controller before listeners attach, so first subscriptions receive no initial snapshot. README's automatic anonymous sign-in claim is stale: anonymous sign-in is an explicit auth-screen action.

### D10 — Medium: test and deployment baseline is insufficient

The only tracked Flutter test (`test/widget_test.dart:5-7`) pumps `PuraAirApp` without `ProviderScope`, although the app is a `ConsumerWidget`; the check actually failed with `Bad state: No ProviderScope found` and a consequent text assertion failure (0 passed, 1 failed). It also lacks Firebase/provider isolation. No backend behavior tests, rules tests, integration tests or CI exist. Backend “check” means syntax only.

`backend/README.md` documents dependencies, credentials, environment options, API and PM2, but not a pinned runtime/PM2 version, emulator setup, TLS/reverse proxy, deployment rollback, rules verification or delivery acceptance checks. `firebase.json` defines no deployment target for the Node service. Android release currently signs with debug keys (`android/app/build.gradle.kts:35-40`); only debug/profile manifests explicitly declare INTERNET. Release merged permissions have not been inspected. Android Gradle wrapper scripts/JAR are ignored, so clean-machine build prerequisites need verification. Web scaffolding exists but Firebase web options/service-worker integration is absent, and notification code uses `dart:io`/Platform; no web build/runtime claim is made.

## 8. Verification boundaries and missing tests

### Firebase rules checklist assessment

Applied the Firebase security-rules auditor skill's create/update, authority-source, business-logic, resource-limit, type-safety and field/identity checks. This is a static assessment of repository rules; no emulator or deployed-rule execution occurred.

```json
{
  "score": 1,
  "summary": "Critical: client-writable authorization sources allow unauthorized device access; deployed rule state is unverified.",
  "findings": [
    {
      "check": "Authority Source / Field-Level vs Identity-Level Security",
      "severity": "critical",
      "issue": "Users can self-grant RTDB device_access and fabricate Firestore memberships that authorize history and are copied into RTDB ACLs.",
      "recommendation": "Provision membership and ACLs through trusted ownership/share authorization; test both bypass paths with two users."
    },
    {
      "check": "Business Logic vs Rules",
      "severity": "critical",
      "issue": "All authenticated clients can read registry documents used to store per-device ingestion keys.",
      "recommendation": "Keep ingestion credentials inaccessible to mobile clients and expose only necessary registry metadata."
    },
    {
      "check": "The Update Bypass",
      "severity": "major",
      "issue": "Registry claim checks changedKeys but not added or removed fields; pairing creation validates ownership but not expiry or complete field shape.",
      "recommendation": "Restrict all affected fields and validate immutable identity, exact field sets and lifecycle constraints."
    },
    {
      "check": "Storage Abuse / Type Safety",
      "severity": "minor",
      "issue": "Firestore profile/device/pairing writes lack comprehensive type, allowed-field and string-size limits; RTDB controls allow fractional fan levels and arbitrary numeric updated_at values.",
      "recommendation": "Define and enforce bounded field contracts; prevent resource exhaustion and malformed records without weakening ownership checks."
    }
  ]
}
```

- Flutter/Node/Java/Android tools are present; initial sandbox limitations required elevated SDK/cache/network access.
- Android debug build was attempted with elevated access but Gradle failed before compilation with `java.io.IOException: Unable to establish loopback connection`. This is a local networking/runtime blocker; its underlying cause was not established, and it does not prove an application compile failure or a successful build. No code/configuration workaround was applied.
- Environment indicates service-account path/database URL configured and local key file present; values/credential contents were not disclosed. This is **not** evidence the credentials are valid or Firebase connectivity works. No live service was launched because startup automatically starts access synchronization and retention writes.
- No live Firebase auth, registry reads, ownership transactions, RTDB subscriptions, deployed-rules checks, Firestore queries, FCM delivery or cloud deployment was verified.
- No real/simulated device, physical sensor reading, fan/mist execution, calibration or actuator safety test was performed.
- Missing automated coverage: two-user/adversarial rules matrix; pairing expiry/collision/replay/revocation; authentication/logout/account switching; device/provider stream lifecycle; missing/stale/error display; forecast/history schema mapping; malformed ingestion types/ranges/body/path/key limits; queue overload; persistent retry/restart/shutdown; multi-instance dedupe; RTDB partial failure; history retention and clock skew; forecast boundaries/fallbacks/held-out error; controls acknowledgement/failure; preference persistence/alert dedupe/token refresh; Android clean build and emulator UI smoke.
- The ephemeral probes above are reproducible local diagnostics, **not a committed regression suite**. Phase 0 does not add tests or code repairs.

## 9. Prioritized roadmap and next milestone

**Recommended next milestone: secure, repeatable ingestion-to-mobile baseline using a clearly identified simulator and Firebase emulators.** Preserve the architecture; repair its contracts before hardware/deployment expansion. Do not start this milestone as part of Phase 0.

1. **Authorization first:** define owner/shared roles and trusted membership provisioning, separate device credentials from readable metadata, eliminate both self-grant routes and registry field mutation loopholes. Add emulator rules tests before live deployment. Pairing must use secure randomness, expiry, one-time atomic redemption and enforced guessing controls.
2. **Delivery guarantees and payload contract:** define units, types, ranges, timestamp semantics, event identifiers, 202 receipt meaning, durable acceptance/replay, retention and duplicate semantics. Repair retry suppression and cross-database recovery; validate dependency remediation with regression tests. Depends on protected device credential provisioning.
3. **Choose AQI semantics:** document intended indicator/standard, averaging, precision, completeness and categories; add known-value/boundary tests. Keep raw measurements and expose missing/invalid state explicitly.
4. **Emulator + simulator vertical slice:** generate only labeled test telemetry; prove authenticated ingestion -> history -> RTDB state/forecast -> Flutter dashboard/history. Remove synthetic live/history placeholders, use real timestamps, expose stale/error states. Depends on 1–3.
5. **Command contract:** distinguish desired, pending and reported state; add command identity, acknowledgement, timeout, idempotency and failure tests with simulator. Physical actuation waits for separately verified firmware/hardware.
6. **Later milestones:** ESP32 drivers/calibration/failsafes and bench testing; persistent alert preferences and tested delivery policies; forecast error evaluation; reproducible secure deployment, monitoring and rollback. Add CI as checks become repeatable, starting in the next milestone.

### Concrete acceptance criteria for the next milestone

- Clean checkout with documented tool versions resolves locked dependencies; static analysis, repaired widget tests, backend unit/integration suite and debug Android build succeed in CI. Dependency advisories are fixed or explicitly triaged with reachability evidence and an owner.
- Emulator tests show unauthenticated users and a second unpaired user cannot read telemetry/history, write controls, grant ACL/membership, read ingest credentials or mutate registry metadata. Legitimate owner and authorized share flows succeed; revoked/expired/reused codes fail.
- Simulator posts typed telemetry with stable event IDs; wrong/missing keys fail, invalid readings reject before acceptance, queue overload has documented retry behavior. Accepted readings survive injected database failure and process restart with eventual history/live-state convergence and no unintended duplicate history. 202 never implies persistence or hardware execution.
- Fixed golden AQI cases and fractional-boundary tests pass for the chosen documented semantics; insufficient/invalid measurements show unavailable. Forecast known-value tests pass and a measured error baseline is reported before claiming predictive quality.
- Flutter on an emulator displays the simulator's exact values/history timestamps and forecast horizon; no generated data appears as measured history. Stopped telemetry becomes visibly stale/offline within a documented interval; permission/connection errors remain visible.
- Simulator command tests show desired/pending state until matching acknowledgement, confirmed state only afterward, and timeout/failure feedback. No physical actuation claim is made at this milestone.
- One documented command/workflow boots isolated services, seeds non-secret fixture devices/users, runs the slice and shuts down without touching production Firebase.

## 10. Action ledger

Read the pasted task and repository/configuration/history files; checked available memory tooling (none exposed); inspected initial Git state; attempted then successfully created the requested branch; ran requested dependency/static/syntax/test/build checks and independent retries; inspected npm advisory results; ran ephemeral AQI/forecast/normalization/failure/HTTP probes with stubs; checked only credential presence; consulted primary government AQI documentation; created this report. Dependencies and Flutter tooling may populate ignored caches/build outputs. No production Firebase process, service-account contents, real telemetry or hardware was accessed. Final check outcomes and worktree verification are appended below.

### Final verification

- Current branch: `feat/pura-air-stabilization`; HEAD unchanged at the baseline commit.
- Final Git status: only `?? docs/development/BASELINE_AUDIT.md`.
- `git diff --exit-code -- pubspec.lock backend/package-lock.json`: exit 0; no lockfile changes. `git diff --check`: exit 0 (tracked diff); report whitespace additionally inspected separately.
- Only authored repository file: this report. No production source, manifest, rules, schema or test edits. Requested checks generated/refreshed ignored dependency/cache/build artifacts.
- Phase 1 was not started. The failing widget test and Android environment blocker remain documented rather than repaired in this phase.

# Phase 1A implementation and verification results

Date: 21 October 2026 (Asia/Calcutta). Branch: `feat/pura-air-stabilization`. HEAD remains `e5ec5da2ed325be411ea3c2bbf9129f9d75e36c4`. No commits, pushes, merges, migration or deployment occurred.

The original untracked Phase 0 report was preserved byte-for-byte (SHA-256 `B6B2B7EF28C72F7F16293FEF428413150A2D308621427CA0DE7DDF6A8828908B`). No other pre-existing source changes were present. Implementation retains Flutter/Riverpod, the built-in Node HTTP server and Firebase.

## Authorization and compatibility

See [AUTHORIZATION_SECURITY.md](AUTHORIZATION_SECURITY.md) for the full schema, endpoint/error contract, role matrix, cross-database outage behavior and explicit manual migration plan. Canonical private registry membership replaces client-owned authorization sources. Owners control/manage; shares read only; guests and unpaired users cannot access device data. Client registry, credential, membership, ACL and pairing writes are denied. User-facing API identity is a revocation-checked Firebase ID token. Pairing uses hashed 128-bit random one-use codes with expiry, owner binding and durable per-account attempt limits.

The old mobile direct-write protocol, short pairing codes, Boolean ACLs and registry ingestion-key location intentionally require a coordinated upgrade. The backend never promotes old user memberships or falls back to registry keys. Owner removal preserves registry ownership and other users' access; owner reclaim restores their membership. Shared members cannot rename/control/share. Names are global owner-managed metadata, rather than per-user aliases. RTDB authorization publication uses versioned 90-second leases with a default 30-second reconciliation interval; failed publication returns 503 with an explicit refresh message.

## Completed checks

| Check | Actual outcome |
| --- | --- |
| `flutter pub get` | Pass, exit 0; `pubspec.lock` unchanged |
| `flutter analyze` | Pass, exit 0, no issues found after fixes |
| `flutter test` | Pass, exit 0: **14 tests**, including two isolated boot tests, nine API-client cases, three permission/error UI cases |
| `npm ci --ignore-scripts` | Pass, exit 0: 203 installed packages, 204 audited; final manifest/lockfile consistent |
| `npm run check` | Pass, exit 0: all seven backend source modules |
| `npm test` | Pass, exit 0: **15 backend tests** with transactional test double and actual handler functions; explicitly not cloud/emulator evidence |
| Firebase rules/integration suite | **Pass, exit 0: 12 tests** against isolated Firestore and RTDB emulators; 0 failed/skipped; completion receipt verified |
| Android debug APK / physical device | **Pass**: APK built, installed and launched on connected Samsung SM-S928B, Android 16 / API 36, ARM64; `flutter run ... --debug --no-resident` exit 0 |
| Physical app process/foreground | Pass: app PID returned, foreground activity `com.puraair.app/.MainActivity` |
| `git diff --check` | Pass, exit 0 |
| Production Firebase/cloud/hardware | Not tested or deployed |

The physical device was used at the user's request; no Android app emulator was launched. Firebase's isolated local database services are a separate rules-testing requirement. Launching on the phone verifies packaging, installation and process startup, not real owner/share workflows against production Firebase. The phone build had no guessed API endpoint: management requires a configured `PURA_API_BASE_URL` and migrated/reviewed backend. No sign-in, production claim/pairing/control operation or live rules modification was performed as part of physical-device checking.

Initial Flutter checks caught a remaining direct GoogleAuth initialization and missing braces/context guards. Those were corrected, then all 14 tests and analysis passed. The loading screen's timed navigation around the auth gate was removed. Initial Java/Gradle and emulator attempts failed on `Unable to establish loopback connection`; Java 21/IPv4 and selector-only trials failed. A command-local `jdk.net.unixdomain.tmpdir` setting pointing at a verified nonexistent workspace path enabled TCP fallback and the successful physical-device build. No persistent OS/network setting changed. See the contract for the exact workaround.

The first running rules suite passed nine cases but stalled on concurrent pairing with a Firestore emulator transaction-lock timeout. It was interrupted and is not counted as a full pass. ACL synchronization was using an unnecessary read transaction; a single device document read already atomically captures members and version. Replacing that transaction removed avoidable contention. The rerun used 45-second test timeouts and **all 12 cases passed in about 16 seconds**, including the actual concurrent pairing transaction. Emulators then shut down normally. A Windows CLI launcher had also returned early without test evidence; the new JS-entry-point wrapper requires an explicit completion receipt and rejects such false success.

## Vulnerability regression evidence

| Repair | Evidence |
| --- | --- |
| Self-granted RTDB ACL and forged Firestore membership | Deny-client rules plus canonical sync; backend test rejects legacy fabricated mirror as an authorization source; rules suite includes child/sibling/parent/multipath attacks |
| Ingestion key exposure | All registry/credentials reads denied; backend test verifies only the private credential collection is used and legacy registry-only keys are not accepted |
| Body-supplied UID/role and ownership escalation | Verified-token UID only, strict accepted fields; tests reject injected UID/secret/registry fields and competing claims |
| Anonymous privilege | Backend token-provider check and rules exclusion; handler test denies anonymous claims and rules cases deny even anonymous tokens with an owner UID |
| Owner/share privileges | Backend tests enforce owner-only rename/pair/revocation; UI tests hide shared controls/owner actions and surface rejected operations; rules tests exercise allowed owner controls and denied shared controls |
| Pairing guessing/replay/expiry/races | Backend tests cover bounded durable guesses across service instances, expiry, one-time concurrent redemption, replay, changed ownership and invalidated codes; rules/integration suite separately tests real Firestore transactions |
| Revocation/sync failures | Backend tests retain canonical removal on RTDB failure, expire stale leases and prevent older ACL versions from restoring access; rules suite checks denial after successful revocation |
| Control validation | Rules reject fractional/out-of-range speeds, wrong modes/types, stale/future timestamps, extra/missing fields and deletion |
| False success / broken boot test | Fourteen Flutter tests pass without production Firebase; rejected owner controls roll back UI values and rejected membership removal does not show “Device removed” |

## Dependency triage

No blind audit fix or Firebase Admin major upgrade was used. `firebase-admin` remains **13.6.1**, with its existing manifest range `^13.2.0`. Intentional lockfile changes:

- Added exact **dev-only** `@firebase/rules-unit-testing` 6.0.0 and Firebase JS SDK 13.1.0 for the requested isolated rules tests. Their Node >=24.12 test requirement is documented separately from the backend Node >=20 runtime contract.
- Compatible critical remediation: `protobufjs` **7.5.4 → 7.6.6**, `websocket-driver` **0.7.4 → 0.7.5**; related protobuf helper patches, including UTF-8 1.1.0 → 1.1.2, followed the compatible dependency ranges. Added Firebase test tooling caused compatible Firebase interop/database helper deduplication (database 1.1.0 → 1.1.5 and associated type/util patches); the production Admin SDK did not change. Runtime behavior was regression-checked with backend and rules suites, with the latter's exact outcome recorded below.
- `pubspec.yaml` and `pubspec.lock` were not changed.

After remediation npm reports **18 affected package entries overall: 0 critical, 9 high, 8 moderate, 1 low**. Production-only inventory: **14 entries: 0 critical, 5 high, 8 moderate, 1 low**. Audit pipelines retain npm's nonzero advisory exit; this is not a clean audit. Remaining production package names: `@fastify/busboy`, `@google-cloud/firestore`, `@google-cloud/storage`, `@grpc/grpc-js`, `@tootallnate/once`, `fast-xml-parser`, `firebase-admin`, `form-data`, `gaxios`, `google-gax`, `node-forge`, `retry-request`, `teeny-request`, `uuid`.

`firebase-admin` is the sole direct production dependency; the others are transitive. The new Firebase client/rules-test SDKs contribute four additional high-rated package entries through their Firestore/gRPC dependency chain. Current installed gRPC versions include Admin **1.14.3** and test-client **1.9.16**. Do not follow npm's suggested downgrade of the test SDK to an incompatible old major as a substitute for review.

Reachability assessment: Firestore gRPC and RTDB WebSocket transports are used by this app; protobuf code generation parses SDK-owned schemas, not arbitrary `.proto` input from `/ingest`. XML/multipart/crypto/storage advisories arrive via the Admin authentication/storage/HTTP transport graph; the built-in JSON ingestion endpoint does not itself expose an XML or multipart parser or a gRPC server. This is **not proof of non-exploitability** of SDK client paths or malicious upstream responses. A separate remediation change should map each advisory to the exact SDK call/configuration, update compatible leaf dependencies where supported, test real Auth/Admin/RTDB/Firestore behavior, and then assess any necessary Admin major upgrade with migration notes. Do not defer reachable gRPC/credential-validation concerns merely because they are transitive.

## Remaining risks / required next actions

- Live Firebase remains on its previously deployed rules/backend until a separately authorized coordinated rollout. Local repairs do not retroactively secure the cloud.
- Existing registry secrets must be moved/rotated and memberships rebuilt from verified ownership and explicitly approved shares. Old membership paths are untrusted. No automatic migration was executed.
- Cross-database failed revocations have the bounded remaining RTDB lease window (up to 90 seconds). Successfully published revocations deny subsequent reads/writes; downloaded data cannot be recalled.
- Claiming still uses an eligible provisioned device ID; no hardware possession proof/provisioning secret protocol was added. Publicly exposed unclaimed IDs need an operator provisioning/claim policy before production release.
- Per-account durable limits and 128-bit codes protect guessing; process-local IP limits are not a multi-replica ingress solution. Abuse through mass account creation and proxy deployment need separate operational controls.
- Test fixtures do not prove production provider configuration, disabled-account propagation into already-open database sessions, or deployed environment correctness. Physical owner/share sign-in and full app-to-backend workflows remain unverified until a configured isolated endpoint/staging rollout is available.
- Phase 0 telemetry reliability, generated trend/empty-history data, forecasting, physical acknowledgement and alert-policy gaps remain outside this phase. No firmware, sensor drivers, production simulator, AQI algorithm or notification delivery was added.

## Exact authored diff scope

Modified tracked files:

- `README.md`, `backend/README.md`: updated contract links/configuration and migration warnings.
- `backend/package.json`, `backend/package-lock.json`: scripts, exact dev test dependencies and narrow compatible advisory remediation.
- `backend/server.js`: user API integration, private credential lookup, canonical ACL reconciliation/default interval, import-safe startup for tests.
- `firestore.rules`, `database.rules.json`, `firebase.json`: owner/shared/guest policies, strict profiles/controls, isolated emulator configuration.
- `lib/models/device.dart`, `lib/repositories/firestore_device_repository.dart`: role model and trusted API integration; no direct membership/ACL/registry writes.
- `lib/screens/auth_screen.dart`, `lib/screens/splash_screen.dart`, `lib/screens/control_panel_screen.dart`, `lib/screens/device_list_screen.dart`: lazy Google authentication initialization, auth-gate navigation, owner-only actions/share management, safe errors and rollback; formatting in touched files.
- `test/widget_test.dart`: scoped/provider-isolated meaningful boot tests.

Created files:

- `backend/device-security.js`, `backend/user-api.js`.
- `backend/scripts/run-emulators.js`, `backend/scripts/test-emulators.js`.
- `backend/test/helpers.js`, `backend/test/security.test.js`, `backend/test/emulator.test.js`.
- `lib/services/device_api_client.dart`.
- `test/device_api_client_test.dart`, `test/device_permissions_test.dart`.
- `docs/development/AUTHORIZATION_SECURITY.md`, `docs/development/PHASE_1A_RESULTS.md`.

`docs/development/BASELINE_AUDIT.md` was already untracked at entry and remains present/unchanged. Ignored dependency/build/emulator diagnostic artifacts were generated. No staging or Git history changes. Final test outcome and repository checks are appended below.

## Final disposition

The local security repair and its automated acceptance suite pass: **15 backend + 12 Firebase rules/integration + 14 Flutter tests**. The current debug app built, installed and launched on the user's physical Android phone. These results establish local implementation/rules behavior; **production migration, API endpoint configuration, and full physical-phone owner/share workflows against the migrated backend remain outstanding**. Do not infer live cloud protection or deployment readiness from the local pass. No Phase 1B, firmware or other product milestone was started.

Final authored scope is **15 tracked files modified and 12 new files**, plus the pre-existing untracked baseline report preserved unchanged. All changes remain unstaged on the same branch and HEAD. `git diff --check` passes, the Flutter lockfile is unchanged, and the original report hash matches. No credentials/private keys were printed or put in source/fixtures/reports; security fixtures use explicit non-production values. Emulator logs are ignored generated diagnostics, not committed artifacts.

### Security-rules auditor checklist assessment

```json
{
  "score": 4,
  "summary": "The local owner/shared/guest boundary passes the automated rules suite; production migration and operational hardening are still required.",
  "findings": [
    {
      "check": "Authority source / business logic",
      "severity": "minor",
      "issue": "Initial claim relies on a provisioned active device identifier rather than hardware possession proof; exposed unclaimed IDs need an operational claim policy.",
      "recommendation": "Review provisioning/possession requirements before live rollout; do not expose unclaimed identifiers broadly."
    },
    {
      "check": "Storage abuse / operational authorization",
      "severity": "minor",
      "issue": "Pairing and rate-limit records need retention, and per-account limits do not replace multi-replica ingress/account-abuse controls.",
      "recommendation": "Configure reviewed server-only retention and ingress controls separately, preserving role and expiry checks."
    }
  ]
}
```

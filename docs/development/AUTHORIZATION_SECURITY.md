# Phase 1A authorization model and rollout

Date: 21 October 2026. These changes are local and **have not been deployed**. The Phase 0 report remains unchanged. See `PHASE_1A_RESULTS.md` for actual verification outcomes and blockers.

## Trust and roles

The Firebase Admin backend is the sole writer of device ownership, membership, pairing and authorization. User-facing API identity comes exclusively from `verifyIdToken(token, true)` (including revoked/disabled-account checking); body-supplied UID/role/owner fields are rejected. Anonymous Firebase users are guests: device APIs, telemetry/history and controls are denied. Guests may manage only their own bounded profile.

| Principal | View telemetry/history | Controls | Rename | Pair/manage sharing | Remove |
| --- | --- | --- | --- | --- | --- |
| Owner with current membership | Yes | Yes | Yes, global device name | Yes | Own membership only |
| Shared member | Yes | No | No | No | Own membership only |
| Unpaired, unauthenticated, anonymous | No | No | No | No | No |

Removing the owner's membership does not free the device for another claimant, delete the registry/history, or delete shared memberships. The original `owner_uid` is retained; that owner can restore their membership by claiming again. Pairing is disabled while owner membership is absent, and outstanding codes are invalidated. There is no ownership-transfer endpoint. Owner revocation cannot target the owner. A device has at most 50 members, including owner.

## Data contract

- **Private canonical registry:** `/devices/{deviceId}` holds `active: true`, immutable-after-claim `owner_uid`, global `name`, `members: {uid: 'owner'|'shared'}`, integer `auth_version`, and `pairing_epoch`. Clients cannot read or write this document. Claim eligibility requires an explicitly active, provisioned device, unclaimed or already owned by the caller.
- **Display mirrors:** `/users/{uid}/devices/{deviceId}` contains only `name` and `role`. Clients may read their own mirror collection but cannot create/update/delete it. Mirrors are not authorization evidence: history uses canonical registry membership, the API rechecks it, and RTDB sync never reads mirrors. Owner rename updates all mirrors transactionally.
- **Private ingestion credentials:** `/device_credentials/{deviceId}` contains `ingest_key`. All client access is denied. Ingestion reads only this collection, never the old registry key. Existing shared `INGEST_API_KEY` remains an explicit compatibility option; use per-device credentials for isolation. Registered devices must be `active: true`. The pre-existing `ALLOW_UNAUTH_INGEST` bypass is not expanded; it must remain unset/false outside deliberately isolated development.
- **Pairing records:** `/pairing_codes/{sha256(code)}` stores device/owner binding, expiry, epoch, and consumed marker. No client access. The raw code is returned only to the owner and is not stored or logged. Legacy short codes are intentionally incompatible.
- **Rate limits:** `/security_rate_limits/{hash(uid:action)}` is server-only. Firestore transactions enforce 60 API operations/minute/account, 10 validations/minute/account, five code generations/10 minutes/account, five redemption attempts/15 minutes/account. Failed guesses count; restart/replicas do not reset account limits. Redemption attempts are checked before code format/existence. Codes contain 128 bits from cryptographic randomness, live ten minutes and permit exactly one successful redemption transaction. Generating another code invalidates the previous outstanding code. Code expiry/ownership is checked inside the same transaction as membership creation and consumption.
- **RTDB authorization projection:** `/authorization/{deviceId}` holds monotonic `version`, `expires_at` and `members/{uid}/{read,control}`. All client reads/writes are denied, as are all legacy `device_access` writes/reads. State/raw/forecast reads require a registered account, a current read grant and an unexpired lease. Only owners receive a control grant. Parent/sibling/multipath writes cannot bypass the default deny policy.
- **Controls:** mode AUTO/MANUAL, integer fan level 1–5, Boolean mist, integer timestamp between server now minus 60 seconds and plus 10 seconds, exact four allowed fields, non-deletable record. Flutter sends `ServerValue.timestamp`. Admin writes continue to bypass client rules. These remain cloud requests, not physical acknowledgements.
- **Profiles:** only the authenticated UID may access their profile; writes accept only bounded string fields `display_name` (100), `phone` (30), `location` (200), `about` (1000). Existing unknown profile fields must be reviewed/removed during migration or merged updates will fail validation.

Device IDs and API UIDs are restricted to 1–128 ASCII letters, digits, underscore or hyphen, excluding prototype-property names. Standard Firebase-generated UIDs are supported; deployments with custom UIDs outside that alphabet need explicit encoding support before rollout.

## Cross-database consistency and revocation

Canonical registry changes and display mirrors commit in **one Firestore transaction**. RTDB publication follows, outside the transaction callback. A monotonic version and a whole-device ACL transaction prevent a delayed older projection from restoring revoked grants. Default reconciliation interval is **30 seconds** (`ACCESS_SYNC_INTERVAL_MS`); grants expire **90 seconds** from the start of the registry read, rather than being extended by delayed network responses. Do not configure refresh intervals >=90 seconds; setting zero eventually denies all direct RTDB access once leases expire.

The API reports success only after projection synchronization. If Firestore committed but RTDB cannot be reached, it returns **503 `access_sync_pending`**. The client explains that the change was saved and asks the user to refresh, instead of claiming completion or blindly repeating a consumed pairing code. Reconciliation repairs incomplete publication. Firestore history authorization changes immediately. An existing RTDB grant can remain usable for up to the remaining 90-second lease after a failed revocation publication; after successful revocation publication new reads/control writes are denied. Previously downloaded/cached data cannot be recalled. These systems cannot offer a cross-database atomic transaction; outage behavior is explicit and fail-closed on lease expiry.

Out-of-band administrative changes to `active`, ownership or membership must increment `auth_version` and resynchronize. Do not delete a registry document as a substitute for the membership API: a missing registry is denied by Firestore; old RTDB grants expire, but immediate RTDB revocation requires publishing an empty newer ACL. Large installations need batched/event-driven reconciliation and operational monitoring; this phase retains a full registry scan.

## User API

Built-in Node HTTP server, JSON bodies up to the existing 16 KiB limit. `Authorization: Bearer <Firebase ID token>` is mandatory. No UID comes from request JSON. Device ingestion `X-Device-Key` and user ID tokens are separate contracts. Responses are JSON; all successful calls below return 200.

| Method and path | Body | Response / permission |
| --- | --- | --- |
| GET `/api/devices` | None | `{devices:[{device_id,name,role}]}` for caller; no registry or credential fields |
| POST `/api/devices/{id}/validate` | `{}` | `{claimable:boolean}`; bounded account enumeration, no metadata |
| POST `/api/devices/{id}/claim` | `{name}` | `{device_id,role:'owner'}`; active registry + transactional claim |
| POST `/api/devices/{id}/pairing` | `{}` | `{code,expires_at}`; current owner only |
| POST `/api/pairing/redeem` | `{code,name}` | `{device_id,role:'shared'}`; one-use transaction; `name` is validated for API compatibility but the owner's global name is retained |
| PATCH `/api/devices/{id}` | `{name}` | `{device_id,name}`; owner only |
| DELETE `/api/devices/{id}` | `{}` | `{removed:true}`; caller membership only |
| GET `/api/devices/{id}/members` | None | `{members:[{uid,role}]}`; owner only |
| DELETE `/api/devices/{id}/members/{uid}` | `{}` | `{removed:true}`; owner revokes a share |

Error body is `{error: code}` with 400 for invalid input, 401 missing/invalid/revoked token, 403 insufficient role/guest, 404 unavailable resource/invalid code, 409 ownership conflict/consumed code, 410 expired/invalidated code, 429 throttled, 503 pending ACL synchronization, and generic 500 for unexpected service failure. SDK details, tokens, codes and credentials are excluded from user API logs/responses. HTTP 202 from `/ingest/{id}` continues to mean queued, not persisted. Ingestion durability/AQI defects documented in Phase 0 are outside this phase.

The user API has a bounded process-local 120 requests/minute/socket-address throttle before token verification. It deliberately ignores untrusted `X-Forwarded-For`; replicas/reverse proxies need a separately reviewed ingress rate-limit policy. Persistent account limits plus high-entropy codes protect pairing across instances; unlimited malicious account creation/credential stuffing remains an authentication/ingress concern. Existing telemetry endpoints and public health/metrics endpoints are not expanded into a new monitoring/security platform here.

### Flutter configuration

Pass `--dart-define=PURA_API_BASE_URL=https://your-reviewed-backend.example` to `flutter run`/`flutter build`. No default cloud endpoint is guessed. Missing configuration raises a visible service-not-configured error. HTTPS is required except debug-only loopback (`localhost`, `127.0.0.1`, Android host alias `10.0.2.2`). Tokens are obtained from the current Firebase user for each call. Redirects are not followed with the bearer token. Calls time out and map 401/403/validation/expired/used/throttled/server failures to safe messages.

Flutter continues watching backend-written Firestore membership mirrors and permitted RTDB telemetry; privileged writes go through the API. Controls are directly written to RTDB only under owner rules, without the old Firestore cached-state write. Shared users see read-only controls and no rename/pair/share-management actions. API failures do not trigger success notices. The auth gate owns navigation; the former loading-screen timer can no longer navigate around authentication. The existing platform remains Android-focused; this native `dart:io` API transport makes no new web support claim.

For a physical Android device, use its actual `flutter devices` ID. A phone can replace the Android app emulator but **cannot replace Firebase rules-test services**. Do not point adversarial/rules fixtures at production Firebase to work around a local emulator problem. No backend endpoint is automatically exposed over USB or the LAN, and no cloud deployment is authorized by the local configuration example.

## Explicit manual migration / rollout plan — not executed

1. Back up Firestore/RTDB in a secure operator-controlled location and verify restoration. Inventory existing owners using trusted provisioning/ownership evidence. The old user membership paths and old editable registry metadata may have been forged; **never automatically promote their contents into canonical authorization**.
2. Schedule a coordinated maintenance window, block legacy clients/device-management writes and stop the old backend ACL sync. Old apps cannot retain claim/pair/control-writing behavior under the new rules; deploy an explicit app/backend/rules compatibility plan. Do not run the old and new authorization sync implementations together.
3. Install the deny-client registry/credentials/pairing/membership/ACL policy as part of that reviewed rollout. This repository change alone does not update live rules. Old unsafe rules must not remain active while canonical credentials are moved.
4. In an explicit Admin-only migration transaction per device, copy an existing key into `/device_credentials/{id}` using an in-memory SDK value, verify destination equality **without printing the value**, then remove legacy `ingest_key` and any other secrets from the registry. Rotate keys that may have been exposed. The new backend has **no legacy fallback**; coordinate key migration before enabling ingestion. Review shared global-key use and disable it when per-device provisioning is ready. Ensure `active` is an explicit Boolean.
5. Build `members` from verified owner identity and owner-approved shares only, preserving `owner_uid`; assign owner/shared roles explicitly, cap 50 members, initialize an incremented `auth_version` and `pairing_epoch`. Rebuild only safe `{name,role}` display mirrors. Delete/review forged or obsolete mirrors. Do not infer authorization from profile-document presence.
6. Invalidate all legacy short pairing codes. Publish the new versioned RTDB ACLs from canonical devices; legacy Boolean `device_access` values are ignored by new rules and may be removed only under an explicit reviewed cleanup plan. Use a new ACL version/empty ACL to revoke missing/deactivated devices. Verify owner/shared/unpaired denial using an isolated staging setup before rollout completion.
7. Run the unit, Flutter and Firebase rules suites and physical-device owner/share workflows against isolated services. Then an operator can approve a separate deployment. No migration script, rule deployment, backend deployment or production data modification was performed in this phase.
8. Define private collection retention/TTL for expired pairing/rate-limit records as an operational follow-up. Codes are invalid after ten minutes even without cleanup; TTL is for storage management, not authorization. Keep used-code tombstones until expiry so replay gives a clear error.

## Repeatable local tests

Use Node >=24.12 for pinned test tooling (`@firebase/rules-unit-testing` 6.0.0, Firebase JS SDK 13.1.0), Firebase CLI 15.6.0 and Java 21+. Production backend retains its Node >=20 requirement. `npm ci` in `backend/` installs exact lockfile dependencies; `npm run check` checks seven source modules; `npm test` runs backend tests. From `backend/`, `npm run test:emulators` invokes the installed CLI JavaScript entry point directly and runs only the fixed **demo-pura-security** project on loopback Firestore 18080 and RTDB 19000. Set `FIREBASE_CLI_JS` if the pinned CLI is installed elsewhere. The wrapper rejects a missing test-completion receipt so a silent/early CLI exit cannot be mistaken for passing tests.

`test/emulator.test.js` refuses to start unless both emulator host variables equal those exact loopback endpoints. Admin SDK calls use the fixed demo project; client rules contexts use the same namespace. Tests use only non-production fixture identifiers/keys and clear only that isolated namespace. Tests fail rather than falling back to live Firebase. Global CLI installation is a documented prerequisite, not a new production dependency.

### Windows Java socket workaround verified in this workspace

The installed Java runtimes could not open a selector pipe: `Unable to establish loopback connection`, caused by `UnixDomainSockets.connect` / `Invalid argument: connect`. Java 21, IPv4 preference and alternate selector trials alone did not fix it. OpenJDK's pipe implementation can fall back to TCP when it cannot bind its temporary Unix-domain listener. For **one command only**, pointing the Unix-domain temporary directory to a verified nonexistent workspace path enabled that fallback. No system/network settings, SDK versions or security rules were weakened.

```powershell
# Confirm this path does not exist; do not create it for this workaround.
Test-Path 'C:\dev\PuraAir\.java-unix-sockets-disabled'
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:\dev\PuraAir\.java-unix-sockets-disabled'
flutter run -d <physical-device-id> --debug --no-resident
# In a separate command with the same process-local setting:
Set-Location backend
npm run test:emulators
```

The phone run built/installed/launched successfully with this setting. This is a workstation workaround, not a required product runtime setting. Do not persist it globally. Source used to diagnose the fallback: [OpenJDK Windows PipeImpl](https://github.com/openjdk/jdk21u/blob/master/src/java.base/windows/classes/sun/nio/ch/PipeImpl.java).

Primary rules-testing reference: [Firebase rules unit testing](https://firebase.google.com/docs/rules/unit-tests) and [Firestore emulator testing](https://firebase.google.com/docs/firestore/security/test-rules-emulator).

# Native HTTP authentication — milestone 3c

Approved source plan: `2026-10-10-phoenix-native-milestone-3c-plan.md`; ADR-0017. Implementation is in progress; FULL GATE remains controller-owned. No acceptance claim is made here.

## A0 baseline

Source: app `bdaa9aa363230857b5a96fe67eb1e6d10f7390b3`, E2E `ff256e6fd6a8a50f3f05a9e5a1e9656ef5a47b2d`, Elixir 1.20.4/OTP 27. Native standalone, self-hosted, one ordinary synthetic actor without extra data. Counts cover the admitted request, with telemetry retaining counts only. Auth has no connected mount.

Cold browser measurements after network idle:

| Script graph | First-party requests | Decoded bytes | Encoded body bytes | Transfer bytes | Third-party requests |
| --- | ---: | ---: | ---: | ---: | ---: |
| Anonymous | 42 | 1,643,579 | 1,476,024 | 1,488,624 | 0 |
| Authenticated 2FA | 51 | 1,763,010 | 1,507,760 | 1,523,060 | 0 |

The five anonymous GETs and authenticated 2FA GET were measured directly in Chromium. Every remaining response below has identical complete script-block fingerprints to its graph's measured GET. Their graph totals are inferred from that equality, rather than claimed as independent browser measurements. Optional Cloud scripts were not enabled in this dataset; their acceptance measurements remain separate. The proposed HTTP first-party eager cap remains 20 KiB; native LiveView growth remains at most 2 KiB.

| Response state | Status | Repo queries | HTML bytes | Graph |
| --- | ---: | ---: | ---: | --- |
| /users/sign_in | 200 | 4 | 8,296 | Anonymous |
| /users/sign_up | 200 | 4 | 8,714 | Anonymous |
| /users/password/new | 200 | 4 | 7,753 | Anonymous |
| /users/unlock/new | 200 | 4 | 7,722 | Anonymous |
| reset GET | 200 | 4 | 8,216 | Anonymous |
| sign-in failure | 422 | 10 | 9,490 | Anonymous |
| signup failure | 422 | 7 | 9,003 | Anonymous |
| reset failure | 422 | 7 | 8,815 | Anonymous |
| unlock replay | 200 | 7 | 8,313 | Anonymous |
| 2FA show | 200 | 10 | 64,809 | Authenticated 2FA |
| 2FA setup | 200 | 11 | 72,128 | Authenticated 2FA |
| 2FA verify failure | 422 | 10 | 73,315 | Authenticated 2FA |
| 2FA backups | 200 | 12 | 65,689 | Authenticated 2FA |
| OTP initial | 422 | 7 | 7,883 | Anonymous |
| OTP failure | 422 | 6 | 9,050 | Anonymous |
| link challenge | 200 | 1 | 8,413 | Anonymous |
| link password rejected | 422 | 2 | 9,656 | Anonymous |

All rendered states issue a session cookie; setup and backups are authorized one-response secret displays. The baseline probe emitted counts, statuses, byte lengths, cookie-presence booleans and script hashes only. Existing protocol tests preserve action/global CSRF, cookie flags, status/Location, owner headers, pending state, counters and flash. No credential or response-body artifact was captured.

Evidence identifiers: `impl-m3c-a0-baseline` (21 passed, exit 0), `impl-m3c-a0-measure` (35 passed, exit 0), `impl-m3c-a0-measure-corrected` (36 passed, exit 0), `impl-m3c-a0-probe-final` (1 passed, seed 404, warnings-as-errors, exit 0). Temporary probes were removed. Targeted G44 reference: 22 passed / 0 failed / 0 skipped / 0 flaky, exit 0. A preliminary sandbox launch failed at Chromium MachPortRendezvous; the explicitly authorized unsandboxed retry succeeded. Conditional account-link fixture cases were not loaded by this reference environment; D1 must provide active native cases.

## Controller decisions

O1 retains pre-router admission and adds presentation-only controller/HEEx rendering. O2 preserves HTTP chrome with explicit document lifecycles. O3 admits initial OTP session-locale display as Phoenix parity repair. O4 preserves current cache/referrer/head policy. O5 restores configured-provider and credential-visibility parity without widening sign-in GET admission. Cloud lifecycle, API/mobile and whole-app emergency fallback remain outside this milestone.

## Results and test successors

A1 adds `AuthPageController.document/4` and dedicated HEEx root/app templates. Its contract takes an admitted/prepared connection, safe pre-rendered content, status and explicit chrome/token/title options. It does not prepare layout/session again or assign content to the connection. Authenticated callers provide preloaded navbar data. Feature wiring and working HTTP controls remain subsequent tasks.

Named tests: “HTTP auth document preserves response status headers cookie and one-request flash” and “HTTP auth document has no LiveView root or legacy runtime”; anonymous and authenticated shell coverage. RED: `impl-m3c-a1-red`, 0/2 passed, exit 2 (missing renderer). GREEN: 2 passed, exit 0. Double-layout mutation loses inherited flash: 1/2 passed, exit 2. LiveView entry mutation: 1/2 passed, exit 2. Restored direct-caller batch: 39 passed, seed 404, warnings-as-errors, exit 0; expanded/format-final renderer batch: 2 passed, exit 0. Explicit-file formatting exited 0. A2 provides the explicit `auth_http.js` entry and `initializeAuthForms` lifecycle. It reads no credentials, keeps controls enabled for browser serialization, latches one valid submit, restores on pageshow, cleans listeners, and focuses server-declared error summaries. Feature forms acquire its explicit selector during B/C; browser keyboard/navigation acceptance remains D2.

Node names: “HTTP submit accepts Enter or click once without dropping commit or credentials”; “invalid form remains retryable”; “pageshow restores a submitted form”; “error summary receives focus without reading credential values”. Each starts RED (missing module; 0/4, exit 1), GREEN (4/4, exit 0). Named mutations disable controls, bypass validity, omit pageshow reset, admit a second submit, and read a credential value; each fails its named case (exit 1), restored 4/4 exit 0. The new build gate “HTTP auth eager graph fits 20 KiB without a socket or legacy runtime” starts RED without an HTTP entry (7/8, exit 2), becomes GREEN, fails a LiveView-import mutation (6/8, exit 2), and restores GREEN. Final asset/document batch 10 passed, seed 404, warnings-as-errors, exit 0; explicit-file formatting and Biome checks exit 0. Evidence identifiers `impl-m3c-a2-*`.

A3–X3 and controller FULL GATE X5 remain pending.

## Rails bugs fixed (changelog)

none.

## A3 — HTTP chrome

HTTP flash dismissal/expiry, locale dismissal, settings focus, POST/DELETE logout, confirmation cancellation and onboarding controls have explicit listeners and disposal. Changelog and achievement initializers are shared with native hooks, including stale-response cleanup. RED: `impl-m3c-a3-{node,http,widgets}-red.log`; restored GREEN: `impl-m3c-a3-restored-green.log` (25 passed, exit 0, warnings clean), `impl-m3c-a3-node-restored-green.log` (13 passed, exit 0). Mutations `flash`, `locale`, `cleanup`, `cancel`, `widget`, `stale` each exit 1; `signout`, `tabs` each exit 2. Integrated browser sizing remains D2.

## B1 — sign-in/provider/logout

HEEx preserves Devise field protocol, empty rejected passwords and source redirects/statuses. Provider display uses public deployment-policy results and distinct action CSRF; Google/Apple mobile suppression and OIDC-only credential suppression retained. RED `impl-m3c-b1-red.log` plus corrected `b1-fields-red`; GREEN 3 cases; mutations remember/policy/revocation/password each exit 2 with named case failures; restored `impl-m3c-b1-final-green.log`: 80 passed, exit 0, warnings clean. Early retargets: SignInForm exact HTML → source fields/links/translations; AuthHandler exact HTML → source fields/labels/native document; wrong/unknown retains identical status/owner/counters/notice plus source fields. Source fixtures remain unchanged. Remember revocation and password salt revocation remain separate source behaviors.

## B2 — signup

HTTP signup retains invitation readonly email/token, password/confirmation fields, localized errors, no user/outbox intent on validation, policy denial and account update/delete classification. RED `impl-m3c-b2-red.log`: 0/3; GREEN 3/3; corrected confirmation/disabled and classification mutations each exit 2. Initial weak mutations were discarded and assertions strengthened. Restored `impl-m3c-b2-restored-green.log`: 45 passed, exit 0, warnings clean. No domain change or source fixture rewrite.

## B3 — OTP

Initial and repeated failure responses use the anonymous HTTP renderer, with empty code, unchanged counters/completion/remember/cache and approved session-locale display. RED `impl-m3c-b3-red.log` 0/4 exit 2; GREEN 4/4; locale/echo/counter/pending mutations each fail their named test (exit 2); pending mutation also warns about its intentionally unused attribute. Restored `impl-m3c-b3-restored-green.log`: 42 passed, exit 0, warnings clean. OTP FormTest exact markup → source fields/labels/navigation/input constraints; ResponseTest forced English hero → matching seven-locale source fields/title; header/cookie/status/completion cases retained.

## B4a — scoped 2FA operations

`Accounts.Security.manage_two_factor/5` validates admitted scope/server proof and allowed fields, then preserves the existing locked closure and required presentation scalars. Secrets stay in local rendering results; no Account result enters conn state. RED `impl-m3c-b4a-red.log`; GREEN 3 cases; salt/admin/passwordfirst mutations fail named cases (exit 2); corrected fresh-admin mutation replaces a discarded stale-role probe. Restored `impl-m3c-b4a-restored-green.log`: 16 passed, exit 0, warnings clean. B4 templates and browser validation remain pending.

## B4b — native 2FA display

Native authenticated documents and HTTP tabs retain setup/verification/error/backup/disable protocol. Backup values are selectable, wrapped, untruncated and one-column at narrow widths. Secret/URI/codes are function-local rendering arguments. RED `impl-m3c-b4b-red.log` 0/3 exit 2; GREEN 3/3; state/code/chrome/backup mutations each exit 2 with named failures. Restored `impl-m3c-b4b-restored-green.log`: 63 passed, exit 0, warnings clean. FormTest exact HTML → source fields/labels/title/QR and secret/code visibility booleans; ResponseTest exact feature/flash markup → source fields/labels and flash text, retaining all statuses/cookies/cache/title assertions. D2 browser verification pending.

## C1 — recovery templates

HEEx preserves source blank email/credentials, reset capability/PUT override/commit, fields/navigation and seven-locale messages. Labels/errors are explicitly associated with focusable summary. RED `impl-m3c-c1-red.log`: new named failures plus temporary unused alias (exit 3); GREEN four cases. Capability/password/description mutations fail named cases (exit 2). Restored `impl-m3c-c1-restored-green.log`: 27 passed, exit 0, warnings clean. Recovery Form exact HTML → all source fields/navigation/headings/labels/error text; source fixture cases unchanged. C2 document tests were RED against parent HTTP adapter before this commit and GREEN with candidate wiring.

## C2 — recovery lifecycle

Endpoint cases preserve known/unknown/unlocked public notices, post-insert synthetic sealed intent rollback, reset session/remember revocation plus one-use capability, and unauthenticated unlock/replay. RED `impl-m3c-c2-red.log` against parent HTTP adapter before C1 commit: 0/4 exit 2; GREEN included in C1 27-test batch. Notice/enqueue/salt/unlock mutations each 3/4 passed, exit 2, failing the named case. Restored `impl-m3c-c2-restored-green.log`: 83 passed, exit 0, warnings clean, including real mail worker/transaction/expiry/concurrency source corpus. No domain production change.

## C3 — account-link web boundary

Closed HTTP admission/params/dispatch moved to Actions, reducing domain closure and compatibility HTTP module below 300 lines. Operation order and issuer callers unchanged. RED `impl-m3c-c3-red.log` 0/3 exit 2; GREEN 3/3; attempt/MFA/dispatch mutations each exit 2 with named failures. Restored `impl-m3c-c3-restored-green.log`: 43 passed, exit 0, warnings clean. Direct-caller search has no Closure.route references.

## C4 — account-link documents

Both link challenge forms use the anonymous native document and distinct action tokens; one shell alert is consumed on the next request. Token purpose/target/provider UID/replay and MFA sign-in refusal remain unchanged. Four named cases RED at impl-m3c-c4-red (0/4, exit 2), GREEN 4/4; tokens/password/purpose/MFA mutations each fail their named case (3/4, exit 2). Restored impl-m3c-c4-restored-green: 37 passed, exit 0, warnings clean. Exact markup successors preserve source fields, translated card text, head meta values, status/redirect/cookie/cache/flash and blank-password behavior. Source fixtures unchanged. Browser verification remains D1/D2; no Rails defect fixed.

## C4 integration follow-up — native link mail

Active D1 delivery exposed missing runtime enqueue wiring (native POST email returned 503). Native Actions now supplies the existing durable UserCallbacks.link publisher only in native mode, preserving supplied callbacks and legacy opt-in behavior. Worker args exclude the retained URL; existing token/mail/ownership contracts are reused. Named case “native account-link email publishes durable intent without authenticating”: c4-mail-red 4/5 (503), exit 2; GREEN 5/5 exit 0; fake-publication mutation c4-mail-mutation-intent 4/5 (intent count 0 vs 1), exit 2; restored direct-mail batch c4-mail-strict-green 38 passed, exit 0, warnings clean. This repairs Phoenix integration, not a Rails defect. New in-process link tests use a reserved synthetic client IP and clean only their own counter keys, preserving legacy counter characterization. A preexisting compiler inference warning in the dynamic mail claim-key test is handled separately in X2 with equivalent apply/3 dispatch.


## D1 implementation and stage verification

All eleven existing auth specs retain their behavior cases. New active unlock and account-link password/email/MFA cases use owned synthetic fixtures, actual mail delivery and capability redemption. Trace/video/screenshots, ARIA failure snapshots and retries are disabled. Failure wrappers avoid credential/capability equality dumps. Source fixture data remains intact.

E2E commits: `75624c0`, `ecd7a13`, `a488114`, `0c06bad`, `80c9c08`, `71f7f5b`. Historical candidate app `c69c6b529` / E2E `71f7f5b`: all six new D1 cases passed. The combined targeted run was 14 passed, 3 D2 failed, zero skipped/flaky, exit 1; this is not browser acceptance. Baseline RED failed the native-entry requirement before those flows. Browser mutations, final eleven-spec regressions and runtime identity are deferred under the controller's stage-level E2E decision. No milestone browser acceptance is claimed.


## D2 implementation and provisional measurements

Five named probes cover validation/repeated Enter and click with enabled serialized controls, submitter/back retry, keyboard/errors/shell and JS-disabled navigation, stale salt/deletion/lock/pending/demotion, sockets/legacy runtime, and EN/DE 390px text Ranges/full backup readability. E2E `901ce01` and `a322b75` correct pending-navigation automation and the actual mobile focus dropdown; dialog choice/import/track states are included. Syntax checks pass. These latest probes have not been browser-verified under the revised stage-level E2E rule.

Historical app `c69c6b529` / E2E `71f7f5b` passed stale-identity and no-socket cases. The other three D2 cases timed out on test-driver assumptions; no final GREEN is claimed. Cold actual first-party measurements for twelve EN anonymous initial/error states were 2 requests, decoded 3,552 bytes, encoded 1,452, transfer 2,052. Four EN 2FA show/setup/error/backup states were 4 requests, decoded 8,570, encoded 3,264, transfer 4,464. Third-party count was zero. Visible Range counts were 14–25 and 51–62 respectively; document/range/label/readable checks passed before the mobile logout locator timeout. DE and final shell/OTP states were not reached. These are provisional historical measurements, not stage acceptance or Cloud optional-script coverage.


## X1 ownership, graph and failure-log evidence

`NativeAuthIntegrationTest` sends real Endpoint requests for every auth document/error state and strict refusals, with exact effective-method CSRF and native ownership. The callback telemetry probe remains silent; retained API/mobile responses retain their status/JSON/session contract. Historical compatibility callers remain isolated. New synthetic counter keys are cleaned independently of the legacy source oracle.

Named protocol RED failed the legacy root/refusal; root importmap/label/callback mutations each failed their corresponding successor. Callback mutation was rerun alone after an earlier label failure masked it. Graph-growth mutation failed the named budget case; restored isolated batch was 86 passed, exit 0. Final forced failure-log case was RED, GREEN, filter-removal mutation failed, restored integrated batch 93 passed, exit 0 with warnings clean (`x1-final-green`). OTP attempt/backup keys join the existing bounded linear log filter; Rails already filters them (`config/initializers/filter_parameter_logging.rb:9`), so this fixes Phoenix parity only.

Fresh default-build eager graphs: HTTP 6,368 bytes in 2 chunks; native LiveView 345,419 bytes in 4 chunks versus base 344,744 (+675 bytes). The named 20KiB HTTP and 2KiB native-growth tests pass; no transitive legacy/socket/map/studio imports in the HTTP eager graph. Format check passes. Build bytes and historical browser wire bytes are separate measurements; stage acceptance remains pending.

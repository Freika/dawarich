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

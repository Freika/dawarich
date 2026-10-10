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

Pending A1–X3. FULL GATE X5 is reserved for the controller. A1 renderer and A2 document-enhancement tests have initial RED evidence; they are not implemented yet.

## Rails bugs fixed (changelog)

none.

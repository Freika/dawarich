# A12f-4 runtime preparation

Status: preparation only. Coexistence remains the default; `DAWARICH_RAILS=off` selects the existing standalone implementation. No Rails source retirement or final release acceptance is authorized by this package. Last updated: 2026-10-06.

## Prerequisite census

Inspected integration head: `4045f0540`. Integrated Rails 1.15.3 sync: `ad4704b38` (verified ancestor). The other sync merge `1dd02374d` is not an ancestor of this allocation and is not its provenance.

The supplied census originates at `4628a6659/demo-stand`: 375 raw Rails declarations, 374 classified method/path rows, 217 Phoenix route expansions. Historical self-hosted classification: 175 Rails, 195 conditional, 2 native, 2 retired/redirect. Explicit Cloud classification: 186 Rails, 184 conditional, 2 native, 2 retired/redirect. These counts are **not a current acceptance census**. Unset `SELF_HOSTED` remains source-default self-hosted; explicit `SELF_HOSTED=false` is Cloud.

Current declarations were compared with that historical head. `router.ex` now mounts health, metrics, and operator routes; `operator_routes.ex` serves local Swagger and redirects Sidekiq while retiring Flipper. `AuthGate.flows/0` and terminal `Strangler` behavior still select standalone explicitly. `Application.plan/2`, `Release.Lifecycle.mode/1`, and `Standalone.job_entries/1` retain coexistence when the standalone setting is absent.

| Required acceptance | Integrated implementation / named evidence | Final-switch status |
| --- | --- | --- |
| R1 retained routes/envelopes | Standalone merge `15f280db0`; native account/provider, settings and public-share corrections including `0340bd282`, `f5e6f3fe1`, `5e9abaff1`; `StandaloneTest` auth/assets/terminal cases and retained request goldens | Acceptance incomplete: native terminal 422 is not source-success parity. Controller must accept all retained envelopes. |
| J1/J2 producers, accepted payloads and schedules | H02 merge `faacc0616`; `A12f3bH02Test` exhaustive closure, native MAIL and point effects; CACHE merge `c86ff9db1` | H02 reports 78 kinds, 50 native paths, 28 conservative gaps/partial kinds. Preserve all accepted debt; full closure not accepted. |
| L1–3 lifecycle/provisioning/registration | A12h merge `e81131ae7`; `Release.NativeTest` fresh/current/repeat migration, floor, lock, lease, readiness, registration and seed proofs; concurrency correction `55d7ff2cf` | Self-hosted evidence exists. Cloud callbacks/provisioning/registration acceptance remains an owner prerequisite. |
| 3c fences, source drain and DRAIN rollback | A/C/D/P merges `026863269`, `a159efb06`, `b13b2fa7e`, `4045f0540`; `Drain` and `JobDrain` preserve unknown debt; P report audits owner/release boundary | NEW-server/OLD-source deployment and G48/G49 release rehearsal remain pending. SQL zero cannot prove Sidekiq drain. |
| 3o Swagger/metrics/Sentry | Operator merge `baec1fe30`, metric merges `a73a95209`/`89b1f62a2`, Sentry merge `e45c6fb60`; native API-docs, metrics, web/LiveView/Oban/release reporting tests | Integrated implementation is evidence, not collective acceptance or real release serving proof. |

Controller instruction explicitly states these prerequisites are not all accepted. Preparation and focused tests proceed; final default selection and deletion do not.

## Package boundaries and remaining final steps

Package R owns plan A tasks 1–4, 7 and 25. The brief's master-index wording for terminal fallback and self-hosted/source-debt warning maps to A05/A09/A10, owned by T/C. R supplies runtime/lifecycle/registry seams and acceptance handoff; it does not edit their transport or entrypoint files.

After controller prerequisite acceptance and exclusive test-file handoff:

1. Make native lifecycle/default Standalone selection unconditional in both deployment modes and remove Rails lifecycle dispatch.
2. Select the native Front web plan by default; retire direct/proxy/free-upstream plans and RailsServer only after all callers are redirected.
3. Invoke the prepared candidate environment validator at the beginning of runtime configuration, before any effects. Remove old ownership parsing. Shell validation belongs to C.
4. Select the full H02 registry by default without changing owner rows, pins, claimability, identity, locks or replay suppression.
5. Promote T's terminal HTTP/auth/assets behavior and C's native self-hosted/Cloud boot plus source-debt warning. The warning must distinguish G49 source debt from native SQL debt and must not deserialize/delete/import source queues.
6. Transition superseded coexistence assertions only after the controller hands over the listed T/Q test files. Keep all source response/effect/crypto/storage goldens and the retained Rails 1.15.3 oracle.
7. Run gates on that coherent accepted integration head; controller runs integration seed 202 and real G42–49/U1 acceptance. No package green is release acceptance.

Rails sources, fallback plans and existing opt-in configuration are retained throughout this preparation. No allocation values belong in tracked files. The controller report records concrete command/log locations.

## Prepared seams and verification

`Standalone.validate_candidate_env!/1` is a pure, dormant final-candidate validator. It refuses the eleven exact obsolete settings by presence, reports only the variable name and native remedy, and preserves Rails/Rack environment, secrets configuration, Redis selectors, SMTP, Sentry and arbitrary wire/data keys. It is deliberately **not invoked by runtime configuration** while coexistence and standalone activation remain supported.

`Application.runtime_plan/2` respects compile-time `front_runtime: false` in ordinary tests. Manual `plan/2` and `children/1` still exercise the real native listener and parser. Production defaults `front_runtime` to true. Standalone release startup requires public/private lifecycle readiness before caches or supervisor children; explicit legacy Cloud opt-in behavior is preserved until its owner prerequisites are accepted. The isolated release-style probe compiles the same application implementation with front runtime enabled and checks the actual status-3 halt against a pending public ledger inside a private rollback transaction.

| Task / tag | Executable preparation | Mutation proof |
| --- | --- | --- |
| A02 / `a12f4_a02_1` | Standalone lifecycle mandatory for unset/self-hosted/explicit Cloud, including conflicting old lifecycle flags; absent standalone still Rails | M-A02-MODE restores Rails dispatch |
| A02 / `a12f4_a02_2` | Pending public version refuses readiness without schema, ledger, registration, outbox or Oban writes in all deployment modes | M-A02-READY accepts private-ledger-only readiness |
| A03 / `a12f4_a03_1` | Requested native listener has one Endpoint and Drainer, no Rails child or upstream | M-A03-CHILD inserts a second transport listener |
| A03 / `a12f4_a03_2` | Occupied native bind fails terminally; exact listener serves after release of the occupied port | M-A03-BIND supplies an alternate port only on occupied bind |
| A03 / `a12f4_a03_3` | Ordinary test application has no public listener; enabled native startup refuses a pending public version before children | M-A03-TEST ignores compile-time suppression; M-A03-READY removes readiness halt |
| A04 / `a12f4_a04_1` | Candidate validator rejects empty/off/true/synthetic values without echoing them | M-A04-FLAGS omits `DAWARICH_RAILS_ROUTES` |
| A04 / `a12f4_a04_2` | Retained deployment/wire keys remain valid candidate configuration | M-A04-ENV rejects `RAILS_ENV` |
| A07 / `a12f4_a07_1` | Full H02 registry reaches supervised Claimer; pinned source owners/claimability stay unchanged, no Oban work | M-A07-OWNER bypasses the actual Claimer pin predicate for a native command |
| A07 / `a12f4_a07_2` | Idle worker has zero dependencies/producers and normal shutdown; coexistence registry remains opt-in | M-A07-IDLE inserts Repo |
| A25 / `a12f4_a25_1` | Standalone real Endpoint sign-in, unknown HEAD, note create/read and rejected body retain response/effect checks with zero upstream connections | M-A25-DEFAULT empties standalone auth flows |

Each named selector has assertion RED, GREEN, named mutation failure and restored GREEN at seed 404. Already implemented behavior uses characterization RED via its production mutation, rather than claiming new implementation was required. A04 refusal and A03 compile-time test suppression use test-first new-contract RED. The report retains exact command/log evidence and fixture/setup corrections. No final-default test was weakened, skipped or represented as accepted: the preparation selectors explicitly exercise standalone.


The first full seed-404 gate recorded 8989 tests and one existing peer-VM startup timeout. The minimum gate fixture seam in `jobs/two_node_test.exs` bounds private child VMs to two schedulers and asserts their real scheduler count, preserving timeouts, SQL election checks and the characterized same-node double-leader behavior. The existing distinct-node test (`a12f4_gate_peer`) has assertion RED (18 versus 2 schedulers), GREEN, argv-removal mutation failure and restored GREEN; all three original election cases pass. This is a test-resource correction, not a product concurrency change or a timeout extension. Original failing gate logs are retained in the controller report artifacts.

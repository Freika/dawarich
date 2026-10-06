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

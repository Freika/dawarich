# A12h release lifecycle prerequisites

Last updated: 2026-10-05.

This branch implements default-off lifecycle policy, two release DDL workers,
transactional native release-job insertion, standalone ordinary install seeds,
and route hand-back regression tests. It does not enable a live native lifecycle.
The implementation plan is `2026-10-05-phoenix-a12h-plan.md` in the project plans
repository. The implementation report is `SP/orch/out/impl-a12h.report.md`.

## Current command and boot behavior

`DAWARICH_PHOENIX_LIFECYCLE` has a strict policy: absent or literal `false` selects
Rails; literal `true` selects native only for self-hosted configuration. Other
values and Cloud-native configuration are rejected by the policy module.
The current Release, CLI and entrypoint callers do not consume that policy yet.
Setting the flag on this head does not switch migrations or seeds to Phoenix.

The retained self-hosted `docker/web-entrypoint.sh` path is:

1. Bootstrap database selectors, assets, database creation and database wait.
2. `bundle exec rails db:migrate`.
3. `bundle exec rake data:migrate`.
4. `bundle exec rails db:seed`.
5. `dawarich eval 'Dawarich.Release.migrate()'` installs Phoenix/Oban schemas
   and copies registration policy.
6. On success, a server command runs under the Phoenix supervisor with its
   original Puma arguments. On Phoenix migration failure, the existing Rails
   fallback runs. Other arguments retain `exec bundle exec "$@"`.

`docker/release.sh` retains Rails schema migration followed by private Phoenix
migration and registration copy. Cloud stops deploy if that Phoenix step fails;
self-hosted deploy retains its existing fallback notice. Cloud web startup uses
private-schema readiness and retains the Rails fallback. Sidekiq remains real.

`dawarich migrate` still installs only private schemas and registration policy.
`dawarich migrate status` classifies the public ledger without public migration.
`dawarich seeds`, `db:seed` and `db:migrate` aliases await Task 16. The planned
native boot sequence (migrate, seeds, public-aware readiness, Phoenix/Puma) is
pending Tasks 9–10 and 15–19 and is not an operator procedure on this head.

## Implemented source contracts

`ReleaseMigrator.migrate(repo, job_mode: :enqueue)` decodes new version intents
and inserts existing worker changesets through the supplied repo with prefix
`oban`, inside that version's transaction. Raw intents and ledger entries commit
with transactional source effects and native jobs. Delay, queue, priority and
max attempts are retained. Skip records the raw intent only; deferred, invalid
or unknown jobs refuse the version. The default `:record` remains unchanged.

Reentry does not replay historical raw intents or change existing native job IDs,
payloads, schedule or state. The public migrator lease serializes its callers;
this is not complete Release-level or Rails/native exclusion. Nontransactional
source effects can remain after failure, while no version ledger/jobs commit.
Exactly-once insertion per applied version does not promise exactly-once execution.

The standalone seeds preserve source order within each component and whole-table
guards: scoped user emptiness; unscoped country/region/tag emptiness; ascending
scoped users for four default tags. Country loading alone is transactional.
Region loading reuses the existing two-statement load/repair effect and rejects
empty countries first. Tag failures retain earlier rows; a partial tag table
prevents further automatic seeding. Whole-call ordering/exclusion awaits Task 15.

Bootstrap retains database defaults, bcrypt and random API-key generation,
committed creation before self-hosted activation, and Rails calendar expiry.
It reuses the existing TZInfo-compatible `Imports.ZonePeriod` behavior, including
future transition bounds, instead of PostgreSQL's indefinite DST extrapolation.
Admin creation retains authorization before shared persistence. ED-532 suppresses
bootstrap credential logging; clock, salt and random-byte injection is for corpus
tests, with production defaults remaining the real clock and entropy.

## Activation and upgrade matrix

| Case | Current evidence and remaining condition |
|---|---|
| Flag absent/false | Existing Rails lifecycle and fallback remain in production callers. |
| Fresh self-hosted / supported 1.0.0+ schema | Synthetic migrator/job tests and Rails seed corpus prove components; live Release orchestration and real-vector closure are pending. |
| Below product 1.0.0 | Public migrator refuses the missing schema state, including floor 0.37.2. Existing CLI remedy: start Dawarich 1.15.2 once so Rails upgrades it, then retry. Final last-Rails image selection belongs to the release owner. |
| Foreign/newer/non-Dawarich ledger, UTC/pool/lease refusal | Existing public migrator checks remain; refusal before all private writes awaits Task 9. |
| Deferred release jobs | Achievement and import adapters must close Task 6. No restricted upgrade range or substitute workers is accepted. |
| Concurrent native lifecycle callers | Private bootstrap, public DDL, registration copy, seeds and migrate-versus-seeds require a common complete write scope and Release-level race tests in Tasks 9/15. |
| Rails starts after preflight | Observing Rails' advisory lock does not exclude a later Rails migrator, especially during nontransactional DDL. Task 9 exclusion proof is an activation blocker. Operator quiescence is required operationally but is not that proof. |
| Cloud | Native lifecycle remains unsupported; existing Rails deploy/provisioning remains. |

Before activation, close the real achievement release wrapper (countries guard,
missing-region load and bulk/child ownership) and import activity-file backfill
plus track reprocessing adapter. Preserve the import release's 120-second initial
delay and 10-second spacing. Then close complete Release coordination, strict CLI
and shell branching, readiness, real upgrade vectors, C3/C4 and release rehearsals.

Raw intents have no execution/disposition marker and may be offline proof output
or already executed through Rails. Establish a known baseline and resolve any
recorded-but-unperformed work with the release owner's existing jobs procedure.
Do not replay all stored intents. Retain per-key owners, producer fences and
Sidekiq; this slice does not drain arbitrary ActiveJob queues or flip job owners.

## Rollback and verification boundaries

The two independent Task 20 tests prove actual upstream request/body receipt for
`DAWARICH_RAILS_ROUTES` route metadata and `DAWARICH_RAILS_SLICES`, before native
pipelines, with auth configuration and ordinary job-owner reads unchanged. This
is request hand-back. Stateful native-on then Rails-off lifecycle evidence awaits
Task 6 and orchestration; it does not yet prove disposition of pending Oban work.

Older-image rollback requires compatible public DDL/data and an explicit native-job
disposition. G48 remains blocked until the release owner supplies the existing
snapshot/restore procedure. Route hand-back does not restore schemas or cancel
workers. G49 final drain stays with A12d3.

The branch gate for completed work is the existing `resync-check.sh` (seed 404)
and `seedrun.sh` (seed 202), with pinned Elixir 1.18.3/OTP 27, private allocated
DBs/Redis and the existing full-suite slot. The controller owns the third seed.
Scoped tests and named mutations run directly. Reports contain exact results;
this document does not substitute for them.

Release/asset smoke, images, browser/stand checks, C4 and release topology are
**deferred to the controller mini lane**. Schema parity scripts require the plan's
separately authorized existing-script fixes before G47 can run. No activation or
release acceptance is implied by local tests. No AFFiNE synchronization is performed
because this slice touches seeds and credentials.

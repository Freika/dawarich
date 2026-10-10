# A12f-3b cron closure

G01–G04 retain all 24 source schedules in the existing native registry. The
additional hourly native state purge remains independent. This is package
implementation and test evidence; G49 cut-over, source drain, rollback and
deployment acceptance remain controller work.

## Scheduling and ownership

Standalone (`DAWARICH_RAILS=off`) selects the complete registry and schedules
cron in the source ambient timezone: a valid `TZ` takes precedence over
`TIME_ZONE`, whose default is `Europe/Berlin`. Blank or unknown `TZ` values
fall back to that Rails timezone. Rails timezone labels such as `Berlin` are
mapped to IANA names. Oban uses a Calendar timezone adapter over the existing
native `Imports.ZonePeriod` reader and the system zoneinfo files; no new
dependency, SQL connection or Rails process is required for cron validation.
The adapter supports ambiguous and missing local times and the reader's future
transition rules. UTC delegates to the standard library to preserve canonical
DateTime metadata throughout native workers. Production images already install
system tzdata.

Ambient timezone selection follows Fugit's EtOrbi resolver, using the retained
TZInfo zone inventory. Its longest recognized prefix maps `UTC0` to `UTC`,
`GMT-3` to `GMT`, `EST5EDT,M3.2.0,M11.1.0` to `EST5EDT`, and
`CET-1CEST,M3.5.0,M10.5.0/3` to `CET`. The named zone's DST transitions apply;
the trailing POSIX rule text does not override them. Unknown custom names such
as `ABC-5:30` and `ABC3:15:20` fall back to `TIME_ZONE`. EtOrbi numeric offsets
retain their source limits and sign behavior. Named zoneinfo zones retain their
DST gap and overlap behavior. Scheduled instants follow local minute boundaries,
including historical offsets containing seconds; tick identity and grace use
the resulting exact UTC instant.

`Jobs.TickScheduler` replaces ordinary Oban cron admission. The additive
`phoenix.cron_ticks` table has a composite primary key on `(key, tick)`; the
receipt and Oban job commit in one transaction. Completion and job pruning do
not remove tick receipts. Repeated or concurrent leader evaluations cannot
admit the same key and UTC scheduled instant twice. Cron inserts disable the
worker's unfinished-job uniqueness because different ticks must remain distinct,
as they do in Sidekiq-cron. Command and continuation inserts retain their worker
uniqueness. A no-insert result rolls back the admission transaction. A conflict
can retain a receipt only if its stored job has the same worker, cron key and
tick and a runnable state; the stored row is locked until commit. Missing,
unrelated and terminal conflicting jobs leave the tick eligible for recovery.

Boot and Oban database-peer leadership acquisition evaluate immediately.
Evaluation considers only the latest preceding scheduled instant within
Sidekiq-cron 2.4.0's inclusive 60-second grace, after the key's last durable
receipt. The source's strict previous-time rule excludes the current tick
throughout the first second of a local minute, including fractional
timestamps. This matches Fugit's subtraction of one second before truncating
its previous-time cursor. Routine evaluations run just after that boundary.
Older missed ticks are not replayed. Jobs carry `cron_tick` metadata so recovered
nightly, integration and daily-track roots retain the original slot identity.

Coexistence retains the existing UTC scheduler policy. This narrows ED-520 to
coexistence; the controller owns the shared difference ledger. All source cron
entries still disable immediate claim-time catch-up, including archive, clear,
monthly and yearly digest schedules. Missing owner rows still mean Sidekiq,
persisted pins survive claiming, and Lite warning/mail keys transfer jointly.
Failed owner transactions return errors rather than becoming successful claims.
Standalone nightly roots and per-batch reverse-geocoding routes use these same
owner locks. Pins to Sidekiq reject fresh native nightly roots and route fresh
children to the source; already accepted leaves and pending invalidation retain
their existing drain behavior.

Accepted TeslaMate/Trek scheduler wrappers remain visible debt in every
nonterminal state, including discarded jobs. Their completion is required
before replacement cron ownership is claimed. Existing shared source/native
slot receipts and track generation identities remain authoritative.

## Worker behavior

Family invitation cleanup, location expiry and points-counter correction return
transaction failures to Oban. Exact request expiry remains expired, while
invitation cleanup retains the source strict comparison. Pending-import cleanup
returns ownership loss or failure when scheduling a continuation. Required blob
deletion remains retryable; existing shared references survive cleanup.

Daily track sweeps keep per-user savepoints and the Rails rescue behavior. A
replayed accepted slot deduplicates native range children by the existing
slot/user event UUID across all Oban states, retaining already scheduled
children and their original payloads. Explicit commands and later cron slots
keep their own identities.

Archive and clear workers fan out through the Oban instance carried by their
job. Warning markers and native mail remain in one transaction; a rollback is
returned and leaves neither a marker nor mail behind. Digest eligibility,
calendar periods, delivery ownership and accepted continuations use their
existing native implementations.

Nightly cache invalidation is represented by a durable
`Geocoding.NightlyInvalidationWorker` job committed with its receipt, or by the
existing transactional Rails command when the source owns the effect. Redis
eviction happens after commit; enclosing rollback removes the intent and leaves
the cached value intact. Redis deletion is idempotent and worker errors remain
retryable. This small local worker must be consolidated with `AfterCommit.cache`
when the shared after-commit-effects package is integrated.

## Verification

Task-specific contracts live in `test/dawarich/a12f3b_g01_test.exs` through
`a12f3b_g04_test.exs`. G01b reuses the existing slot-sharing test in
`test/dawarich/jobs/schedule_cutover_test.exs`, because it already passed on the
base. Each new named test has actual RED evidence and a failing named production
mutation followed by restored GREEN; G01b has baseline and mutation evidence.
The existing Sidekiq initializer spec characterizes all 24 source definitions
and Berlin winter/summer and explicit-TZ firing times.

Post-hoc cron regressions live in `test/dawarich/jobs/cron_ticks_test.exs` and
`test/dawarich/geocoding/nightly_cron_fences_test.exs`: durable database identity,
completion/pruning/concurrent admission and rollback, exact grace boundaries,
boot/restart and leadership acquisition, Fugit timezone resolution, standalone rollback
fences, and cache intent commit/rollback. Every new named regression has RED,
GREEN, a failing production mutation, and restored GREEN evidence in the
controller implementation report.

Review follow-up regressions cover the real daily worker's midnight/noon overlap,
stored runnable conflict identity, and UTC/historical-second-offset fractional
boundaries. `test/fixtures/cron_timezone_oracle.json` captures Fugit 1.12.2 /
EtOrbi 1.4.0 with Rails' Ruby TZInfo data source and Berlin fallback: 16 ambient
forms and 32 winter/summer scheduled instants. All four new named tests were RED
before implementation, GREEN after it, failed their own named mutation, and
returned to GREEN after restoration. No Rails bug was fixed by these parity
corrections; the Cloud lifecycle refusal remains unchanged.

Review follow-up gates passed: 51 targeted tests with zero failures and one
existing exclusion, forced warnings-as-errors compilation of 1725 files,
whole-tree formatting, and the controller's full seed404 gate with 9482 tests
and zero failures. Existing exclusions/skips are unchanged. No Ruby files
changed; source-oracle probes used the task's isolated resources. Exact logs,
mutation selectors and commit evidence are retained in the controller report.

The controller report records task commits, selectors, logs, peer suites and
final gates. Feature acceptance requires warnings-as-errors compilation, whole
tree formatting, full seed404 through the controller suite-slot script,
targeted changed Ruby specs/lint, redacted leak detection and a clean tree.
Seed202 runs on the integration head under ruling14. No retries, test sleeps,
timeout changes, source removals or owner cut-over are introduced here.

Shared knowledge counterpart: **Dawarich — A12f-3b cron closure** in AFFiNE.

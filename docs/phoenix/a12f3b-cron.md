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
transition rules. Production images already install system tzdata.

Coexistence retains the existing UTC scheduler policy. This narrows ED-520 to
coexistence; the controller owns the shared difference ledger. All source cron
entries still disable immediate claim-time catch-up, including archive, clear,
monthly and yearly digest schedules. Missing owner rows still mean Sidekiq,
persisted pins survive claiming, and Lite warning/mail keys transfer jointly.
Failed owner transactions return errors rather than becoming successful claims.

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

## Verification

Task-specific contracts live in `test/dawarich/a12f3b_g01_test.exs` through
`a12f3b_g04_test.exs`. G01b reuses the existing slot-sharing test in
`test/dawarich/jobs/schedule_cutover_test.exs`, because it already passed on the
base. Each new named test has actual RED evidence and a failing named production
mutation followed by restored GREEN; G01b has baseline and mutation evidence.
The existing Sidekiq initializer spec characterizes all 24 source definitions
and Berlin winter/summer and explicit-TZ firing times.

The controller report records task commits, selectors, logs, peer suites and
final gates. Feature acceptance requires warnings-as-errors compilation, whole
tree formatting, full seed404 through the controller suite-slot script,
targeted changed Ruby specs/lint, redacted leak detection and a clean tree.
Seed202 runs on the integration head under ruling14. No retries, test sleeps,
timeout changes, source removals or owner cut-over are introduced here.

Shared knowledge counterpart: **Dawarich — A12f-3b cron closure** in AFFiNE.

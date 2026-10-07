# Durable after-commit effects

Status: accepted. Date: 2026-10-07.

Writes must persist cache eviction and dependent work in the same PostgreSQL
transaction as their domain changes. `Dawarich.AfterCommit.enqueue/4` inserts
an Oban intent using the caller's repository; `cache/3` inserts the shared
consumer with an operation, payload and UUID. Existing reverse Rails commands
remain transactional rows in `phoenix.rails_commands`. Nothing reaches Redis
or an external Rails executor before these records commit.

The shared consumer rejects an open application transaction. It checks out a
connection and serializes each intent with a PostgreSQL session advisory lock,
without opening a write transaction around Redis. A persistent
`phoenix.processed_commands` marker acknowledges successful execution. An
error or connection exit returns a retryable error to Oban; the consumer has
20 attempts. Its advisory lock is released in an `after` block. Connection
loss releases the database session lock. An outage does not roll back the
already committed domain write or discard its pending intent.

Redis deletion may repeat when a process dies after eviction but before the
completion marker commits. Deletion is idempotent. An incomplete track epoch
attempt uses a fresh generation on retry, so an older attempt cannot resurrect
a generation already superseded by a newer write. Completed intents do not
repeat epoch changes or broadcasts. Native PG Cable batches and their durable
completion markers commit in one transaction through `AfterCommit.once/3`.
This guarantees one committed batch per intent, including owner, family and
share messages, even if an append fails partway through a batch.

Stats calculation and toponym refresh record eviction intents; both stats
workers return calculation errors to Oban. Visit calendar producers queue
`VisitMonthsWorker` in standalone and coexistence modes. Native track changes
queue their epoch and broadcast work. Demo import/destruction record cache
and recalculation intents before their enclosing transaction commits.
Subscription updates and API-key rotation record cache eviction intents with
their writes. API-key housekeeping stores a digest, never a usable key, in
job arguments.

Anomaly arrival locks the user row while changing flags and recording follow-up
jobs. A failed enqueue rolls back both. API point deletion commits counters,
removed-row metadata and dependent intents together. Achievement debounce also
locks the user row before checking for a pending job and preserves the minimum
removed timestamp. Native live broadcasts commit their replay claim with the
complete PG event batch.

Transportation initialization runs after commit and before publishing the track
fanout. Each track records a progress intent with its database change; the
consumer increments Redis idempotently by event and commits its native PG
notification once. A rolled-back track change cannot advance progress.

The alternative of keeping callbacks in process memory was rejected because a
process crash loses them. Running Redis inline was rejected because rollback
and pre-commit readers invalidate the cache/write ordering. Existing Oban and
processed-command tables supply durability without a new schema or queueing
system. The consequence is asynchronous cache visibility: committed values may
remain cached until the worker consumes its intent. Operators use existing Oban
retry and drain tooling; failed intents must be resolved before a runtime drain
is declared complete.

`test/dawarich/after_commit_*_test.exs` contains deterministic rollback,
concurrency, outage, replay and epoch-generation regressions. The AST guard
follows every function clause and local or aliased module calls throughout
`app-phoenix/lib` from transaction closures, and rejects
both direct and indirect cache eviction or epoch changes. Passive cleanup of
an already expired Rails cache entry is excluded because it does not invalidate
values in response to a domain write. Reflection and dynamically selected
callbacks still require review.

Related: the existing Phoenix A1 outbox/job-ownership plans, and the A12f controller review of native point
producers. The implementation report records the individual test mutations and
release-gate results.

AFFiNE counterpart: `Dawarich — ADR-20261007-after-commit-effects — Persist effects with domain writes`
(document `mUh3WnOxB9X3PvgbNqBG-`).

Verification: all 22 named regressions passed, and all 22 named mutations failed
their assertions before restoration passed. Force compilation with warnings as
errors and formatting checks passed. The full seed-404 gate passed 9341 tests
with zero failures through the shared suite runner.

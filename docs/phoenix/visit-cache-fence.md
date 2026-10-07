# Visit calendar cache consistency

The calendar's Redis month entry contains the day and week cells, visit counts,
tracked seconds and aggregate status counts. There are no independent cached
visit-day or aggregate entries in the timeline readers. Native timeline readers
build these values from SQL; coexisting Rails readers cache the month entry.

## Stable producer and consumer API

`RailsEffects.visit_months(repo, user_id, [DateTime.t()]) -> :ok` delegates to
`Visits.Calendar.changed/3`. Call it inside the transaction that changes visit
rows, supplying all affected old and new started-at stamps. Empty lists do
nothing. SQL failure rolls back both the write and its effects.

`Calendar.changed/3` atomically changes each affected local-month token in
`phoenix.epochs` and inserts `Points.VisitMonthsWorker` with unique ISO stamps.
The epoch key is `timeline_visit_month/<user>/<YYYY-MM>/<timezone setting>`.
One token fences both Lite and Pro segments. Source ownership also retains the
existing `visit_months_changed` reverse command for compatibility.
`Calendar.changed/4` accepts `native_owner: true` for an explicitly native archive
restore while keeping `/3` unchanged; that context suppresses reverse commands. Native cache
housekeeping does not depend on that consumer's rescued Redis calls.

`VisitMonthsWorker.run(repo, %{"user_id" => id, "started_at" => [iso]}) -> :ok`
idempotently unlinks affected legacy and current-generation entries after
commit. Its Oban `perform/1` retains failures using `{:snooze, seconds}`. The
persisted `meta.snoozed` count controls exponential backoff from five seconds to
one hour. Snoozes do not consume attempts in the installed Oban. Every failure
logs an operator-visible warning. Deleted users complete without cache work.
Existing Oban views/drain tools expose pending jobs; operators must repair cache
availability or bad payloads rather than discard the intent to claim a drain.

The shared `AfterCommit` primitive was not merged into the integration branch at
this assignment's start. These signatures and payload fields remain stable for
its integration. Preserve SQL generation publication in the writer transaction
and keep eviction in the committed consumer when replacing the enqueue seam.
An asynchronous worker alone does not provide a cache reader fence.

## Reader protocol

Legacy Rails keys remain `timeline_month_summary/<user>/<month>/<timezone>/<lite
or pro>/v3` when no generation exists. Once a token commits, append that token.
The epoch is read from SQL, so Redis outages cannot prevent fencing. Tokens are
opaque and must not be cached across reads. Repeated mutations produce fresh
tokens; rollback preserves the old token. No schema migration is needed because
Phoenix's existing state primitives own `phoenix.epochs`.

Rails `Timeline::VisitCacheGeneration` reads the token without ActiveRecord's
query cache. `MonthSummary#call` captures the key before lookup/build and checks
it again afterwards. When superseded, it repeats with a fresh summary instance,
avoiding stale per-instance memoized rows. Summary SQL also bypasses the request
query cache, so a retried build cannot reuse pre-commit aggregate results. Rails installations without Phoenix
state tables retain their original key shape. Both applications must deploy the
Rails reader change before relying on the fence during coexistence.

Phoenix `RailsCache.get/2` resolves a logical month key and rechecks its generation
after Redis returns. A concurrent change makes that result a miss. Native month
readers currently bypass Redis. Any future cached SQL builder must capture the
physical generation key before reading SQL and fill that same key, never resolve
a new generation after building an old snapshot. Existing `RailsCache.put/3`
serves direct writes, not a read-compute-fill protocol.

Old physical entries can survive until the worker deletes them or their TTL
expires. They cannot satisfy a current logical read. A late old fill can occur
after deletion and remains fenced. Generation records must outlive cache entries;
do not remove a generation while an old key or in-flight fill could still exist.
This guarantees cache freshness for committed writes, not linearizable unrelated
SQL statements under arbitrary transaction isolation.

## Writer inventory

Web single/bulk writes and merges, API create/update/delete/select-place/merge/
batch/bulk writes, detection insertion/wipe/absorption, enhanced imports, area
relabel/dependent deletion, import visit destruction, demo insertion/deletion,
and restored visit insertion publish through the calendar seam. Import destruction
includes every deleted visit in its month stamps, including archive-restored demo
visits; demo exclusion applies only to its orphan-place cleanup. Demo supplemental
point-month cleanup evicts both legacy and current generated month keys. API bulk uses
UPDATE RETURNING stamps so interleaved tombstones/declines cannot inflate the
changed count or invalidate a captured row that was not updated.

Confidence-only rescoring, name enrichment, orphan-place unlinking, and import
reference detachment do not change the cached month cells/counts. Account
removal has its own account cleanup; historical release migrations run under
the release reconciliation contract. Demo visit updates also publish month intents. Their place adoption and orphan
cleanup exclusions are retained; these exclusions do not exempt calendar counts.

## Rails name comparison

`Visits.NameKey.build/1` implements `name.to_s.strip.downcase` with Ruby's ASCII
strip and a generated Ruby 3.4.9 mapping table. It performs no normalization or
additional Unicode case folding. Both merge endpoints use it. Regenerate with
Ruby 3.4.9 using `app-phoenix/scripts/parity/generate_ruby_downcase.rb`; changing
the supported Ruby version requires regenerating and checking endpoint oracles.

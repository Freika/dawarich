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

The calendar producer now calls the shared `AfterCommit.enqueue/4` directly.
Its Oban intent also records the shared user generation, while the dedicated
month generation remains the coexisting Rails reader fence. Preserve both and
the visit worker's indefinite snooze policy. The generic shared worker's finite
retry policy does not replace the visit consumer. See
[after-commit-effects.md](after-commit-effects.md).

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
after Redis returns. It composes the month token with the shared user/exact-key
generation and accepts the shared `resolved: true` captured-key protocol. A
concurrent change makes an unresolved logical result a miss. The shared user
fence may also invalidate unaffected months, preserving correctness at the cost
of additional cache rebuilding. Native month
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
point-month cleanup captures legacy, month-generated and shared-generation
physical keys before publishing `AfterCommit.cache(repo, "keys", payload)`
inside the demo transaction. The committed generic consumer evicts those exact
keys; supplemental failure cannot be swallowed after the domain commit.
Null-island cleanup publishes the timestamps of every deleted visit, including
archive-restored demos; only orphan-place cleanup excludes demo rows. API bulk uses
UPDATE RETURNING stamps so interleaved tombstones/declines cannot inflate the
changed count or invalidate a captured row that was not updated.

Confidence-only rescoring, name enrichment, orphan-place unlinking, and import
reference detachment do not change the cached month cells/counts. Account
removal has its own account cleanup; historical release migrations run under
the release reconciliation contract. Demo visit updates also publish month intents. Their place adoption and orphan
cleanup exclusions are retained; these exclusions do not exempt calendar counts.

## Concurrent detection publication

Runner captures the effective detection policy, owned areas and resolved provider
configuration before computing a batch. Persister takes its per-user advisory
lock when enabled and always locks the user row. Under that row lock, Runner
reloads the active user and compares the captured context before any anchor
trimming or destructive replacement. A deleted user or changed context rolls
back the batch as a skipped range. The settings writer updates this same user
row, so a policy change cannot commit between validation and visit replacement.
No detection result computed under the obsolete policy is published. Redelivery
starts a fresh computation from current settings.

Final cross-batch stitching takes the same user lock, rechecks the captured
context, and locks/validates the returned visit IDs, times, attribution and
active unnoted state before absorption. Stitching and rescoring share that
transaction. A superseded context or replaced/confirmed/noted/deleted input
cannot publish the old stitched output or alter the newer visit rows.
Unrelated NULL-attachable notes retain the existing detection fixture behavior.

When the context still matches, the existing locked window/evidence refresh
widens overlapping machine visits and recomputes changed raw points or segments.
The unchanged-result check preserves the newer visit ID and associations on
replay. Context comparison also checks captured areas and provider configuration
at the persistence boundary; it does not introduce a global provider lock or
serialize all unrelated place/geodata writers. Accepted command timezone and
plan-window arguments retain their existing contract.

The settings-writer regression splits six ten-minute points into two clusters
under a ten-metre/four-point policy, pauses its empty computation, changes the
radius to 100 metres and commits a newer 50-minute/six-point visit. Resuming the
old computation and repeated deliveries preserve the entire visit and all claims
in coexistence and standalone, with advisory locking enabled or disabled.
The older point-only demo cleanup regression now captures the original physical
key, consumes committed cleanup, verifies the bytes are gone and repeats cleanup;
a logical cache miss alone cannot prove physical eviction.

## Rails name comparison

`Visits.NameKey.build/1` implements `name.to_s.strip.downcase` with Ruby's ASCII
strip and a generated Ruby 3.4.9 mapping table. It performs no normalization or
additional Unicode case folding. Both merge endpoints use it. Regenerate with
Ruby 3.4.9 using `app-phoenix/scripts/parity/generate_ruby_downcase.rb`; changing
the supported Ruby version requires regenerating and checking endpoint oracles.

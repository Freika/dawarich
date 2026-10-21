# Durable after-commit effects

Status: accepted. Date: 2026-10-07. Review amendment: 2026-10-07.

Domain writes persist cache generations, eviction intents and dependent work in
the same PostgreSQL transaction. Phoenix readers consult that generation before
using a cache or validating a tile. Redis eviction runs after commit as cleanup.
Worker delay, Redis outage and discarded jobs cannot make an old generation
readable again. The earlier implementation relied on eventual eviction; this
amendment replaces that unbounded visibility contract.

## Shared API

`Dawarich.AfterCommit.cache(repo, operation, payload)` returns `:ok`. It records
an Oban job, UUID and applicable database generations atomically using the
caller's repository. Operations are `stats`, `keys`, `tracks`, `subscription`,
`rate_limit`, `transport_start` and `transport_progress`. Supply `user_id` for
user-dependent entries. `keys` also records generations for its exact keys;
`rate_limit` accepts the retired API key's SHA-256 digest, never its usable key.
The `tracks` operation snapshots serialized created, updated and destroyed
messages inside this transaction. An incomplete tracks delivery attempt re-reads
current committed values for surviving created/updated IDs; the stored message
is retained for a row subsequently deleted. Durable destroyed IDs and the stored
message ordering preserve delivery identity. A successful receipt suppresses
further publication.

`enqueue(repo, worker, args, opts \\ [])` inserts an Oban intent using the same
repository and returns `:ok`. Tile epoch and visit month workers also record the
user's cache generation. Call it inside the domain transaction; the helper joins an existing transaction
and opens one only when necessary. A failure propagates and rolls back
the domain write. The visits write helper should adopt this API rather than
maintaining a second postcommit primitive.

`with_visibility(repo, operation, payload, effect)` records generations and runs
`effect` in one transaction, returning its result. Reverse Rails tile, stats and
visit intents use it while preserving their command kinds and payloads.

Visit month intents serialize distinct timestamps in chronological order at
`Dawarich.Visits.Calendar.changed/4`, for both reverse Rails commands and native
eviction jobs. SQL `UPDATE ... RETURNING` does not guarantee row order, so callers
must not define the payload order. `Dawarich.Places.JobCommands.orphan_places/3`
similarly sorts and deduplicates place IDs before either the reverse command or
native leaf jobs are emitted. Batch name fetching and orphan cleanup already
select places with `ORDER BY id`; other place commands carry scalar IDs. Import
deletion sorts and deduplicates its `places_cleanup` callback IDs in
`Dawarich.Imports.DestroyEffects.visits!/2`; its native dispatcher also selects
places with `ORDER BY id`. The real import worker regression is in
`test/dawarich/imports/destroy_worker_test.exs`. The
producer regressions in `test/dawarich/visits_api/merge_bulk_test.exs` cover
descending duplicate inputs and both delivery paths without relying on query
plans or test seeds.

`once(repo, intent_uuid, effect)` serializes and acknowledges a successful SQL
batch through `phoenix.processed_commands`. The callback must return `:ok`;
errors roll back its SQL completion marker. Native PG Cable appends share that
transaction. Redis Cable broadcasts inside the callback receive stable event
identities derived from the intent UUID, stream and position within that stream.

## Cache visibility

The server-side stale-entry bound is **zero committed writes**: a read begun
after a domain transaction commits cannot use an entry from its previous
generation. User generations live in `phoenix.epochs`, have no expiration, and
roll back with the write. Missing generations retain legacy key compatibility.
Tile validators combine the database generation with Rails-compatible Redis
epochs, so even a discarded track/point eviction intent cannot produce an old
304. Database errors fail the request instead of trusting the old validator.
Existing browser freshness is still `max-age=300, private`; a browser may reuse
its already received response for that interval without contacting the server.

`AfterCommit.Visibility.key(repo, key)` resolves an exact/user-dependent cache
key. Call it before loading the value and retain the resolved key through the
write. Redis-backed native stats/digests and Rails-compatible user summaries,
yearly digests, timeline summaries and insights fragments use generations.
`RailsCache.get/2` resolves these user keys automatically; code that resolves a
key before rendering uses `resolved: true` for both get and put. Generic exact
key consumers can explicitly resolve their key through `Visibility.key/2`.
Do not resolve again after computing an entry: a concurrent commit would attach
precommit data to the new generation. The deterministic warming regression
covers this boundary, including the first transition from a legacy key.

Rate-plan ETS keys use a database generation of the API key digest, resolved
before loading the account. Old entries expire normally; cleanup removes both
legacy and versioned entries. PostgreSQL point-count caches store their captured
generation alongside their counts in a cursor, in one transaction. Counts from
an older generation are recomputed without disabling caching permanently.

Redis eviction may repeat after a crash between deletion and SQL acknowledgement.
Deletion is idempotent. An incomplete legacy Redis epoch cleanup attempt uses a
fresh token; retry cannot restore an older token. A completed intent does not
repeat broadcasts or cleanup. Unreferenced versioned entries expire under their
existing TTLs; asynchronous eviction can additionally remove them.

## Delivery and follow-ups

The shared worker rejects an open application transaction, checks out a
connection and takes a PostgreSQL session advisory lock per intent. It retains
errors for Oban retry (20 attempts). Its lock is released in an `after` block;
connection loss releases the session lock. Operators must resolve failed jobs
before declaring runtime drain complete, even though cache visibility no longer
depends on draining them.

Redis Cable atomically tests a per-event marker, publishes the unchanged Rails
message and records the marker in one Lua execution. A lost response or a later
batch failure retries already delivered messages without republishing them.
Markers have no TTL: deleting them while their intent can replay would remove
the deduplication guarantee. They belong to the Cable Redis database, not the
cache database. Redis must retain its delivery ledger across restarts (persistent
storage/replication and a no-eviction policy for that database). Restoring Redis
to an older snapshot also restores its deduplication boundary; PostgreSQL alone
cannot guarantee external exactly-once publication across a lost Redis ledger.
Unscoped broadcasts retain their existing transport behavior.

Successful legacy `live_broadcast:done:<id>` claims are adopted as consumed SQL
intents without another publication. New failed batches roll back their legacy
claim and SQL marker and remain retryable. Track snapshots apply to newly
recorded intents; already queued ID-only intents cannot recover a deleted row's
historical body. Preexisting `Tracks.NativeChangesWorker` jobs execute the shared
tracks dispatcher using a stable intent derived from their persisted Oban ID.
New writes enqueue only `AfterCommit.Worker` jobs. Drain legacy track intents
before retiring their source rows or removing the compatibility worker.

Subscription family creation/member synchronization intents now commit with
the subscription update. Their reverse ownership, payload and metadata stay
unchanged. Anomaly filtering takes a user-row lock and wraps all flags and
follow-up intents in one fenced transaction for every caller, including archive
restoration. Lease checks between flag/effect stages are retained; a mid-stage
lease loss rolls back the complete filter. A failed enqueue leaves the point eligible for replay. API point
deletion and achievement debounce retain their atomic, user-serialized behavior.

Nightly geocoding records the stats visibility generation with its accepted
cleanup job or reverse Rails command. The native cleanup worker refuses an open
transaction and consumes the accepted eviction directly, without creating a
second cleanup intent or changing visibility again on retry. Eviction is
idempotent; failed executions remain eligible for the worker's Oban retry policy.
The source routing decision stays at the durable producer boundary.

The reverse `stats.caches_invalidated` consumer uses a strict Redis cache store
for user-cache eviction, sharing the configured client, connection pool and
cache options. Redis and pool errors propagate to the Rails command poller,
which retains the accepted command with backoff; only successful cleanup
completes it. This fixes Rails' default cache-store failsafe acknowledging a
failed `UNLINK`. Deleting an already absent key still succeeds, and replay after
partial cleanup converges without creating another intent or generation.
Digest scanning and deletion already raise on errors. The application's ordinary
cache error handler remains unchanged.

Stats workers return calculation failures to Oban. Demo writes record eviction
and recalculation intents before commit. Transportation initialization runs
only after commit; each track records its progress intent with its write. Native
PG messages and Redis event markers prevent completed progress retries from
publishing again.

## Verification and trade-offs

The whole-tree AST guard lives in `test/support/after_commit_guard.ex` and
`test/support/transaction_roots.ex`. It resolves chained aliases, `__MODULE__`, explicit `Elixir` references and literal
module atoms for transaction entry points, calls and sinks, expands pipelines and named captures with their declared
arity, and checks every reachable function clause. Roots include `Repo.transaction`
and repository-variable transactions, `Dawarich.Transaction.run`, and both
callback and module/function/arguments forms of `Ecto.Multi.run`. Run steps are
conservatively checked even when the Multi is constructed before execution.
Statically bound function callbacks retain their caller's aliases and module
through local and remote wrappers, including invocation inside a transaction
closure. Anonymous callback invocations bind their own parameters; caller
bindings are resolved before crossing that scope. Helpers named `transaction`
are followed through their definitions rather than mistaken for repository
entry points. Context maps with runtime-selected callbacks are not expanded.
Ten R1 rejection regressions and the R2 ownership, actual nightly batch,
wrapper census and nested-context regressions cover these forms. Direct and
wrapped post-commit controls remain accepted. The areas controller keeps only
create/update in its write callback so its post-commit destroy action does not
appear transactionally reachable. The expanded production scan found no
additional actual inline eviction site. Passive cleanup of expired Rails cache
entries is excluded; reflection and dynamically selected callbacks still require
review.

Generations add indexed database lookups and coarse user-wide invalidation.
This is preferred to an age limit, pending-job scan, process-memory callback or
inline Redis call because correctness survives terminal job failure and rollback.
The existing epoch/cursor, processed-command and Oban tables need no migration.
Redis delivery markers require retention and capacity planning.

The implementation report records RED/GREEN/mutation evidence and release gates.
Related: Phoenix A1 outbox/job-ownership plans and the A12f native producer review.
AFFiNE counterpart: `Dawarich — ADR-20261007-after-commit-effects — Persist effects with domain writes`
(document `mUh3WnOxB9X3PvgbNqBG-`).

Round-2 verification: twelve named regression mutations failed their assertions
and passed after restoration. The complete seed-404 gate passed 9476 tests with
zero failures. Force compilation with warnings as errors and whole-tree
formatting passed. Existing suite exclusions/skips were unchanged.

Round-3 verification: ten static guard regressions and two nightly merge
regressions each failed before their fix, failed their named mutation, and passed
after restoration. The affected batch passed 50 tests with zero failures. The
complete seed-404 gate passed 9530 tests with zero failures after resolving the
nightly producer/consumer merge seam. Forced compilation with warnings as errors,
whole-tree formatting and the unchanged suite exclusions/skips were verified.

Round-4 verification: the ownership and actual nightly callback rejection
regressions failed against the prior scanner. The 17-entry wrapper census,
nested-context rejection, post-commit control and area dispatch control each
have named mutation/restoration evidence. The affected batch passed 62 tests
and the areas HTTP batch passed five tests, both with zero failures. Six named
mutations failed their selected assertions and passed after restoration. The
complete seed-404 gate passed 9548 tests with zero failures. Forced compilation
with warnings as errors and whole-tree formatting passed; existing suite
exclusions/skips were unchanged.

## Coexistence API point deletion and tile validators

Single and bulk API point deletion commit a user visibility generation with
`points.web_destroy_follow_up`. Native point and track tile ETags read this
generation, so an immediate refresh observes the deletion before the retained
Rails worker rotates Redis epochs. Rollback preserves the previous generation;
the durable follow-up still handles source epochs, statistics, tracks and
achievements.

This ordering matches `Points::Destroyer`, which bumps its tile epoch before
Rails returns success. Deferring the only invalidation makes a changed tile
body carry its previous ETag. MapLibre 6.4.1 discards such a body even after
HTTP 200; changing the request URL alone does not repair the displayed point.
`PointDeleteTileVisibilityTest` warms a tile, deletes through the API controller
and revalidates immediately with the retained worker idle, for both deletion
routes. The G44 point-delete investigation report records the Rails request,
RED/GREEN/mutation and browser evidence. No Rails defect is changed.

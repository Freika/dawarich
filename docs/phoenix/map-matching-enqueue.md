# Map matching enqueue and recovery

The experimental setting is OFF by default. Completion hooks read one boolean
from `:persistent_term` and return while OFF. This applies to default OFF, stored
OFF and an OFF environment pin: no settings SQL, process/task creation, hashing,
state mutation, job insertion or Atlas request happens per completion.

`Experimental.refresh_map_matching/2` resolves the toggle and Atlas URL
prerequisite when the deferred dispatcher boots after Repo and Oban. Successful
native admin writes to either setting refresh that repository's cache before
the response returns. Environment pins retain precedence. A failed boot lookup
fails closed and logs `map_matching.cache_refresh_failed`. The cache is local to
the node; writes made outside that node's native admin path require a refresh or
restart on that node.

Disabled calls leave existing state untouched. After enabling, changed input
clears status, matched geometry and match timestamp before a new claim is
attempted. The disabled full-row Rails parity comparisons remain exact.

## Completion and transaction boundaries

Builder, Recalculator, Reprocessor, Merger, SegmentEditor, native transportation
reclassification and restored Tracks call `Enqueuer.defer/2`. Enabled dispatch
casts to `Dawarich.Tracks.MapMatching.Deferred`; the caller does not wait for the
optional task supervisor. A monitored request process asks
`Dawarich.Tracks.MapMatching.Tasks` to start preparation. The dispatcher abandons
that request after 100 ms, contains supervisor exits/errors and logs
`map_matching.dispatch_failed` with only the track ID. A missing dispatcher is
also contained. A task created after a timed-out request exits without touching
track state because its requester died before authorizing execution.

Inside an existing transaction, the dispatcher retains the successful request
until outer COMMIT telemetry from that repository and caller. ROLLBACK, failed
COMMIT and caller termination abandon it. Registration and transaction outcome
can arrive in either order. Handlers, monitors and timers are removed when the
request finishes. Outside a transaction, successful registration authorizes
preparation immediately, even if the completed operation's caller then exits.
The `[:dawarich, :map_matching, :hook]` telemetry event exposes `track_id` and the
preparation result after execution.

Dispatch is process-local. Claim/job durability begins when background
preparation commits. Node shutdown or optional dispatch failure can lose the
immediate attempt; the enabled sweeper recovers without requiring a claim or
failure marker from that attempt.

## Claim and insertion failures

`Enqueuer.call/2` is the synchronous preparation interface used by the sweeper
and focused tests. It resolves current configuration before accessing input.
Enabled preparation locks the track before loading and fingerprinting input.
Input invalidation precedes the claim savepoint. Pending claim and Oban insertion
remain atomic; insertion errors roll back only that savepoint, preserving the
new digest and invalidated result with `{"enqueue_failed": true}`. An enclosing
operation rollback still rolls back its own input and matching changes.

Every 15 minutes, the enabled sweeper scans non-demo tracks in 500-row keyset
batches: non-pending tracks and pending claims older than one hour. Scanning
non-pending tracks recovers hooks lost before preparation, including changed
input with an old accepted result. The locked Enqueuer leaves unchanged results
and fresh pending claims alone and avoids duplicate active jobs. This adds a
periodic enabled-only input check for existing results; OFF performs no scan.

## Atlas attempts

The worker permits five total failed executions. Its terminal-attempt check sums
`job.attempt` and Oban's persisted `meta.snoozed` count because Basic decrements
the attempt when acknowledging a snooze. HTTP 429 honors Retry-After until the
fifth execution publishes sanitized failed state. Mixed ordinary retries and
snoozes share that limit. Snapshot and publication fingerprint guards reject
stale input; publication preserves recorded geometry and track statistics.

## Verification and decision history

`hooks_test.exs` counts SQL across processes and traces process creation for all
eight operations under default and stored OFF. `experimental_section_test.exs`
proves admin enable/disable changes dispatch without restart.
`dispatch_regression_test.exs` terminates or suspends the optional supervisor in
its own test VM and proves successful Builder return, bounded failure logging,
no late preparation, and sweeper recovery. `review_regression_test.exs` preserves
row-lock/transaction isolation, verifies boot loading of stored ON, real Oban
429 exhaustion and insertion-failure invalidation/recovery.

The strict memory-only OFF gate supersedes the earlier background settings
lookup documented with correction `c7ccc2dc7`. Controller reports retain that
history and the RED/GREEN/mutation evidence.

Canonical shared counterpart: AFFiNE document `cr8zv6tdFe_-zmSsCuu5a`,
“Dawarich — Phoenix map matching enqueue, workers and hooks (package D)”.
No Cloud lifecycle refusal changes.

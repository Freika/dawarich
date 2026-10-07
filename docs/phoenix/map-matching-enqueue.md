# Map matching enqueue and recovery

The experimental setting is OFF by default. Completion hooks add zero SQL on
the track operation's process. An explicit OFF environment override returns
immediately without starting a task. When the setting is unpinned, a background
task resolves the stored instance setting; OFF performs no track, point or
segment reads, hashing, state writes, claims or job insertion.

This supersedes the original package-D rule to fingerprint input even while
disabled. Disabled calls leave existing state untouched. After enabling,
changed input clears status, matched geometry and match timestamp before a new
claim is attempted. The disabled full-row Rails parity comparisons remain exact.

## Completion and transaction boundaries

Builder, Recalculator, Reprocessor, Merger, SegmentEditor, native transportation
reclassification and restored Tracks call `Enqueuer.defer/2`. A supervised task
does the setting lookup, track lock, normalized input loading, fingerprint and
enqueue. Track operations never acquire a map-matching lock or call the error
reporter on their completion path.

When a hook runs inside an existing transaction, its task waits for successful
outer COMMIT telemetry from that repository and caller. ROLLBACK, failed COMMIT
and caller termination abandon the hook. The task detaches its telemetry handler
when it exits. An operation outside a transaction starts preparation immediately
in the task. The `[:dawarich, :map_matching, :hook]` telemetry event exposes
`track_id` and the preparation result after execution.

Dispatch tasks live under `Dawarich.Tracks.MapMatching.Tasks`. Claim and job
durability begins when background preparation commits. Unfinished dispatch is
process-local; a node shutdown before preparation completes can lose that hook.

## Claim and insertion failures

`Enqueuer.call/2` remains the synchronous preparation interface used by the
sweeper and focused tests. It checks configuration before accessing track input.
Enabled preparation locks the track before loading and fingerprinting input.
Input invalidation precedes the claim savepoint. Pending claim and Oban insertion
remain atomic; insertion errors roll back only that savepoint, preserving the
new digest and invalidated result. The remaining state contains
`{"enqueue_failed": true}` for recovery. An enclosing operation rollback still
rolls back all of its own input and matching changes.

The sweeper runs every 15 minutes in 500-row keyset batches. It repairs pending
claims older than one hour and invalidated rows with the insertion-failure
marker. It uses the same locked Enqueuer path and active-job check, so concurrent
hooks and sweeps do not duplicate active work.

## Atlas attempts

The worker permits five total failed executions. Its terminal-attempt check sums
`job.attempt` and Oban's persisted `meta.snoozed` count because Basic decrements
the attempt when acknowledging a snooze. HTTP 429 honors Retry-After until the
fifth execution, which publishes sanitized failed state. Mixed ordinary retries
and snoozes share that limit. Snapshot and publication fingerprint guards reject
stale input, and publication preserves recorded geometry and track statistics.

## Verification and decision history

`test/dawarich/tracks/map_matching/review_regression_test.exs` reproduces the four
review findings: zero caller-query overhead under default OFF, an enabled
builder completing while another connection holds the enqueue lock, real Oban
429 exhaustion, and obsolete-result invalidation surviving failed insertion
with sweeper recovery. The lock test also controls commit and rollback boundaries.

Canonical shared counterpart: AFFiNE document
`cr8zv6tdFe_-zmSsCuu5a`, “Dawarich — Phoenix map matching enqueue, workers and
hooks (package D)”. Controller review/fix reports record RED, GREEN, named
mutations and the seed-404 release gates. No Cloud lifecycle refusal changes.

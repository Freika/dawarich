# Visits and redetection closure

Last updated: 2026-10-07. Package V, Rails 1.15.3 source contract.

## Implemented native journey

The existing visit routes and domain dispatch remain the entry points. The
visit navigation, action and settings gates admit explicit Cloud, self-hosted
and unset deployment modes. No router or Registry activation changes are
included.

| Task | Proven branch |
| --- | --- |
| V01 | Public GET/HEAD redirect, default and explicit empty status, exact Location, no session write |
| V02 | Suggested confirmation with automatic place name, rename, blank name, owned place and demo adoption; source Turbo markup and durable rows |
| V03 | Soft deletion, unchanged points and unrelated place-visit rows, native missing-visit 404 |
| V04 | Date-scoped bulk update and count, duplicate/missing/comma scalar ID coercion, 500-ID limit |
| V05 | Cross-day deletion streams, tombstones, date and source-status filtering |
| V06 | Noted same-day merge with source dependent-note and place-visit destruction |
| V07 | Visits settings GET and PATCH/PUT in all three deployment modes; Ruby integer coercion and unrelated settings preservation |
| V08 | Cloud POST to typed native outbox, no-points notification, real detection fan-out, accepted event identity, completion cooldown and native 429 |
| V09 | Old and new local-month cache invalidation, both plan segments, unrelated month retained, fresh native summary |

Existing source-owner coexistence behavior remains covered by the neighboring
tests. The task aggregate asserts no `phoenix.rails_commands` effects when the
relevant command owners are Oban. Domain visit action errors return native
terminal responses for that selected owner.

## Effects and ownership handoff

`WebEffects.months/3` and the existing `RailsEffects.visit_months/3` API route
through `Visits.Calendar.changed/3`. It locks `command:visits.suggest`:
Sidekiq retains the `visit_months_changed` source command. Native ownership
in coexistence and standalone queues `Points.VisitMonthsWorker` in the same SQL
transaction as the visit write. The job becomes visible only after commit and
invalidates the affected user-local month keys with the existing Redis cache API.
Cache failure fails the worker attempt for Oban retry, without rolling back
the committed visit. Native timeline summaries read SQL while the job is pending. Keys
retain the Rails `timeline_month_summary/<user>/<month>/<zone>/<segment>/v3`
shape for both Lite and Pro. Blank cache timezone uses UTC. MonthSummary reads
native SQL and does not depend on a Rails cache worker.

The one shared production seam is delegation in `rails_effects.ex`, needed
because native visit persister/redetection paths already call that API.
Sibling cache/effect owners must reconcile that delegation and their remaining
direct `visit_months_changed` writers. Global bus, sink and Registry files
remain unchanged.

The full-suite gate exposed old global Cloud-veto assertions in the shared
O02 dispatch and A8 endpoint tests. Their minimum reconciliation admits only
the visits domain in O02's Cloud matrix and makes the A8 source replay cases
select explicit route hand-back. Other domain predicates and pre-pipeline
byte-preserving hand-back checks remain. O must reconcile this shared test
matrix as other domain packages admit Cloud.

`WebSettings.redetect/4` locks the actor row and calls
`HistoryRedetect.enqueue/6`. That producer locks
`command:visits.full_history_redetect`. Its native outbox command is version 1
`visits.full_history_redetect`, with `user_id`, `time_zone` and
`plan_restricted`; metadata carries source producer identity and locale.
The aggregate ID is the actor and the accepted UUID is retained by the existing
RedetectWorker start/month phases. Source-owner requests retain
`visits.web_redetect`.

The hour cooldown follows the source's completion timestamp. No pending-request
deduplication is introduced: Rails permits another request before completion.
Existing worker tests cover event fencing, locks, supersession and partial
month failure. Registry entries remain `claimable: false`; sibling rows 20–22
own producer, cron and release readiness before activation.

## Source capture and parity decisions

The base lacks the exact V01–V09 paths. The execution brief authorizes local
capture while O03–O05 are in progress. Existing map-frame and settings generators
write the nine JSON captures under `test/fixtures/a8vv/visits/` and the V02
HTML result. V02 adds an actual suggested-confirmation request with a distinct
suggested place name; the remaining captures reuse real existing source
request/graph results. No separate fixture driver is added.

Two successful source writes each ran 17 examples with zero failures; their
visit output trees compare byte-for-byte. All 5,712 preexisting fixture files
remain byte-for-byte unchanged. O05/O08 must reconcile these focused generator
and fixture-inventory changes.

Rails keeps the survivor's notes and destroys removed visits' notes. The source
does not concatenate note bodies. Ruling 13 preserves that behavior. The
planned M-V06 mutation “discard the second source visit note” already describes
the oracle, so the source-backed inverse mutation retains the removed note and
fails the named test. Visit notes use the source Note body, without an ActionText
attachment merge invented here.

## Verification and limits

The nine named aggregates each have initial RED, GREEN, a failing production
mutation and restored GREEN evidence in the assigned execution report.
The focused Phoenix batch has 113 tests and zero failures; the source visit
request batch has 67 examples and zero failures. Changed generators pass
RuboCop. The reconciled shared gate batch has 11 tests and zero failures.
Missing renderer dependencies were installed without a lockfile change; its
focused existing tests have three tests and zero failures. The final execution
report records the full seed-404 partition totals,
compile/format, secret scan, commits and service cleanup.

This is the main native journey cut under ruling 15, not release acceptance of
every historical envelope. Global auth/session/CSRF, malformed/repeated query,
format negotiation and generic body handling remain A12f-2/O06–O07 work.
Malformed settings/timezone/container and uncommon error-rendering variants
are not claimed closed by this aggregate. External provider/import effects
remain their callee owners' responsibility.

The residual fleet `Visits::UserRedetectJob` contract is separate from
user-triggered full-history redetection: suggestions-enabled check, per-user
lock, three collision retries at 15 minutes, no user-request cooldown or
completion notifications, and a completion timestamp only if no months fail.
The existing release fleet producer belongs to the
sibling job/cron readiness owner; it is not activated here. Direct remaining
month-command producers and final sink routing need sibling reconciliation.

Seed 202 runs on the integration head under ruling 14. Browser deployment and
Ruby-free release smoke remain the controller's later release gates. Shared
transport, fleet activation and those release gates are not certified here.

AFFiNE maintains a matching focused document titled
“Dawarich — Phoenix visits and redetection implementation”
(`docId: BsApq3bMe4_hiZ9Co4mUq`); this repository
file is the versioned code-coupled counterpart.

## Reconciled arrival-time suggestions (2026-10-06)

`Ingest.Intake` uses `Visits.RealtimeDebouncer` as the sole arrival-time visit
scheduler. `Points.Realtime.visits` and `Points.RealtimeVisitsWorker` are removed.
The Points alternative duplicated scheduling while bypassing the versioned
`visits.suggest` outbox, fixing day steps at 24 hours and always restricting the
plan. The shared Visits path preserves the native worker's dispatch, preference
recheck and debounce release.

The Rails source contract is `Points::ArrivalCommands`'s `visits.realtime`
handler, `Visits::RealtimeDebouncer#trigger`, `VisitSuggestingJob#perform` and
`Visits::Commands.forward_suggest`. Arrival scheduling uses the arrival clock,
not the point's recorded timestamp: a six-hour window ending at arrival, due
five minutes later, with a ten-minute sliding claim. Geocoding and opt-in gate
the claim; failed publication rolls it back. ISO8601 arguments parse in the
user's timezone and use calendar stepping. Restriction follows
`User#plan_restricted?` / `Entitlements#restricted?`, including unrestricted
self-hosted and paid users and inherited family access.

Native scheduling publishes version-one `visits.suggest` with actor aggregate
ID and `Visits::RealtimeDebouncer` producer metadata. Standalone mode selects
native work; coexistence locks `command:visits.suggest`, and Sidekiq ownership
retains `visits.realtime`. SuggestWorker releases the claim before checking
existence and opt-in, so execution permits the next arrival to schedule.

R01 checks the exact payload, scheduling envelope, opt-out and coexistence, and
rejects restoration of either removed Points entry point. R20 exercises delayed
dispatch, visit creation, sliding TTL, claim release, execution-time opt-out,
failed publication and Lite/Pro/self-hosted restriction. Intake covers the
same native payload, historical point versus arrival time, duplicate arrivals
and final-effect rollback while preserving independently committed point
slices and their tile effect. The existing ingest goldens retain Rails' command
order and request/response fixtures.

Reconciliation verification: 79 targeted R01/R20/intake/ingest-golden tests,
30 Rails characterization examples and 8,912 full-suite tests at seed 404 all
pass with zero failures. The full suite retains its existing 11 exclusions and
three skips. Six independent production mutations fail their assertions and
restored targets pass. Forced compilation with warnings as errors, whole-tree
format verification and Gitleaks pass; Swagger and schema show no drift.


## Visit write review corrections (2026-10-07)

Visit transactions atomically publish a fresh SQL month generation and a durable
cache projection. Rails and Phoenix readers consult that committed generation;
legacy and previous-generation entries cannot satisfy a read after the write
becomes visible. Rails checks again after cache lookup/fill, rebuilding from SQL
if the generation changed. A late fill from an older SQL snapshot stays under
its captured older key. The month entry includes all day/week cells and
aggregate status counts. Both Lite/Pro segments use the fence.

Web writes, API writes including bulk status changes, area dependent deletion,
detection/redetection, enhanced imports, import destruction, demo insertion and
deletion, and user-data visit restoration use the common calendar seam. Source
area/import paths no longer bypass it. Native month-cache housekeeping runs even
when the visit producer is source-owned; its reverse compatibility command is
retained. Worker cache failures snooze with durable exponential backoff capped
at an hour and emit an operator-visible warning, without exhausting attempts.

Both merge endpoints accept UTF-8 visit names using Rails' ASCII strip and the
pinned Ruby 3.4.9 lowercase mappings for comparison. They retain first spellings,
join distinct names with `, `, preserve composed/decomposed differences, and
impose no byte limit. U+A7CB remains distinct from U+0264, as in Rails. Invalid
place/area HTML redirects and Turbo maximum-count interpolation remain covered.

The API, generation protocol, writer inventory, and after-commit coordination
contract are documented in [visit-cache-fence.md](visit-cache-fence.md).
Named regressions reproduce the authoritative scoped re-review and the live
count-changing writer omissions. RED/GREEN/mutation/restoration evidence and
release gates are recorded in the controller's fix2 report. The fix3 report adds
the restored import-owned demo deletion worker scenario in coexistence and
standalone, cache outage, immediate pre-drain freshness, durable intent and its
filtering mutation.

### ED-FIX-VISITS-CACHE — durable, fenced month invalidation

Rails loses failed cache invalidations, and its old-snapshot fills can restore a
stale month summary after a write commits. Phoenix commits SQL generations and
retains indefinitely retryable projections. API bulk changes also correct Rails'
callback-free `update_all` cache omission. Demo/restore count changes now retain
month intents even if their old synchronous cache cleanup fails. Import deletion
also includes restored demo visits in its month intents: Rails destroys these
rows but skips their demo cache callback (`EnhancedImport::Destroy`,
`Visit#bust_timeline_month_summary_cache`). Demo orphan-place exclusions remain. The repository
ED/DRB registers are controller-owned; this scoped decision supplies their
reconciliation evidence without editing shared rows.

AFFiNE counterparts were read. The master execution plan forbids delegate AFFiNE
writes for this assignment; controller synchronization remains pending.

## Review follow-up: shared effects and stale suggestions (2026-10-07)

Calendar publication now uses the shared `AfterCommit.enqueue/4` directly,
retaining the transactionally committed month token, source reverse command,
explicit native restore option and visit worker's indefinite snooze policy.
`Points.NativeEffects.enqueue/4` is the shared delegation; the feature's direct
Oban insertion is removed. RailsCache composes the shared visibility generation
with the month fence, retaining generation rechecks and captured-key reads.
Demo importer/destroyer publish supplemental point-month eviction and stats
follow-ups inside their domain transaction. Their keys intent captures legacy,
month-generated and shared-generated physical keys before the generation bump.

Null-island cleanup publishes all deleted visit timestamps, including restored
demos. Its orphan-place exclusion remains. The named archive-worker regressions
cover both modes, a cache outage, committed absence, immediate logical misses,
a durable month intent, consumer recovery and repeated execution.

Detection persistence rechecks the overlapping machine window and reloads all
candidate points and transportation segments while holding its per-user lock.
Changed evidence or boundaries cause recomputation before anchor trimming and
destructive replacement. The user row lock also serializes native persistence
when advisory locking is disabled. Unchanged evidence still preserves visit IDs.
The two deterministic realtime/outbox/dispatch interleavings preserve the newer
50-minute/six-point visit and the same-range seven-point visit respectively.
Settings.load excludes soft-deleted users for admission, suggestion execution,
smart detection and fleet/redetection callers. Accepted workers still clear the
debounce claim before skipping the deleted actor.

Scoped reconciliation: ED-FIX-VISITS-NULL-ISLAND and ED-FIX-VISITS-CONCURRENT in
`app-phoenix/parity/expected_diffs.md`; FRB-051 and FRB-052 in the fixed Rails bugs
register (provisional feature IDs). Soft-deleted admission restores Rails parity
and adds no intentional-difference row. Gate and mutation evidence belongs to
the fix4 controller report. AFFiNE synchronization remains controller-owned
under the master plan's delegate-write restriction.

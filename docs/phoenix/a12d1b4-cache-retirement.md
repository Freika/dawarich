# A12d1b4: cache preheat coexistence

This slice adds durable yearly preheat behind disabled ownership. The historical
filename does not mean cache retirement has happened. Rails and Phoenix still
share the existing cache reader and writer contracts. No ownership is activated,
Redis key removed, public schema changed, or new runtime child installed.

## Ownership and work

`command:cache.preheat_user` and `cron:cache_preheating_job` are both
`claimable: false` and use the existing `projections` queue. There is no native
cleaning command, worker or cron. The Rails job inventory classifies cleaning
as `:retire` for its eventual final role; its current execution stays live.

The native cron checks ownership under the existing lock and inserts a reverse
`cache.preheat_sweep` command. Rails performs the original global country write
once per invocation and fans out source jobs in 500-user batches. Self-hosted
includes all nondeleted users; Cloud includes statuses 1 and 2. Separate nightly
invocations are not collapsed by a new uniqueness policy.
The Rails nightly schedule supplies a `cron` argument, whose enqueue callback
uses the same ownership lock to enqueue only under Sidekiq ownership. Boot,
manual and reverse requests omit that argument and remain unconditional.
Already accepted sweeps retain warming and fanout after ownership transfers.

For either owner, each Rails user job writes years tracked, geocoding counts,
countries, cities and total distance for one day, then runs the original yearly
preheat service, including one-hour snapshots. Only after warming does current
ownership select source completion or native durable work. Forward/rehome/reclaim
retain the original source UUID, ambient Rails zone and due time. Command v1
contains exactly `user_id`, `time_zone` and `source_job_id`; scheduled time stays
in outbox or reverse `run_at`. It does not use the user's saved zone.

Native durable preheat selects the newest two distinct stat years strictly
before the ambient current year. Missing or blank-pattern rows and strictly
older timestamps calculate through the existing repository-aware yearly API.
Equal timestamps are fresh; a nil latest-stat timestamp alone is not stale.
Preheat uses all year's stats, independently of HTTP Lite restrictions. Missing
or soft-deleted users do no work. A service failure stops later years, keeps
earlier saves and logs once without mail; lookup/dispatch/marker failures remain
retryable with the existing three-attempt worker policy.
Diagnostics retain the exception type and fixed safe text. Postgrex errors add
only a validated SQLSTATE; query, detail and arbitrary exception messages are
never logged by native preheat.

Stable forwarded events use existing Processed markers. Calculation and marking
are separate transactions: a crash can recalculate before settlement, and the
existing indexed digest collision handling converges without a new lock or
receipt. Accepted jobs drain after release. An undelegated sweep cancels when
ownership is released; a committed reverse sweep still performs source warming.

## Readers, invalidation and rollback

Warm yearly snapshots, stale snapshots and cached nil retain precedence. Cold
existing yearly rows, corrupt or unreachable Redis, and missing/stale monthly
admission retain their existing Rails hand-back results. No-stat/no-digest stays
native with empty patterns. Admission and LiveView loads remain read-only.
Snapshots, JSON pair ordering, six shared HTML fragments, versions, timestamp
keys, one-day fragment TTL and connected/disconnected write policy stay intact.
Warm country hashes remain authoritative; cold SQL duplicate/fuzzy lookup and
localized stats/unit presentation retain source behavior.

The reverse `stats.caches_invalidated` handler still evicts the specified user's
yearly snapshots, including all timestamp keys for that year. All-scope
invalidation removes all years; other users and their TTLs remain intact.
Rails boot `cache_jobs_scheduled`, version invalidation and Cache::Clean remain
live. Cleaning does not alter preheat ownership or unrelated correctness state.
PointCounts retains its own PostgreSQL lifetime and invalidation rules.

Manual page hand-back uses `DAWARICH_RAILS_ROUTES=insights,stats`. Existing
`digests`, `api_stats` and broad `api` switches keep their independent meanings;
HTTP digest writes and API recalculation stay Rails-owned. Existing operator
`dawarich:jobs:release[<key>]` pins a key to Sidekiq. Pending command work can be
rehomed with `dawarich:jobs:rehome[command:cache.preheat_user]`; dispatched native
work drains. These are existing rollback operations, not an activation step.

## Scheduler difference: ED-500

Both cron strings are `0 0 * * *`, but source TZ/Time.zone/OS resolution and
global Oban `Etc/UTC` can fire at different instants. The source corpus records
Europe/Berlin after `2025-01-01T00:00:00Z`: Rails next fires at 23:00Z that day,
Oban at 00:00Z the next day. After `2025-07-01T00:00:00Z`, Rails fires at 22:00Z
and Oban at next-day 00:00Z. This extends the existing scheduler difference;
carried ambient zone still controls completed-year selection. No global timezone
change or automatic catch-up on claim is introduced.

## Source fates

| Sources | Fate in this slice |
|---|---|
| Cache::PreheatInsightsDigests; Digests.Calculation/Context/CalculateYear/Store | Durable calculation ported into Cache.PreheatDigests using the existing calculator; original warming service retained. |
| Cache::PreheatingJob and UserPreheatingJob | Retained warming/fanout; user job is a forward shim after warming. Native Schedule/SweepWorker delegate through reverse source warming. |
| JobCommands/JobOwnership; RailsCommands Registry/Poller; Jobs Registry/Ownership/Dispatch/Outbox/Relay/Processed | Existing bridges composed with Cache.Commands and CacheEntries; stable identity and pending-only rehome retained. |
| Cache::CleaningJob/Clean/InvalidateUserCaches; cache_jobs initializer and schedule.yml | Retained coexistence boot, operator cleanup and invalidation contracts. Cleaning retirement is inventory-only. |
| User/Country, InsightsController, stats/insights Rails views | Retained shared readers and hand-back sources. |
| Stats/Insights, PointCounts, Details/DetailDigests/CountryCodes, Fragments and six renderers | Retained reader, PostgreSQL lifetime, HTML cache and ordering contracts; characterized without reader changes. |
| Router/PageRoutes/Strangler/Slices/RailsProxy/InsightsGate/Frame/FrameAuth/Visit | Retained route, admission, frame and auth contracts. |
| RailsCache JsonOrder/Wire/Marshal/Snapshot/Value and adapters | Retained active coexistence codecs; no cache adapter removal. |
| Existing stats/details parity generators and Rails/Phoenix fixtures | Extended source oracle and tests; previous corpus/routing cases remain. |
| Recalculation gates/progress/epochs/throttles, raw-data restore, app version PG state, registration toggle, photo/geocoder caches | Adjacent owners; no retirement or state deletion in this slice. |

Post-coexistence work must separately authorize removing yearly snapshots,
country hashes, six HTML caches, source warming and cleanup dependencies, then
replace sweep delegation with native batches. HTTP calculation, residual mail,
activation/drain, migrator boot and physical Rails/Redis deletion are separate
slices. No changed reader result is admitted by ED-500.

Plan: `superpowers/plans/2026-10-04-phoenix-a12d1b4-plan.md` in the project parent.
Named mutations and source oracles cover the disabled seams and coexistence
contracts. Local gate results belong to `SP/orch/out/impl-a12d1b4.report.md`.
Browser characterization, page Track B, stand, image and pooler acceptance are
deferred to the controller mini lane. No AFFiNE writes in this data-exposure task.

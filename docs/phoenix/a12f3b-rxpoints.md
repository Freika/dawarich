# RX-POINTS native effects and HOT handoff

Implemented Plan D R01–R03 against Rails 1.15.3. The execution plan and its master
rulings remain the authority. This package does not establish whole-app
standalone acceptance or consume previously accepted Rails reverse rows.

## Behavior

When `DAWARICH_RAILS=off`, in-range point effects use native Oban children or
native calls regardless of a retained Rails ownership row. During coexistence,
selected native ownership routes to the native consumer; the Rails-owned route
retains its original reverse payload and source quirks.

Point writers persist tile invalidation jobs in their transaction. The consumer
rotates the deployed raw Redis year tokens (UTC, clamped to 1970–2100, or the
`all` sentinel), which existing native tile readers use. Rollback leaves no job.

Arrival publication queues anomaly filtering, live broadcasting and the source
realtime debounce slots. Track debounce uses `track_realtime:user:<id>` (120-second
TTL, 45-second delay); visits use `visit_realtime:user:<id>` (600-second TTL,
300-second delay), geocoding/opt-in guards and a captured six-hour actor-zone
window. Wrappers clear the source claims before invoking existing native workers.
Live broadcasts use the one-day source broadcast UUID claim. Native Cable sends
point and opted-in eligible family envelopes and only active live links; live
shares use the existing PostGIS privacy predicate. Missing and soft-deleted users
are skipped.

Anomaly dependents retain masks, track detachment, fence callbacks, exact affected
local months and queue overrides. `AnomalyStatsWorker` reuses `Stats.CalculateMonth`
with its optional `:invalidated` callback, deleting the source four user-cache
keys and yearly insights pattern. The calculator's default is unchanged for the
RX-STATS owner. Native anomaly backfill preserves source UUIDs, progress/cursors,
leases/fences and Processed replay guards, and queues native rebuild/achievement
children in standalone mode.

Standalone point deletion reuses one native composite from web and API actions.
It invalidates tiles, schedules local stats and affected tracks, and coalesces
oldest achievement timestamps into a pending native job due after 60 seconds.
User scoping, counters and replay of an already deleted point remain unchanged.

Untracked-import scheduling reuses `Tracks.RangeWorker`, with source count >=2,
import min/max, actor zone, untracked-only mode and persistent generation identity.
Import-card refresh checks import ownership before publishing the existing
`Imports.Events` notification used by authenticated native views. Visit changes
invalidate the exact source month/zone/segment keys; native calendar reads remain
current. Area/import Rails callbacks preserve their original timestamp arrays.

## HOT integration

H02 should append `Dawarich.Points.JobEntries.entries()` to the shared registry
entry list. This package deliberately does not edit shared registry or route
files. No HTTP mount is required. The three entries are tested directly, with
version 1 decoding and invalid-payload/version rejection:

| Ownership key | Worker | Payload |
| --- | --- | --- |
| `command:points.tile_epoch` | `Points.TileEpochWorker` | `user_id`, `timestamps` |
| `command:points.live_broadcast` | `Points.LiveBroadcastWorker` | `user_id`, `broadcast_id`, `upserted`, `payloads` |
| `command:points.anomaly_filter` | `Points.AnomalyArrivalWorker` | `user_id`, `start_at`, `end_at`, `time_zone` |

Other ownership keys are existing canonical keys: tracks.generate_realtime,
visits.suggest, tracks.recalculate, stats.calculate_month, points.anomaly_backfill,
tracks.generate_range and enhanced_import.extract_gpx. Standalone producers
insert direct native Oban children, so they already run before H02 mounts the
selection entries. H02 mounting enables normal coexistence claim selection for
the new effect keys.

RX-STATS may reuse or reconcile the optional calculator invalidation callback and
point-domain cache helper. RX-TRACKS owns backfill, tracks_changed,
geocode_recent_points and realtime retrigger; RX-PLACES owns reverse_place.
Those downstream kinds can still appear in this package head and are not
claimed closed here. HOT retains the legacy reverse-kind inventory and accepted
reverse-row disposition. No generic reverse poller or new admission layer exists.

## Verification

New tests are `a12f3b_r01_test.exs`, `a12f3b_r02_test.exs` and
`a12f3b_r03_test.exs`, with named selectors R01k01–05, R02k01–04 and R03k01–04.
Every new name has observed RED, GREEN, a named production mutation failure and
restored GREEN. Retained Rails oracle batch: 27 examples, zero failures (seed 404).
Final execution counts and feature-head gate evidence are in the controller's
RX-POINTS implementation report. Private test allocations are recorded only
there, never in code or this runbook.

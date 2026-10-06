# Native stats and digest effects

R06–R07 retain Rails 1.15.3 period calculations and mail eligibility. In standalone mode (`DAWARICH_RAILS=off`), stats and digest producers choose native execution even when an ownership row remains pinned to Sidekiq. During coexistence, each downstream command retains its ownership choice and Rails reverse payload.

Stats scheduling inserts `CalculateMonthWorker` jobs, preserving the notification flag and delay. Callers with a stable event can pass `event_id` to suppress duplicate publication. Full recalculation publishes `stats.full_recalculation` to the existing job outbox using `source_job_id` as its event identity; the existing worker clears the shared debounce and fans out tracked months.

AirTrail storage claims the accepted event in its transaction and schedules the union of months before and after the sync. Flight dates take precedence; missing dates use the departure timestamp in the user's timezone. Deleted and moved flights therefore invalidate their former months as well as their current months.

Stats calculations, toponym refresh and nightly geocoding call the native cache invalidator when the stats calculation owner is Oban or standalone is enabled. It deletes shared Rails Redis cache keys and scans the exact yearly insights snapshot prefix. The toponym scope retains total-distance and geocoded-point caches; the all scope removes them. Other users and years remain intact. Readers that query PostgreSQL directly need no additional cache.

Digest scheduling inserts the existing monthly/yearly native workers, preserving source timezone and due time. Calculation settles its accepted event once and publishes the existing digest mail command. Publishing mail does not mark the digest sent; the existing enqueue worker checks saved eligibility, queues delivery, then marks sent. The existing failure and sent-at ordering remain unchanged.

No new reverse poller or generic dispatcher is introduced. Existing worker registry entries are reused. HOT retains ownership of final registry and route integration. Other point/import/release packages can use `Stats.Schedule.calculate/6` for monthly fanout; their composite effects remain with their assigned owners.

Execution authority: `2026-10-06-phoenix-a12f-3b-producers-plan-d.md`, R06–R07, and the controller's standalone ruling 15. Test evidence and integration notes are recorded in the RX-STATS implementation report and shared AFFiNE knowledge base.

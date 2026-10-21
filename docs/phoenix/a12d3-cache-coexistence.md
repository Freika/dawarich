# Cache coexistence remains a drain blocker

There are 23 unique native cron mappings and one retained cache-preheating cron.
All remain default off. Cache cleaning is retained in A12d1; no native cleaning cron exists.

The Rails server boot initializer writes `cache_jobs_scheduled` with `unless_exist` and enqueues
cleaning and preheating only when it wins that sentinel. Source cleaning removes the sentinel, version cache
and coexistence projection keys. This behavior is retained with the current keys and TTLs.

Without b4 ownership/state tables, preheating stays in Sidekiq and performs source warming and
digest calculation. With those tables, the current owner controls dispatch. The b4 native sweep
publishes a `cache.preheat_sweep` reverse intent for retained global warming; source per-user
warming precedes dispatch to the native digest worker. Native digest calculation does not retire
the Rails warming prerequisite or guarantee zero reverse backlog.

Cache coexistence removal and the rollback window remain separate controller release decisions.

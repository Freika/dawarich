# Native cache warming

Native user warming populates the Stats country/city/distance summaries, tracked months, point-count projection and completed yearly Insights digests. Summary and tracked-month entries expire after one day; yearly digests expire after one hour. Point counts retain their existing one-day `computed_at` freshness check.

Native Redis entries use the `phoenix/` prefix and a versioned Elixir term payload. They never decode ActiveSupport cache entries. Summary signatures reflect current SQL values, and yearly readers verify current digest and stat freshness before accepting a cached row. Unavailable or corrupt caches fall back to SQL on reads. Warming requires successful writes before marking a command processed, so partial failures remain retryable. The source digest helper's rescued calculation errors retain Rails parity.

The existing stats and point invalidation paths remove both source and native Redis entries. Native Insights reads ignore Rails yearly snapshots. Standalone tracked-month reads use native entries; coexistence retains the source reader for Rails parity.

Controller ruling 8 retires Rails boot sentinel scheduling, self-rescheduling cleaning and Rails-only warming after native reader proof. Phoenix boot does not read the Rails sentinel or create cleaning work. Source cache jobs already accepted still drain. Native warming and consumer invalidations remain. Rails initializer deletion and old-app drain fences belong to later source retirement work.

The CACHE package's named proof is `test/dawarich/a12f3b_c01_test.exs`; sweep and boot proof is `test/dawarich/a12f3b_c02_test.exs`. The shared registry owner applies cache claimability changes after domain tests pass.

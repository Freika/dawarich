# Performance regressions and small optimizations

Date: 2026-10-08. Branch: `feat/phoenix-port`.

## Changes

- `TtlCache.fetch/4`: warm reads remain direct ETS lookups. Cold loads use a node-local, per-key lock and recheck the cache. The callback executes in its caller, preserving Ecto sandbox/transaction ownership. An exception or caller death releases the lock; token-based insertion still prevents an invalidated in-flight result from being republished. The entry-count eviction policy is unchanged.
- `MapApi.PointRecord`: cache the validated points column catalogue for 60 seconds, scoped by repository, dynamic repository and its running PID. Preserve physical column ordering and rejection of unknown schemas. `PointRecord.invalidate/0` (or `/1` for a dynamic repo) refreshes early; during online DDL call this after changing columns, or restart the application. Without explicit invalidation, schema changes may remain cached until the one-minute TTL. Before the ETS cache exists, read the catalogue directly.
- `MapApi.TrackRecord`: a track list fetches only segment IDs, timestamps, indexes and transportation modes. It avoids `ST_DumpPoints(s.path)`, coordinate aggregation and unused detail fields. Track detail continues to return full segment coordinates and fields. This does not address the earlier benchmark's tracks slowdown: that fixture had no segments.
- `MapApi.Points`: convert each query row directly into the final serialized term, eliminating the full intermediate list of maps. Preserve full/slim key ordering, Ruby-compatible floats, ordered nested JSON and pagination metadata.
- `RailsTime`: reuse an active equal-zone context only when the Ecto repository identity is known. Invalidate the marker after a different nested zone or opaque query adapter; clear it on exceptions/exit. Query/transaction adapters without `get_dynamic_repo/0` retain their original behavior. The deferred points serializer establishes its own later context. This removes repeated `set_config` SQL, not a claimed extra SQL `BEGIN` for every nested Ecto wrapper.

These are small code-level optimizations and contract checks, not new throughput measurements. The previous ten-route k6 report retains its frozen source/image/runtime provenance.

## Regression coverage

Thirteen new tests across six files:

| Area | New tests | Coverage |
| --- | ---: | --- |
| TTL cache | 3 | Twenty simultaneous cold callers share one caller-side loader; failed/killed loaders can retry; in-flight invalidation suppresses stale publication |
| RailsTime | 4 | One setup for nested equal zones; later deferred call sets its own zone and preserves DST; different nested zones and thrown callbacks; opaque SQL adapters including adapter-in-Ecto nesting |
| Point schema | 1 | Dynamic repository isolation, early invalidation, unknown-column validation |
| Map reads | 3 | Warm catalogue SQL eliminated; segment geometry omitted only for lists with unchanged detail/timeline; 1000-point full/slim ordering, coordinates and common fields agree |
| Timezone catalogue | 1 | Opaque adapters with only `query!/2` remain supported and are not cached without a known repository identity |
| CLI | 1 | Migration lock loss gets its intended operator error message |

Existing endpoint parity expectations are retained. One existing query-count test now asserts one cold catalogue read and zero warm reads, replacing the old one-query-per-render assumption. Page envelope tests explicitly use a logical-path asset fixture, with digest mapping tested separately. The standalone page fixture uses its original capture instant (2026-10-07 12:00 UTC), so its shared links do not expire according to the test machine's clock. Remember-cookie overflow rejection remains covered by its existing assertions. Compiler compatibility edits for Elixir 1.20 are documented in `elixir-1.20-and-heex-20261008.md`.

## Verification

Artifact directory: `/Users/frey/projects/dawarich/benchmarks/performance-regressions-20261008/`.

- Initial RED: 28 tests, five failures before the corresponding optimizations (`red.log`). Additional nested-adapter RED: 11/12 passed, one failure (`adapter-context-red.log`).
- Core targeted checks: 186 passed, one excluded, including API reads, timezones, cache, CLI, trip note races and job corpus (`targeted-final.log`). Recheck of every module that failed the full compatibility run: 200 passed (`full-failures-recheck.log`).
- Forced application/test-support compilation with `--warnings-as-errors`: passed under Elixir 1.20.4 / OTP 27 (`compile-final.log`). Whole-project formatting check and `git diff --check`: passed.
- Standalone concurrency proof: 20 callers, one loader (`cache-concurrency.log`). Frozen before/after cache sources also reproduce 20 versus one loader on the same Elixir 1.20.4 / OTP 27 toolchain (`cache-proof-before.log`, `cache-proof-after.log`), separating this result from the language upgrade.
- Both production Docker targets build using the new toolchain; release evaluation confirms Elixir 1.20.4 / OTP 27 and `Release.check_runtime_apps!`. Builds are local arm64; other architectures were not built here.
- Final full suite, seed404: **9937 tests, 0 failures, runner exit0**; partitions 2716/0, 3617/0, 3604/0. Existing six exclusions and three skips remain in effect. Maximum partition wall time: 466.9 seconds. Use the final `partitions/` and `full-suite.log` only. Interrupted logs are retained separately: an invalid environment, the pre-adapter-fix RED run, reuse of interrupted fixture databases, and the complete pre-runtime-compatibility run (9936 tests, 16 failures, all addressed by the 200-test recheck). They are not final verification results.

The full-run resources were private PostgreSQL databases and three Redis containers, removed after verification; build images and evidence are retained. The parent's scheduler cap uses `ERL_AFLAGS` so peer-specific `+S 2` remains effective. Fresh databases are necessary after an interrupted run because committed peer fixtures can remain. No remote server access, deploy or push is involved.

## Remaining work outside this change

Byte-budget/oversized-entry cache policy and gradual eviction remain follow-ups. No byte-based RAM bound or cache-leak cause is established. Database profiling remains necessary for points aggregation, tracks geometry and MVT; this change does not claim a new RPS or memory percentage improvement.

## Related documents

- `points-api-performance-20261008.md` — earlier timezone bottleneck diagnosis and optimization opportunities.
- `benchmark-k6-20261008.md` — frozen ten-route Rails/Phoenix benchmark.
- `elixir-1.20-and-heex-20261008.md` — updated runtime and template assessment.

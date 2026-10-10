# Dawarich — Phoenix points API performance diagnosis, 2026-10-08

Repository counterpart: `/Users/frey/projects/dawarich/dawarich/.worktrees/phoenix-port/docs/phoenix/points-api-performance-20261008.md`.
AFFiNE counterpart: https://affine.dwri.xyz/workspace/c309ded7-e11e-4e72-ba6f-aec8a31a740b/NCzOrfmPz_Ho_8zh6HeVn
Artifacts: `/Users/frey/projects/dawarich/benchmarks/phoenix-diagnosis-20261008`. Follow-up to the [2026-10-08 benchmark](https://affine.dwri.xyz/workspace/c309ded7-e11e-4e72-ba6f-aec8a31a740b/NFBRxPyOeWYhshN4xDEqR).

## Established cause

Repeated expensive PostgreSQL timezone validation is a major cause of the native small-page throughput gap. The `/api/v1/points?per_page=100` read path performs **two `pg_timezone_names` validations per HTTP request**. Each materializes/scans the timezone view before filtering to one name. A single isolated EXPLAIN measured 10.331 ms: Function Scan, one result and 598 rows removed by filter; the fallback subplan did not run. See `timezone-plan.json`.

On sequential HTTP requests, the two validations together took **15.89 ms** out of **31.01 ms** mean server time. The points aggregate took 8.86 ms; JSON encoding took 2.28 ms. Under concurrency 16, PostgreSQL reached its two-core limit and query execution plus connection-pool wait dominated latency.

A controlled intervention memoized the **original database-validated result** in the disposable VM, retaining the same timezone normalization/fallback behavior for the fixed fixture. No validation was replaced with an unconditional UTC answer. With identical response contents and unchanged pool/resource budgets, throughput rose from median **58.0 to 171.2 RPS (2.95×)** and p95 fell from **333.1 to 114.4 ms**. Restoring original validation restored slow performance; repeating the memoized variant restored the gain.

Increasing the pool from 10 to 37 without memoization did not help: 51.3 RPS. It shifted waiting into longer SQL execution while PostgreSQL remained saturated. Connection-pool size is therefore not the sole/root cause of the measured slowdown. JSON encoding is a secondary cost in the original small-page profile; this does not rule out serialization or GC bottlenecks on large pages.

## Controlled experiment

Same frozen native image/revision `7e90969a7a4d8ad28b3be24d38754635aac3d9ac` and Rails 1.15.3 image as the benchmark. Each app 2 CPU / 1 GiB; PostgreSQL separate 2 CPU / 1 GiB. Original native pool 10; larger-pool hypothesis 37; no other pool changes. Same private synthetic database, 100,000 points / one active Pro user. Same 71,612-byte JSON page; HTTP/1.1 keepalive, no compression/conditional validators. Fresh application VM for each variant; one-client warmup 3 seconds, sequential profile 4 seconds, concurrency-16 profile 8 seconds. All diagnostic measured requests passed HTTP 200/body-length/OOM checks. Rails contemporaneous comparator: 205.1 RPS, p95 123.9 ms (one short control run).

Order: original Rails/Phoenix; memoized timezone; original larger pool; original restored; memoized timezone repeated. The two original native values were 60.6/55.4 RPS; the two memoized values 171.5/170.9 RPS. A/B results are short local measurements, not production capacity guarantees. Residual difference from Rails remains; not every part of the original performance gap has been explained.

## Measured profile

Concurrency 16, median of two runs where available (larger pool has one run):

| Variant | Runs | RPS | p95 ms | Server mean ms | SQL execution ms/request | Pool wait ms/request | JSON ms/request | SQL calls/request | Timezone scans/request |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Original / pool 10 | 2 | 58.0 | 333.1 | 273.6 | 150.0 | 102.2 | 8.1 | 15 | 2 |
| Timezone memoized / pool 10 | 2 | 171.2 | 114.4 | 92.0 | 40.4 | 24.0 | 16.2 | 13 | 0 |
| Original / pool 37 | 1 | 51.3 | 403.5 | 309.1 | 260.8 | 17.2 | 8.7 | 15 | 2 |

Times are **elapsed wall time**, not exclusive CPU samples. Ecto query_time includes SQL/network/server waiting; queue_time measures waiting for a connection; decode_time is negligible here and retained in raw data. SQL execution and pool waits are summed over sequential calls within each tagged HTTP request. JSON time also includes process scheduling/GC elapsed inside encoding. Raising throughput can raise encoding wall time due to contention; this does not mean the intervention changed the encoder. The same encoder instrumentation is present in all native variants.

Profiling uses native Ecto SQL telemetry, endpoint start/stop telemetry and a narrow JSON encoder wrapper. Only events belonging to `/api/v1/points` HTTP request processes are counted; background/Oban SQL is excluded. Every profile validates its completed endpoint count against successful HTTP responses. SQL **bind values are never recorded**. Instrumentation overhead and shared-host activity limit precision; a nearly threefold repeatable gain plus reversal is the causal evidence.

## Code path and secondary work

At the frozen revision:

1. `app-phoenix/lib/dawarich_web/api/user_zone.ex:22`: a string timezone delegates to `Dawarich.UserTimeZone.name/1` during API setup.
2. `app-phoenix/lib/dawarich/map_api/closure.ex:9`: the map read calls `Account.zone(user.timezone)` again.
3. `app-phoenix/lib/dawarich/account_api/closure.ex:66`: delegates to `UserTimeZone.name` again.
4. `app-phoenix/lib/dawarich/user_time_zone.ex:53`: runs the CTE with subqueries against `pg_timezone_names`.

The original read executes 15 SQL operations per request, including 2 timezone validations, 2 begin/2 commit, 3 set_config calls, per-request point-column introspection, auth/settings reads, the aggregate and the page select. The diagnostic memoization removes exactly the 2 validation queries in steady state. Duplicate timezone resolution is the first fix candidate; transaction/config round trips and schema introspection are secondary candidates requiring their own semantic review.

`COUNT(*) / MAX(timestamp) / MAX(updated_at)` on the selected points is also expensive, but **Rails performs the same aggregate** for its ETag/page headers (confirmed from the actual pinned Rails image's controller, saved as `rails-points-controller.rb`). It is not solely a Phoenix regression. After eliminating timezone scans, remaining DB work and JSON/DTO construction still bound throughput. This diagnosis does not investigate bulk-response OOM, other APIs, LiveView or background workloads.

## Production fix direction and boundaries

Resolve a validated canonical timezone once per request and reuse it across auth/map boundaries. If using cross-request caching, cache a bounded valid IANA set or bounded validation results with explicit environment/tzdata refresh semantics; preserve aliases, invalid-zone fallback, user/env precedence, transaction-local timezone and DST behavior. Do not cache arbitrary unbounded user settings maps as a production implementation.

The intervention here is a **diagnostic VM patch**, not a production implementation: its cache is designed only for fixed synthetic inputs. No application source, API semantics or deployment was permanently changed. All instrumented VMs, private DB/Redis volumes and network were removed after collection. Throwaway scripts and source copies remain only in the explicitly named diagnostic artifact directory. No RPC/SSH to an external server was used.

## Repro and falsifiable signal

`python3 diagnose.py baseline` was actually run and returned **exit 1**: Phoenix/Rails throughput ratio 0.295, below the feedback-loop target 0.667. Requests all passed; the failure was specifically the throughput gap. `verify-signal.py` checks the same saved comparison before and after intervention and records RED → GREEN. The 0.667 threshold is a diagnostic test criterion, not a product SLA or proof of parity.

Reproduce in a fresh copy preserving the original artifacts:

```sh
python3 setup.py > setup.log 2>&1
python3 diagnose.py baseline > baseline-progress.log 2>&1
# exit 1 above is the expected unoptimized symptom; do not chain with &&
python3 diagnose.py cached-zone > cached-zone-progress.log 2>&1
python3 diagnose.py pool37 > pool37-progress.log 2>&1
python3 diagnose.py baseline-repeat > baseline-repeat-progress.log 2>&1
python3 diagnose.py cached-zone-repeat > cached-zone-repeat-progress.log 2>&1
python3 verify-signal.py
python3 report.py
python3 cleanup.py
```

Setup refuses existing benchmark names and uses a local Unix Docker context. The environment contains generated private synthetic secrets; never publish it. `profile-start.exs`, `respond.ex` and `user_time_zone.ex` provide the instrumentation/intervention; app source copies are from the frozen benchmark source. Runtime redefinition warnings are expected only in these temporary VMs. Raw request/profile/resource records are `*-c1.json` / `*-c16.json`; all SQL times/counters, HTTP statuses and cgroup states are retained. `profile-summary.json`, EXPLAIN plan and progress/server logs retain the evidence. The original 48-run benchmark remains unchanged.

## Permanent fix — 2026-10-08 follow-up

The earlier diagnostic intervention was confined to disposable VMs. The production working tree now caches PostgreSQL's accepted timezone catalogue in `Dawarich.TimeZoneNames`, using the existing bounded TtlCache, a one-hour TTL, per-dynamic-repository/process keys, and serialized cold loads. `TimeZoneNames.invalidate(repo)` forces refresh; migration callers work before the cache starts. Settings and environment remain uncached; PostgreSQL still calculates offsets and DST.

`UserTimeZone.name/1..3`, `iana/2..3`, `query!`, `MapWindow`, and `Visits.WebScope` share that catalogue. Existing fallback differences, aliases, blank/invalid zones, parameter positions, DST overlaps/gaps remain covered. The native Docker target also copies `app/assets/svg`: real authenticated HTML preflight found missing icons causing 500 errors.

54 relevant regression tests pass. New name and warmed-window no-catalogue-SQL checks each fail against the corresponding original implementation (expected RED controls). A no-cache-startup check passes. Ten production probes return 200; five API payloads match (semantic JSON and byte-identical MVT).

The fresh 10-route k6 comparison is complete: 160 unique phase trials, 512 MiB and 1 GiB app limits, 2 CPU each, separate 2 CPU/1 GiB PostgreSQL, no swap, two reversed-order repetitions. All 80 lower-rate trials pass. Same-image resolver control increases points API delivered throughput from 29.9 to 84.4 RPS (2.82×); both variants were overloaded at the offered 300 RPS, so this is a controlled intervention result, not maximum sustainable capacity. Initial HTML p95 is 1.71–2.25 times lower and mean working set 3.61–3.84 times lower in Phoenix. Points reads still saturate PostgreSQL under higher load; tracks API remains slower, and dense MVT overload fails in both implementations. Full results: [Dawarich — fixed Phoenix vs Rails — k6 10-route benchmark — 2026-10-08](https://affine.dwri.xyz/workspace/c309ded7-e11e-4e72-ba6f-aec8a31a740b/xazZ2Mixb70XF2jcZAPmH), repository `docs/phoenix/benchmark-k6-20261008.md`, artifacts `/Users/frey/projects/dawarich/benchmarks/rails-phoenix-fixed-20261008`. Calibration and the rejected-host control are excluded. Temporary benchmark containers/network/volumes and local regression databases are removed. The patch remains uncommitted.

## Small performance and memory opportunities — 2026-10-08

Assessment of the fixed working tree after the k6 comparison. These are proposed changes, not implemented optimizations or measured application gains. One additional isolated concurrency reproducer was run; no load test or benchmark container was restarted.

| Priority | Candidate | Evidence and expected benefit | Boundaries |
|---|---|---|---|
| 1 | Serialize cold loads in TtlCache.fetch | claim/1 treats a live {key, token, :loading} marker like an expired entry and replaces it, allowing every caller to become a loader. Actual reproducer: 20 concurrent callers to one empty key invoke the callback 20 times; desired count is one. Avoid duplicate expensive computations/queries and simultaneous result allocations on cold/expired keys. | Preserve caller/Sandbox context, failed/dead loader recovery, cancellation, cache_nil:false and invalidation. This demonstrates duplicated work, not 20× application throughput. TimeZoneNames already avoids this fetch behavior through its own lock. |
| 2 | Cache PointRecord.columns metadata | PointRecord.columns/0 reads pg_attribute and verifies the column set on every points request, including slim reads. A repo-scoped validated metadata cache removes one catalogue query from warm requests. | Keep unknown-schema rejection, database/dynamic repo isolation, migration invalidation or bounded TTL and cache-free startup. No estimated percentage gain. |
| 3 | Separate timeline-only vs full segment queries | TrackRecord.features(rows,false) returns mode_timeline but still fetches segment path coordinates, distance, speed and confidence. Segments.timeline only needs times/indices/duration/mode. Avoid ST_DumpPoints/jsonb aggregation, transfer/decoding and allocations for omitted segment geometry in list responses. | Preserve all fields for features(...,true). Most benefit expected for actual tracks with many segments/vertices. Benchmark fixture has NO segments: this cannot explain its measured tracks regression. |
| 4 | Reuse active same-zone SQL context | Closure.read and MapApi.read both call RailsTime.with_zone; each wrapper unconditionally sends set_config. The lazy points serializer opens a later context after the outer transaction has completed. | Remove only repeated setup within the same active repo/connection/timezone. Keep the later lazy serializer's own context. Nested Ecto calls do not each imply a separate SQL BEGIN; do not claim they do. |
| 5 | Fuse points row conversion and serialization | Points.rows builds a complete list of maps, and its caller builds a second list of PointRecord terms before JSON encoding. Convert each result row directly to its final term, reducing simultaneous intermediate maps/lists and GC pressure. | Largest expected benefit for large per_page, not necessarily the benchmark's 100-point page. Preserve ordering, slim/full behavior, ordered JSON, float formatting, headers and ETags. Do not replace the compatibility encoder with Jason indiscriminately. |

Additional memory hardening: TtlCache limits entry COUNT to 10,000, not retained bytes, and clears all entries at capacity. Large values can exhaust RAM before that count; gradual eviction, oversized-entry limits and a byte budget are worth considering. This is a design risk visible in code, not a measured cache leak or the proven cause of tracks OOM. Large structured ETS values also cost allocations during lookup; large reference-counted binaries require separate accounting.

The largest remaining measured bottlenecks are database work for points/list/MVT and the tracks API. Treat geometry SQL rewrites, aggregate/ETag caching and new indexes as profiling-led follow-ups rather than guaranteed easy wins. ST_AsGeoJSON is a potential alternative to manually aggregating geometry coordinates, but its default precision differs; coordinate/empty/NULL/dimension compatibility requires verification.

Suggested order: cache load coordination → schema metadata cache → segment projection and fused point conversion → repeated zone setup with transaction tests. Validate changes individually with warm/cold SQL counts, exact API parity and large-geometry/large-page allocation measurements before rerunning the entire ten-route matrix.

Evidence: /Users/frey/projects/dawarich/benchmarks/performance-opportunities-20261008/ttl-cache-concurrency.exs and ttl-cache-concurrency.log. Command: `elixir ttl-cache-concurrency.exs` from that artifact directory. Actual exit 1 is the expected current concurrency defect; output is `%{concurrent_callers: 20, loader_calls: 20, expected_loaders: 1}`.

Primary references: [Ecto nested transactions](https://ecto.hexdocs.pm/3.13.5/Ecto.Repo.html#module-nested-transactions), [OTP 27 ETS object copying](https://www.erlang.org/docs/27/apps/stdlib/ets.html), [PostGIS ST_AsGeoJSON precision](https://postgis.net/docs/ST_AsGeoJSON.html).


## Implemented follow-up — regression tests and small optimizations

The five opportunities above are now implemented with regression coverage; the `20 -> 20` loader output describes the pre-fix assessment. The same proof now produces 20 callers and one loader. See `performance-regressions-20261008.md` for the implementation, invalidation/transaction contracts, RED/GREEN evidence and current validation. Elixir also moves to 1.20.4: `elixir-1.20-and-heex-20261008.md`. The earlier benchmark remains unchanged and does not measure these additional changes.


Final follow-up verification: 13 new tests; full Elixir 1.20.4 / OTP 27 suite, seed404, **9937 tests, 0 failures**, runner exit0 (2716/0 + 3617/0 + 3604/0; six exclusions and three skips unchanged). Forced compilation with warnings-as-errors and formatting pass. Both arm64 Docker targets build and pass release runtime checks. The cache's frozen before/after sources on the same new toolchain reproduce 20 versus one loader for 20 simultaneous callers. No new HTTP benchmark or percentage RAM reduction is claimed. Temporary test databases and Redis instances are removed; retained logs are in `/Users/frey/projects/dawarich/benchmarks/performance-regressions-20261008/`.

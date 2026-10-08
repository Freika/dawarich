# Dawarich — fixed Phoenix vs Rails — k6 10-route benchmark — 2026-10-08

AFFiNE counterpart: https://affine.dwri.xyz/workspace/c309ded7-e11e-4e72-ba6f-aec8a31a740b/xazZ2Mixb70XF2jcZAPmH

Repository counterpart: `/Users/frey/projects/dawarich/dawarich/.worktrees/phoenix-port/docs/phoenix/benchmark-k6-20261008.md`.

## Scope and reproducibility

Exactly 10 distinct GET scenarios: five authenticated initial HTML pages and five API URLs. The same generated Rails session is used for both implementations. Requests repeatedly read one synthetic user and fixed windows, so warmed internal application caches are part of the workload; multi-user/cache-miss/write traffic is not modeled. This measures server-side initial HTML and HTTP API work; assets, browser JavaScript, network geography, and LiveView WebSocket interactions are outside the test. JSON APIs have semantic equality; the non-empty dense MVT responses are byte-identical. HTML payloads differ between renderers, so this is an application comparison rather than a language microbenchmark.

Application limits: 512 MiB then 1 GiB, 2 CPU each, swap disabled. Apps run individually against the same separate 2 CPU/1 GiB PostgreSQL 17/PostGIS 3.5 instance; Redis has 128 MiB. Rails 1.15.3 / Ruby 3.4.9 + YJIT, two Puma workers × five threads. Phoenix production native release / Elixir 1.18.3 + OTP 27, two schedulers, DB pool 10. Client: official Grafana k6 2.3.0 binary, 2 CPU / 512 MiB, 32 preallocated VUs with a hard maximum of 32. Apple M5 Pro, ARM64 OrbStack VM; macOS and user applications remain active, so this is not a dedicated laboratory host.

Synthetic fixture: 100,000 points, 40 tracks (two-coordinate original paths, no segments), 40 visits, 20 trips, 20 imports, one monthly stat. Points are concentrated in the Berlin viewport. Complex real track geometries and multi-user distributions are not modeled. Rails schema plus native additive migrations; VACUUM ANALYZE precedes measurements. This fixture differs from the earlier points-only benchmark, so historical absolute RPS are not a controlled before/after comparison.

k6 uses the open-model constant-arrival-rate executor: request starts do not wait for previous responses. Each case gets a fresh app process and five seconds of low-rate warmup, followed by 20 seconds at a common lower offered rate and 15 seconds at a common higher offered rate. Both RAM caps, both implementations, two independent repetitions; app and endpoint order reverse in repetition two. The initial pilot is preserved under pilot/ and excluded from every final table. Source is frozen; provenance.json records image IDs, runtime-file hashes and the patch digest.

Lower offered rates (RPS): HTML pages 10; points API 50; tracks API 5; stats/visits APIs 20; MVT 2. Higher rates: HTML 100; points API 300; tracks API 100; stats/visits APIs 200; MVT 8. Higher-rate trials measure delivered successful RPS at this exact configuration, not maximum sustainable capacity. Missing arrivals are reported as dropped_iterations; latency for completed requests alone does not include them.

Each request checks HTTP 200 and the expected non-empty fixture (100 points, 40 GeoJSON tracks, 40 visits, 100,000 points in the summary, non-empty MVT, authenticated HTML and list markers). HTTP errors, assertion failures, cgroup oom_kill increments, container OOM/death, dropped iterations and p95 are retained. The exploratory passing objective is zero errors/drops/OOM and p95 < 1 second; this is not a production product SLO. Quantiles are median-of-run-quantiles, not pooled quantiles. Low-rate MVT has only 40 successful samples per repetition: p99 is descriptive and poorly resolved. These are bounded exploratory load/stress tests, not a soak test or a confidence interval. The short per-case warmup may leave Ruby YJIT/GC settling; higher-rate trials follow the lower-rate trial and are more warmed, so compare implementations within the same phase rather than interpreting a cross-phase latency decrease as a load benefit.

CPU and memory are sampled from cgroup v2 once per second for app, DB and client. 100% CPU means one full core. Memory is working set (memory.current minus inactive_file); the exact kernel peak since app restart is also retained. CPU ms/request includes app + DB and excludes generator; cgroup sample/exec overhead is part of the observed windows. Background workloads are absent; native in-process queue services remain enabled, while a separate Rails Sidekiq process is not included.

Guidance: [k6 constant arrival rate](https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/constant-arrival-rate/), [open and closed models](https://grafana.com/docs/k6/latest/using-k6/scenarios/concepts/open-vs-closed/), [dropped iterations](https://grafana.com/docs/k6/latest/using-k6/scenarios/concepts/dropped-iterations/), [thresholds](https://grafana.com/docs/k6/latest/using-k6/thresholds/).

## Production changes and correctness

PostgreSQL accepted timezone names are cached per dynamic repository and running repo process, with one-hour TTL, explicit invalidation, serialized cold loads, and a cache-free migration fallback. Settings/env are resolved afresh. UserTimeZone, MapWindow and Visits.WebScope share this validation; PostgreSQL still computes DST and offsets. The native Docker target now includes existing SVG assets required by the HTML renderer. 54 relevant regression tests pass. Two genuine RED controls restore original resolver/window modules only in separate test VMs and fail the corresponding no-catalogue-query regression; current implementations pass. No schema/index/data change is required by the production fix. Test evidence is retained in `/Users/frey/projects/dawarich/benchmarks/timezone-fix-regressions.log`, `timezone-fix-red-control.log`, `timezone-map-window-red-control.log` and `timezone-cold-start-check.log`.

## Findings and remaining limits

All **80 lower-rate trials** meet the exploratory objective. Across the five initial HTML pages and both RAM caps, Phoenix p95 is 1.71–2.25 times lower and mean app working set is 3.61–3.84 times lower. This range describes the tested pages, not a universal language advantage.

At **512 MiB**, points API lower-load p95 is 43.2 ms Rails / 21.7 ms Phoenix. Under 300 offered RPS, delivered traffic is 98.8 / 82.2 RPS with dropped starts; neither meets that load. Phoenix DB CPU is 200%, app CPU 55%: residual work is concentrated in PostgreSQL.

The points HTML page also overloads: at 100 offered RPS, delivered traffic is 68.6 Rails / 42.8 Phoenix with drops. Its native DB CPU is 200%. Lower HTML latency therefore does not imply higher throughput on every page.

Tracks API lower-load p95 at 5 RPS is 51.4 / 121.7 ms. Its higher-rate CPU/memory behavior remains a separate optimization target. Raw OOM counts and invalid trials are retained; they are not stable capacity results.

At **1024 MiB**, points API lower-load p95 is 38.3 ms Rails / 20.5 ms Phoenix. Under 300 offered RPS, delivered traffic is 97.7 / 84.1 RPS with dropped starts; neither meets that load. Phoenix DB CPU is 200%, app CPU 54%: residual work is concentrated in PostgreSQL.

The points HTML page also overloads: at 100 offered RPS, delivered traffic is 64.9 Rails / 42.0 Phoenix with drops. Its native DB CPU is 200%. Lower HTML latency therefore does not imply higher throughput on every page.

Tracks API lower-load p95 at 5 RPS is 53.5 / 121.5 ms. Its higher-rate CPU/memory behavior remains a separate optimization target. Raw OOM counts and invalid trials are retained; they are not stable capacity results.

Dense MVT overload at 8 offered RPS produces errors/timeouts in both implementations while PostgreSQL saturates. The 2 RPS lower-load trials remain valid. The tile is generated over 100,000 synthetic points in one area; it is not a representative distribution of every real map viewport.

The generator reached at most 15.3% CPU and 106.1 MiB working set across measured windows (limits 200% CPU / 512 MiB). Dropped starts are therefore chiefly a 32-VU response-time/backlog limit; no CPU/memory exhaustion of the generator was observed.

## Same-image causal control

After completing the main matrix, the original UserTimeZone module was restored only in an isolated VM of the same fixed production image. The fixture, app/DB limits (2 CPU; app 1 GiB), 32 VUs, offered load (300 RPS), points payload and other modules remain identical. Two 15-second trials per variant, five-second low-rate warmup, reversed variant order. Both variants send the same authorized Host header. An initial alias rejected with HTTP 403 is preserved under `control-rejected-host/` and excluded; the entire four-trial control was rerun. This restores only the original resolver; MapWindow/Visits changes are not separately measured by this control.

| Variant | Delivered RPS median (range) | p95 ms | DB CPU % | Dropped starts, total |
|---|---:|---:|---:|---:|
| phoenix_before | 29.9 (29.1–30.6) | 1305.5 | 200 | 8054 |
| phoenix | 84.4 (83.9–84.9) | 423.7 | 200 | 6430 |

The permanent resolver fix increases delivered points RPS by **2.82×** in this controlled workload. Both variants are overloaded at the offered rate, so the ratio is an intervention result, not a sustainable production capacity estimate. All completed requests in these four trials pass content/error/OOM checks. See `control/summary.json` and `control/runs/*.json`.

The remaining tracks and MVT signals require separate profiling and tuning; this patch removes the proven repeated timezone catalogue bottleneck and fixes native HTML asset packaging. It does not establish that every Phoenix endpoint is faster than Rails. The source patch remains uncommitted.

## Results

Measured trials: **160**; semantically correct without OOM: **148**; full exploratory load objective passing: **116**. Every failed trial remains in raw records.



### 512 MiB application cap

| Scenario | Lower target RPS | p50 Rails / Phoenix ms | p95 Rails / Phoenix ms | p99 Rails / Phoenix ms | Mean RAM Rails / Phoenix MiB | App CPU Rails / Phoenix % | App+DB CPU/request Rails / Phoenix ms | Lower status Rails / Phoenix |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| map | 10 | 28.8 / 27.1 | 69.7 / 32.1 | 75.6 / 34.0 | 454.9 / 124.5 | 34.0 / 21.0 | 35.6 / 27.3 | PASS / PASS |
| stats_page | 10 | 26.8 / 21.0 | 55.2 / 25.8 | 67.3 / 27.1 | 441.3 / 117.6 | 28.1 / 16.8 | 29.6 / 22.2 | PASS / PASS |
| trips | 10 | 26.0 / 28.0 | 60.9 / 34.9 | 75.9 / 37.6 | 448.7 / 123.7 | 29.7 / 12.4 | 31.6 / 29.2 | PASS / PASS |
| imports | 10 | 29.3 / 25.1 | 53.1 / 30.0 | 77.5 / 32.7 | 458.2 / 125.5 | 32.0 / 22.3 | 33.5 / 26.2 | PASS / PASS |
| points_page | 10 | 33.4 / 33.2 | 71.9 / 36.5 | 80.3 / 38.1 | 458.5 / 121.3 | 27.5 / 9.9 | 55.7 / 67.0 | PASS / PASS |
| points_api | 50 | 18.2 / 16.6 | 43.2 / 21.7 | 60.8 / 28.0 | 424.5 / 204.5 | 49.3 / 28.4 | 36.3 / 33.7 | PASS / PASS |
| tracks_api | 5 | 28.9 / 113.2 | 51.4 / 121.7 | 61.3 / 128.9 | 460.3 / 277.4 | 13.8 / 35.8 | 36.0 / 147.4 | PASS / PASS |
| stats_api | 20 | 10.2 / 9.1 | 21.6 / 12.1 | 38.9 / 13.4 | 381.1 / 95.6 | 20.7 / 13.9 | 11.7 / 10.1 | PASS / PASS |
| visits_api | 20 | 11.5 / 8.5 | 20.6 / 11.6 | 39.5 / 13.9 | 385.8 / 118.6 | 23.0 / 11.8 | 12.9 / 9.5 | PASS / PASS |
| points_tile | 2 | 392.5 / 405.3 | 417.8 / 438.7 | 439.0 / 453.9 | 330.2 / 88.4 | 3.0 / 1.4 | 596.2 / 612.7 | PASS / PASS |

| Scenario | Higher target RPS | Delivered successful RPS Rails / Phoenix | p95 Rails / Phoenix ms | Dropped starts Rails / Phoenix | Status Rails / Phoenix |
|---|---:|---:|---:|---:|---|
| map | 100 | 60.2 / 99.9 | 625.5 / 26.9 | 1138.0 / 0.0 | drops or p95 > 1 s / PASS |
| stats_page | 100 | 96.6 / 100.0 | 349.7 / 8.3 | 54.0 / 0.0 | drops or p95 > 1 s / PASS |
| trips | 100 | 90.3 / 99.9 | 439.0 / 45.9 | 238.0 / 0.0 | drops or p95 > 1 s / PASS |
| imports | 100 | 58.0 / 100.0 | 666.3 / 19.6 | 1196.0 / 0.0 | drops or p95 > 1 s / PASS |
| points_page | 100 | 68.6 / 42.8 | 603.9 / 818.0 | 883.0 / 1679.0 | drops or p95 > 1 s / drops or p95 > 1 s |
| points_api | 300 | 98.8 / 82.2 | 393.3 / 476.6 | 5976.0 / 6492.0 | drops or p95 > 1 s / drops or p95 > 1 s |
| tracks_api | 100 | 29.2 / 16.4 | 1892.9 / 1543.0 | 2076.0 / 2373.0 | OOM / OOM |
| stats_api | 200 | 200.0 / 200.0 | 5.2 / 3.8 | 0.0 / 0.0 | PASS / PASS |
| visits_api | 200 | 200.0 / 200.0 | 3.7 / 3.5 | 0.0 / 0.0 | PASS / PASS |
| points_tile | 8 | 0.2 / 0.5 | 8576.4 / 6750.2 | 107.0 / 77.0 | errors/OOM state / errors/OOM state |

RPS from trials marked OOM/errors are partial successful traffic during an invalid trial, and are not a stable throughput result. If the app died at lower load, its higher trial was skipped rather than measuring a dead server.

### 1024 MiB application cap

| Scenario | Lower target RPS | p50 Rails / Phoenix ms | p95 Rails / Phoenix ms | p99 Rails / Phoenix ms | Mean RAM Rails / Phoenix MiB | App CPU Rails / Phoenix % | App+DB CPU/request Rails / Phoenix ms | Lower status Rails / Phoenix |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| map | 10 | 28.6 / 26.6 | 70.1 / 31.2 | 78.5 / 32.5 | 451.4 / 125.0 | 33.5 / 20.6 | 35.0 / 26.7 | PASS / PASS |
| stats_page | 10 | 26.2 / 21.6 | 53.6 / 26.1 | 70.3 / 27.5 | 439.9 / 117.7 | 28.4 / 17.0 | 30.0 / 22.7 | PASS / PASS |
| trips | 10 | 25.1 / 27.6 | 58.1 / 34.0 | 73.7 / 41.3 | 459.0 / 121.7 | 28.7 / 12.1 | 30.6 / 28.8 | PASS / PASS |
| imports | 10 | 28.7 / 25.6 | 61.2 / 30.1 | 81.7 / 33.4 | 456.0 / 121.2 | 31.9 / 22.4 | 33.3 / 26.4 | PASS / PASS |
| points_page | 10 | 33.3 / 33.8 | 70.9 / 37.5 | 83.9 / 39.8 | 458.2 / 119.4 | 27.5 / 10.0 | 55.6 / 67.8 | PASS / PASS |
| points_api | 50 | 18.0 / 16.0 | 38.3 / 20.5 | 49.2 / 81.4 | 433.2 / 207.7 | 47.9 / 26.7 | 36.0 / 33.0 | PASS / PASS |
| tracks_api | 5 | 29.7 / 112.7 | 53.5 / 121.5 | 61.2 / 123.4 | 480.6 / 269.9 | 13.8 / 35.9 | 36.1 / 147.1 | PASS / PASS |
| stats_api | 20 | 10.5 / 8.9 | 21.0 / 12.0 | 39.2 / 13.7 | 380.9 / 96.5 | 21.2 / 14.0 | 12.0 / 10.2 | PASS / PASS |
| visits_api | 20 | 11.4 / 9.1 | 21.4 / 12.1 | 36.2 / 20.5 | 389.7 / 122.7 | 22.8 / 12.3 | 12.9 / 10.2 | PASS / PASS |
| points_tile | 2 | 378.3 / 413.7 | 402.7 / 460.4 | 422.2 / 484.6 | 359.9 / 91.5 | 3.0 / 1.4 | 589.9 / 623.5 | PASS / PASS |

| Scenario | Higher target RPS | Delivered successful RPS Rails / Phoenix | p95 Rails / Phoenix ms | Dropped starts Rails / Phoenix | Status Rails / Phoenix |
|---|---:|---:|---:|---:|---|
| map | 100 | 60.4 / 99.9 | 633.3 / 24.5 | 1126.0 / 0.0 | drops or p95 > 1 s / PASS |
| stats_page | 100 | 99.8 / 100.0 | 159.3 / 7.9 | 0.0 / 0.0 | PASS / PASS |
| trips | 100 | 94.5 / 99.9 | 351.6 / 52.3 | 118.0 / 0.0 | drops or p95 > 1 s / PASS |
| imports | 100 | 58.5 / 100.0 | 616.1 / 12.6 | 1190.0 / 0.0 | drops or p95 > 1 s / PASS |
| points_page | 100 | 64.9 / 42.0 | 556.7 / 840.1 | 1000.0 / 1704.0 | drops or p95 > 1 s / drops or p95 > 1 s |
| points_api | 300 | 97.7 / 84.1 | 408.1 / 419.1 | 6007.0 / 6435.0 | drops or p95 > 1 s / drops or p95 > 1 s |
| tracks_api | 100 | 100.0 / 22.7 | 19.5 / 1532.7 | 0.0 / 2134.0 | PASS / errors/OOM state |
| stats_api | 200 | 200.0 / 200.0 | 4.0 / 3.8 | 0.0 / 0.0 | PASS / PASS |
| visits_api | 200 | 200.0 / 200.0 | 3.7 / 3.5 | 0.0 / 0.0 | PASS / PASS |
| points_tile | 8 | 0.2 / 0.9 | 4097.9 / 8756.6 | 107.0 / 87.0 | errors/OOM state / errors/OOM state |

RPS from trials marked OOM/errors are partial successful traffic during an invalid trial, and are not a stable throughput result. If the app died at lower load, its higher trial was skipped rather than measuring a dead server.

## Exact ten requests

| Scenario | URL (authentication omitted) | Kind | Rails / Phoenix body bytes |
|---|---|---|---:|
| map | `/map?start_at=2026-01-01&end_at=2026-01-02` | html | 349745 / 272348 |
| stats_page | `/stats` | html | 138500 / 107347 |
| trips | `/trips` | html | 140259 / 110325 |
| imports | `/imports` | html | 212468 / 180661 |
| points_page | `/points?start_at=2026-01-01&end_at=2026-01-02` | html | 183936 / 154792 |
| points_api | `/api/v1/points?start_at=1767225600&end_at=1767325600&per_page=100` | points | 71412 / 71412 |
| tracks_api | `/api/v1/tracks?start_at=2026-01-01T00%3A00%3A00Z&end_at=2026-01-02T04%3A00%3A00Z&per_page=100` | tracks | 15992 / 15992 |
| stats_api | `/api/v1/stats` | stats | 395 / 395 |
| visits_api | `/api/v1/visits?per_page=100&start_at=2026-01-01&end_at=2026-01-02` | visits | 10903 / 10903 |
| points_tile | `/api/v1/tiles/points/10/550/335.mvt?start_at=1767225600&end_at=1767325600` | mvt | 18813 / 18813 |

## Artifacts and rerun

Artifact directory: `/Users/frey/projects/dawarich/benchmarks/rails-phoenix-fixed-20261008`. `cases.json`, `bench.js`, `matrix-k6.py`, `provenance.json`, `preflight.json`, `summary-k6.json`, `results-k6.csv`, `runs-k6/*.json` preserve workload, checks, every k6 summary, threshold exit code, cgroup samples, OOM state and repetitions. Private generated secrets/session fixture are excluded from documents. `source/`, `fix.patch` and `time_zone_names.ex` preserve build inputs. `pilot/` is calibration, not final data.

```sh
python3 setup.py > setup.log 2>&1
python3 prepare-session.py
python3 preflight.py
python3 matrix-k6.py > progress-k6.log 2>&1
python3 control-k6.py > progress-control.log 2>&1
python3 summarize-k6.py
python3 make-report-k6.py
python3 finish-results.py
# Optional charts: use Python with numpy and matplotlib (requirements-plot.txt)
python3 plot-k6.py
python3 cleanup.py
```

Setup refuses pre-existing benchmark names and checks for a local Unix Docker context. It uses pinned images and synthetic isolated data. No SSH/external server is involved. Cleanup removes only owned labelled containers/network and their anonymous volumes. prepare-session.py generates session-private.json before HTML probes; seed.sql includes the additional list fixture. The control uses bench-control.js with an identical authorized Host header for both variants. Rejected-host controls and pilot data are excluded.


Cleanup verified: private benchmark containers/network/anonymous volumes and the four unique local regression databases created for this task were removed. Artifacts and images remain; unrelated `dawarich-trek` is preserved.


# Dawarich — Rails vs Phoenix benchmark, 512 MiB and 1 GiB

Measured on 2026-10-07; report generated 2026-10-07T21:25:04+02:00.
Repository counterpart: `/Users/frey/projects/dawarich/dawarich/.worktrees/phoenix-port/docs/phoenix/benchmark-20261007.md`. Detailed artifacts: `/Users/frey/projects/dawarich/benchmarks/rails-phoenix-20261007`.
AFFiNE counterpart: https://affine.dwri.xyz/workspace/c309ded7-e11e-4e72-ba6f-aec8a31a740b/lpUJR2CPL1Jqx6i7XNUkP

## Finding

The current native Phoenix port uses considerably less application memory for small JSON pages and MVT tiles, but this experiment shows no general throughput improvement over Rails. With 16 concurrent clients requesting 100 points, Rails was about 2.1× faster at 512 MiB and 3.0× faster at 1 GiB. Large JSON pages and MVT tiles at 1 GiB were broadly comparable within substantial run-to-run variation.

512 MiB is configuration-dependent: both the primary two-worker Rails setup and Phoenix failed with OOM under 16 concurrent 1000-point requests. Phoenix passed this page size with four clients. The supplementary one-worker Rails setup passed the measured workloads, including 64 clients, at the cost of queueing latency. These are short local runs, not a proof of long-term stability or a production sizing recommendation.

## Controlled environment

- Apple M5 Pro, 18 logical CPUs, 64 GiB host RAM; macOS 26.4; ARM64 Linux containers in OrbStack (18 CPUs, approximately 16 GiB VM RAM). Other development work was active on the host. Runs have wide ranges; absolute throughput and small differences are not reliable production capacity estimates.
- Rails production image: Dawarich **1.15.3**, revision `e32b70701b2467b862d4b5bc27ac428999997c1b`, Ruby 3.4.9 with YJIT. Pinned image `sha256:589e3606b11b61c3fa2d9661832cb73645a9b93a9cc7d807a071e2bc6c584498`.
- Native Phoenix release built from **`146d99212f25a3c773c4af785afc254d6828210f`**, Docker `native_runtime` target. Elixir 1.18.3 / OTP 27; no Ruby executable and no Rails proxy. Pinned image `sha256:21610fdd5711c18379d6271b001d2f4d25231dfcd4ca10e79b3da2eec2df8145`. Source was frozen before building; later branch changes are not part of this measurement.
- Each application: **2 CPU**, memory cap **512 or 1024 MiB**, memory+swap cap equal to RAM (swap disabled). Rails: 2 Puma workers × 5 threads, 10 total database connections. Phoenix: 2 BEAM schedulers, Repo pool explicitly set to 10 before startup. This deliberately matches total web DB connections, rather than using Phoenix's larger automatic pool default.
- Supplement: Rails 1 Puma worker × 5 threads, 5 total web database connections, still 2 CPU / 512 MiB. This is a different tuning profile, not part of the matched-pool primary comparison.
- Separate PostgreSQL/PostGIS 17: **2 CPU / 1 GiB**, same private database for both versions. Separate Redis: 0.5 CPU / 128 MiB. These resource budgets are **additional to the application limit**; this experiment does not fit a complete deployment into 512 MiB or 1 GiB.
- Fresh Rails schema plus native additive migrations; **100,000 synthetic Berlin points**, one synthetic active Pro user, fixed 2026-01-01–2026-01-02 interval. No real user data. Both versions read the same dataset. Application containers run sequentially.
- Web API workloads only. Separate Rails Sidekiq is excluded; Phoenix's in-process queue infrastructure is idle but enabled. No import, reverse geocoding, UI/LiveView, WebSocket, asset, or background processing benchmark.
- Private internal Docker network, no host ports, no outside services. Load generator has a separate 2 CPU / 256 MiB budget and was not CPU-bound.

## Method and correctness

GET cases: `/api/v1/points` with `per_page=100` (71,612 response bytes), with `per_page=1000` (716,060 bytes), and `/api/v1/tiles/points/10/550/335.mvt` covering the full point interval (18,365 bytes). Authentication uses a synthetic API key confined to the local fixture. Health is used for readiness only; its bodies differ and are not benchmarked.

Preflight verified that both JSON page contents are semantically identical and the MVT responses are byte-identical (`preflight.json`). Each measured request checks HTTP 200 and expected response length. This guards against benchmarking authentication errors, empty responses, redirects or cached 304s; it does not parse and compare every subsequent response.

Custom Go load generator, HTTP/1.1 keep-alive, identity encoding, no conditional validators, redirects disabled, 15-second client timeout. Closed-loop concurrency: JSON 1/16/64 clients, MVT 1/4/8. Two repetitions, alternating application order between repetitions. The four-client large-page supplement uses 12-second measurements; other profiles use 8 seconds. App restarted before each scenario/repetition, 2-second single-client warmup. Within a scenario, concurrency increases without an intervening restart, so later profiles retain cache/heap state.

RPS counts successful complete responses divided by actual elapsed time, including in-flight requests finishing after the nominal window. Percentiles are for successful responses; tables show median of the two per-run p95 values, not a pooled percentile. A valid run requires no HTTP/body/transport errors and no OOM kills. Failed runs are kept as raw evidence and never treated as successful capacity. If Phoenix's container died at concurrency 16, concurrency 64 was skipped in that scenario.

Resources are sampled from cgroup v2 approximately once per second. RAM means **container working set** (`memory.current − inactive_file`), not one process's RSS. Peaks are sampled lower bounds; brief pre-OOM spikes can be missed. Raw `memory.peak`, `memory.events` and Docker OOM/exit state provide enforcement evidence. Cgroup memory peak can include earlier profiles in the same scenario. CPU is cgroup usage over measurement time: 100% is one core, the cap is 200%. Includes application threads and measurement exec overhead. DB CPU is reported separately. Short warmup, only two repetitions, small sample counts for heavy MVT requests, shared host load, and closed-loop coordinated omission limit statistical confidence. No confidence interval or fixed-arrival overload SLA is claimed.

## Small JSON page, 100 points

| App limit | Version | Case / clients | Valid runs | RPS median [range] | p95 ms | App RAM mean / sampled peak MiB | App CPU / DB CPU % |
|---|---|---|---|---|---:|---|---|
| 512 MiB | Rails, 2 workers | points_100 / 16 | 2/2 | 49.0 [37.4–60.6] | 627 | 414 / 461 | 173 / 127 |
| 512 MiB | Phoenix | points_100 / 16 | 2/2 | 22.9 [18.5–27.3] | 856 | 170 / 266 | 51 / 199 |
| 1024 MiB | Rails, 2 workers | points_100 / 16 | 2/2 | 80.7 [59.5–102.0] | 340 | 449 / 489 | 175 / 139 |
| 1024 MiB | Phoenix | points_100 / 16 | 2/2 | 26.7 [19.7–33.7] | 832 | 156 / 222 | 62 / 197 |

## Large JSON page, 1000 points

| App limit | Version | Case / clients | Valid runs | RPS median [range] | p95 ms | App RAM mean / sampled peak MiB | App CPU / DB CPU % |
|---|---|---|---|---|---:|---|---|
| 512 MiB | Rails, 2 workers | points_1000 / 4 | 0/2 | OOM / failed | — | — / 497 | — |
| 512 MiB | Phoenix | points_1000 / 4 | 2/2 | 17.8 [17.4–18.2] | 273 | 226 / 286 | 176 / 84 |
| 512 MiB | Rails, 2 workers | points_1000 / 16 | 0/2 | OOM / failed | — | — / 500 | — |
| 512 MiB | Phoenix | points_1000 / 16 | 0/2 | OOM / failed | — | — / 305 | — |
| 1024 MiB | Rails, 2 workers | points_1000 / 4 | 2/2 | 19.7 [19.3–20.0] | 291 | 507 / 533 | 193 / 29 |
| 1024 MiB | Phoenix | points_1000 / 4 | 2/2 | 19.4 [18.8–20.0] | 260 | 219 / 268 | 176 / 88 |
| 1024 MiB | Rails, 2 workers | points_1000 / 16 | 2/2 | 11.3 [8.2–14.3] | 1973 | 541 / 585 | 186 / 28 |
| 1024 MiB | Phoenix | points_1000 / 16 | 2/2 | 10.6 [7.0–14.3] | 2596 | 345 / 506 | 181 / 81 |

At 512 MiB / 16 clients, Rails lost Puma children and restarted them; Phoenix's whole container was killed (exit 137 in both repetitions). At 1 GiB / 64 clients, the two-worker Rails large-page runs passed, but Phoenix failed both repetitions (one OOM and one error run). Even 1 GiB does not ensure survival at this concurrency for the tested native implementation.

## MVT tile

| App limit | Version | Case / clients | Valid runs | RPS median [range] | p95 ms | App RAM mean / sampled peak MiB | App CPU / DB CPU % |
|---|---|---|---|---|---:|---|---|
| 512 MiB | Rails, 2 workers | points_tile / 4 | 2/2 | 1.6 [1.5–1.6] | 2779 | 301 / 321 | 7 / 197 |
| 512 MiB | Phoenix | points_tile / 4 | 2/2 | 1.3 [1.1–1.5] | 3385 | 88 / 94 | 4 / 198 |
| 1024 MiB | Rails, 2 workers | points_tile / 4 | 2/2 | 1.8 [0.9–2.6] | 3217 | 299 / 317 | 11 / 194 |
| 1024 MiB | Phoenix | points_tile / 4 | 2/2 | 1.8 [1.1–2.5] | 2821 | 86 / 92 | 3 / 198 |

PostgreSQL approached its two-core cap. This tile includes all 100,000 points and is database-heavy; it is not a representative low-density tile. Increasing to eight clients frequently caused timeouts; those failures are in the full matrix. Memory here is materially lower for Phoenix, while the 1 GiB throughput ranges overlap almost completely.

## Rails tuning at 512 MiB

| App limit | Version | Case / clients | Valid runs | RPS median [range] | p95 ms | App RAM mean / sampled peak MiB | App CPU / DB CPU % |
|---|---|---|---|---|---:|---|---|
| 512 MiB | Rails, 1 worker | points_100 / 16 | 2/2 | 57.7 [56.7–58.7] | 357 | 333 / 352 | 90 / 73 |
| 512 MiB | Rails, 1 worker | points_1000 / 4 | 2/2 | 12.0 [12.0–12.1] | 486 | 390 / 411 | 98 / 16 |
| 512 MiB | Rails, 1 worker | points_1000 / 16 | 2/2 | 9.4 [9.3–9.5] | 1932 | 385 / 399 | 99 / 15 |
| 512 MiB | Rails, 1 worker | points_1000 / 64 | 2/2 | 9.5 [9.4–9.6] | 6991 | 387 / 400 | 98 / 14 |
| 512 MiB | Rails, 1 worker | points_tile / 4 | 2/2 | 2.8 [2.7–2.9] | 1501 | 284 / 293 | 5 / 199 |

One worker reduces application memory enough to avoid the OOM failures seen with two workers in these runs. Higher client counts queue behind five Puma threads; compare p95 as well as RPS. This does not establish background-job memory safety or long-run heap behavior.

Idle working set observations: 512 MiB / rails: 265 MiB (after health readiness, before API warmup); 512 MiB / phoenix: 89 MiB (after health readiness, before API warmup); 1024 MiB / rails: 270 MiB (after health readiness, before API warmup); 1024 MiB / phoenix: 88 MiB (after health readiness, before API warmup).

## CPU cost and observed native SQL hotspot

Small-page case, 16 clients:

| App limit | Version | App CPU ms / successful request | App + PostgreSQL CPU ms / successful request |
|---|---|---:|---:|
| 512 MiB | rails | 37.9 | 65.2 |
| 512 MiB | phoenix | 23.9 | 115.0 |
| 1024 MiB | rails | 23.6 | 42.2 |
| 1024 MiB | phoenix | 25.0 | 105.4 |

Phoenix's lower aggregate web-container CPU usage partly reflects lower completed throughput. Including DB CPU per successful request, these runs show **higher total CPU cost for Phoenix**; lower web CPU percentage alone is not an overall efficiency win.

During native small-page load, active PostgreSQL queries included concurrent timezone-validation scans of `pg_timezone_names`. Frozen source `app-phoenix/lib/dawarich/map_api/closure.ex:9` calls `Account.zone`; `account_api/closure.ex:66` delegates to `UserTimeZone.name`; `user_time_zone.ex:53` executes the timezone validation CTE. Pool-drop logs (`connection not available and request was dropped from queue`) explain some native HTTP 500 failures at 64 small-page clients.

After all HTTP tests stopped, five isolated `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` measurements of the same validation CTE with `Etc/UTC` / `Europe/Berlin` took median **8.43 ms**, range **8.15–12.88 ms**. A literal SELECT control took median 0.012 ms. See `timezone-query-observed.sql` and `timezone-profile.json`. Combined with DB saturation and the source call path, this is evidence of an optimization candidate, not proof that it accounts for the entire throughput gap. No optimization was applied to either application during this comparison.

Suggested next engineering work: remove repeated expensive timezone validation from the read path while preserving timezone semantics, then rerun the frozen workload; examine bounded admission for large native responses to avoid whole-VM OOM. These are follow-up candidates, not changes implemented in this benchmark.

## Reproduction and artifacts

Artifact directory `/Users/frey/projects/dawarich/benchmarks/rails-phoenix-20261007` contains the frozen tracked `source/`, image provenance, synthetic seed SQL, preflight bodies/hashes, Go client source/binary, individual runs/server logs, cgroup samples, `index.json`, `summary.json`, full `summary-table.md`, and `comparison.png` / `.svg`. Only `index.json` contributes to summaries; the aborted pilot is retained separately and excluded.

Requires local ARM64 Docker and the pinned images (Rails official release and native image built with `docker build -f source/docker/Dockerfile --target native_runtime -t dawarich:benchmark-phoenix-20261007 source`). Helpers validate a local Unix Docker context. Do not use an SSH Docker context. `setup.py` refuses an existing benchmark namespace, generates private local secrets into a mode-0600 env file, creates fresh labelled resources, loads Rails schema, seeds the private database, applies native additive migrations and creates stopped app containers. It never connects to an existing Dawarich database.

Run in a **new copy** of this artifact directory to preserve the original results:

```sh
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o loadgen loadgen.go
python3 setup.py
python3 run.py > progress.log 2>&1
python3 safe-load.py > safe-load-progress.log 2>&1
python3 supplement.py > supplement-progress.log 2>&1
python3 oneworker-low.py > oneworker-low-progress.log 2>&1
python3 profile-timezone.py
python3 summarize.py > summary-table.md
python3 make-report.py
python3 cleanup.py
```

Plot regeneration: Python with matplotlib 3.11.2 / numpy 2.5.3, then `python3 plot.py`. Bench containers and their temporary database/Redis volumes were removed after collecting results; pinned app images and all local artifacts remain. Cleanup checks ownership labels and targets only `rpbench-*` and `rpbench-net`.

Full measured matrix (98 runs; invalid runs retained):

| RAM MiB | Version | Scenario | Clients | Valid | RPS median | p95 ms | App CPU % | DB CPU % | App RAM peak MiB | OOM kills |
|---:|---|---|---:|---|---:|---:|---:|---:|---:|---:|
| 512 | phoenix | points_100 | 1 | 2/2 | 11.3 | 104.2 | 23 | 80 | 123.5 | 0 |
| 512 | phoenix | points_100 | 16 | 2/2 | 22.9 | 856.0 | 51 | 199 | 266.5 | 0 |
| 512 | phoenix | points_100 | 64 | 0/2 | — | — | — | — | 242.7 | 0 |
| 512 | phoenix | points_1000 | 1 | 2/2 | 3.6 | 340.7 | 69 | 35 | 208.3 | 0 |
| 512 | phoenix | points_1000 | 4 | 2/2 | 17.8 | 272.7 | 176 | 84 | 285.9 | 0 |
| 512 | phoenix | points_1000 | 16 | 0/2 | — | — | — | — | 305.5 | 2 |
| 512 | phoenix | points_tile | 1 | 2/2 | 0.7 | 1517.6 | 3 | 116 | 121.3 | 0 |
| 512 | phoenix | points_tile | 4 | 2/2 | 1.3 | 3384.7 | 4 | 198 | 94.3 | 0 |
| 512 | phoenix | points_tile | 8 | 0/2 | — | — | — | — | 94.9 | 0 |
| 512 | rails | points_100 | 1 | 2/2 | 13.2 | 157.5 | 67 | 36 | 428.1 | 0 |
| 512 | rails | points_100 | 16 | 2/2 | 49.0 | 626.8 | 173 | 127 | 461.4 | 0 |
| 512 | rails | points_100 | 64 | 2/2 | 64.1 | 1362.9 | 173 | 152 | 454.7 | 0 |
| 512 | rails | points_1000 | 1 | 2/2 | 4.5 | 366.2 | 90 | 13 | 380.1 | 0 |
| 512 | rails | points_1000 | 4 | 0/2 | — | — | — | — | 496.8 | 2 |
| 512 | rails | points_1000 | 16 | 0/2 | — | — | — | — | 499.9 | 12 |
| 512 | rails | points_1000 | 64 | 0/2 | — | — | — | — | 504.4 | 13 |
| 512 | rails | points_tile | 1 | 2/2 | 0.9 | 1114.1 | 4 | 116 | 299.0 | 0 |
| 512 | rails | points_tile | 4 | 2/2 | 1.6 | 2779.5 | 7 | 197 | 320.6 | 0 |
| 512 | rails | points_tile | 8 | 1/2 | 1.5 | 5228.4 | 6 | 192 | 319.3 | 0 |
| 512 | rails_1worker | points_100 | 1 | 2/2 | 36.3 | 48.6 | 55 | 46 | 348.0 | 0 |
| 512 | rails_1worker | points_100 | 16 | 2/2 | 57.7 | 356.6 | 90 | 73 | 351.7 | 0 |
| 512 | rails_1worker | points_100 | 64 | 2/2 | 63.2 | 1137.7 | 90 | 79 | 357.3 | 0 |
| 512 | rails_1worker | points_1000 | 1 | 2/2 | 9.4 | 181.3 | 88 | 14 | 381.4 | 0 |
| 512 | rails_1worker | points_1000 | 4 | 2/2 | 12.0 | 486.4 | 98 | 16 | 411.5 | 0 |
| 512 | rails_1worker | points_1000 | 16 | 2/2 | 9.4 | 1931.9 | 99 | 15 | 399.1 | 0 |
| 512 | rails_1worker | points_1000 | 64 | 2/2 | 9.5 | 6990.7 | 98 | 14 | 399.6 | 0 |
| 512 | rails_1worker | points_tile | 1 | 2/2 | 1.7 | 630.5 | 3 | 115 | 279.2 | 0 |
| 512 | rails_1worker | points_tile | 4 | 2/2 | 2.8 | 1500.6 | 5 | 199 | 293.2 | 0 |
| 512 | rails_1worker | points_tile | 8 | 2/2 | 2.9 | 3454.4 | 4 | 199 | 300.2 | 0 |
| 1024 | phoenix | points_100 | 1 | 2/2 | 10.7 | 149.7 | 29 | 76 | 127.1 | 0 |
| 1024 | phoenix | points_100 | 16 | 2/2 | 26.7 | 832.4 | 62 | 197 | 222.4 | 0 |
| 1024 | phoenix | points_100 | 64 | 0/2 | — | — | — | — | 282.9 | 0 |
| 1024 | phoenix | points_1000 | 1 | 2/2 | 4.2 | 310.5 | 67 | 38 | 209.5 | 0 |
| 1024 | phoenix | points_1000 | 4 | 2/2 | 19.4 | 260.3 | 176 | 88 | 267.9 | 0 |
| 1024 | phoenix | points_1000 | 16 | 2/2 | 10.6 | 2596.2 | 181 | 81 | 505.6 | 0 |
| 1024 | phoenix | points_1000 | 64 | 0/2 | — | — | — | — | 931.6 | 1 |
| 1024 | phoenix | points_tile | 1 | 2/2 | 1.0 | 1321.0 | 3 | 115 | 90.7 | 0 |
| 1024 | phoenix | points_tile | 4 | 2/2 | 1.8 | 2821.3 | 3 | 198 | 92.0 | 0 |
| 1024 | phoenix | points_tile | 8 | 1/2 | 2.0 | 4310.4 | 3 | 196 | 98.8 | 0 |
| 1024 | rails | points_100 | 1 | 2/2 | 26.4 | 60.0 | 57 | 44 | 375.2 | 0 |
| 1024 | rails | points_100 | 16 | 2/2 | 80.7 | 340.4 | 175 | 139 | 489.1 | 0 |
| 1024 | rails | points_100 | 64 | 2/2 | 102.1 | 962.0 | 177 | 164 | 496.4 | 0 |
| 1024 | rails | points_1000 | 1 | 2/2 | 7.4 | 231.9 | 89 | 14 | 513.1 | 0 |
| 1024 | rails | points_1000 | 4 | 2/2 | 19.7 | 291.4 | 193 | 29 | 533.5 | 0 |
| 1024 | rails | points_1000 | 16 | 2/2 | 11.3 | 1972.8 | 186 | 28 | 584.8 | 0 |
| 1024 | rails | points_1000 | 64 | 2/2 | 11.7 | 6876.1 | 178 | 24 | 594.7 | 0 |
| 1024 | rails | points_tile | 1 | 2/2 | 1.1 | 1109.5 | 5 | 113 | 298.3 | 0 |
| 1024 | rails | points_tile | 4 | 2/2 | 1.8 | 3216.9 | 11 | 194 | 317.4 | 0 |
| 1024 | rails | points_tile | 8 | 1/2 | 2.3 | 3834.4 | 5 | 198 | 332.8 | 0 |


# Dawarich — completed Phoenix port vs Rails, 512 MiB and 1 GiB

Measured 2026-10-08. Report generated 2026-10-08T16:02:59+02:00.
Repository counterpart: `/Users/frey/projects/dawarich/dawarich/.worktrees/phoenix-port/docs/phoenix/benchmark-20261008.md`.
AFFiNE counterpart: https://affine.dwri.xyz/workspace/c309ded7-e11e-4e72-ba6f-aec8a31a740b/NFBRxPyOeWYhshN4xDEqR
Raw artifacts: `/Users/frey/projects/dawarich/benchmarks/rails-phoenix-20261008`.

## Findings

At 512 MiB, Rails (2 workers) delivered 3.31× the small-page throughput of Phoenix; Phoenix mean working set was 178 MiB versus Rails 434 MiB.
At 1024 MiB, Rails (2 workers) delivered 3.19× the small-page throughput of Phoenix; Phoenix mean working set was 182 MiB versus Rails 449 MiB.
At 1 GiB / 16 clients, 1000-point pages were effectively tied: Rails 32.7 RPS and Phoenix 32.0 RPS, with p95 617/617 ms. Phoenix sampled peak RAM was 519 MiB versus Rails 632 MiB.
At 512 MiB / 4 clients, Phoenix delivered 27.3 RPS for 1000-point pages versus the stable one-worker Rails profile at 15.8 RPS; two-worker Rails suffered OOM. At 16 clients on 512 MiB, native large-page requests caused whole-container OOM in both repeats, while the one-worker Rails profile passed. Dense MVT throughput was similar across the primary application versions.

This is a measured web API comparison on synthetic data. It does not establish total application capacity, background-job performance or deployment acceptance. Failures and overload profiles are kept separately below; a failed run is not a successful throughput result.

## Versions and resource budgets

- Current Phoenix: frozen branch HEAD **`7e90969a7a4d8ad28b3be24d38754635aac3d9ac`**, native_runtime production target built from tracked source. No Ruby, Bundler, Rails or Puma executables in the image; direct native HTTP server, no Rails proxy. Image ID `sha256:d388e4f2688a3b4eab3ac74a24b7f79b17b7f9981656291354ca4953985fd6f3`. The benchmark overrides the release entrypoint only to set the matched DB pool and logger before ordinary Application startup (`phoenix-start.exs`).
- Rails **1.15.3**, source revision `e32b70701b2467b862d4b5bc27ac428999997c1b`, Ruby 3.4.9 with YJIT; same pinned official release image as the previous comparison: `sha256:589e3606b11b61c3fa2d9661832cb73645a9b93a9cc7d807a071e2bc6c584498`. The production Rails version integrated into the Phoenix migration is also 1.15.3.
- Each app gets **2 CPU**, **512 or 1024 MiB RAM**, with memory-swap equal to memory (no swap). Rails primary profile: 2 Puma workers × 5 threads, total DB pool 10. Phoenix: 2 BEAM schedulers, explicit DB pool 10. The pool adjustment keeps the main comparison consistent with the previous benchmark; this is not Phoenix's larger automatic pool default.
- Rails tuning supplement: 1 Puma worker × 5 threads, DB pool 5, still 2 CPU / 512 MiB. It is a distinct configuration profile, not a pool-matched primary result.
- PostgreSQL/PostGIS 17, **separate 2 CPU / 1 GiB RAM**; private database shared by both versions. Redis: separate 0.5 CPU / 128 MiB. These budgets are additional to the app limit. A whole installation was not restricted to 512 MiB or 1 GiB.
- Apple M5 Pro, 18 logical CPUs, 64 GiB host RAM, macOS-26.4-arm64-arm-64bit-Mach-O; local ARM64 Docker / OrbStack. Only dawarich-trek idle Docker container observed at start; macOS and other user applications active. Host is not dedicated. No SSH, external host or production data was used.
- Web process only: separate Rails Sidekiq is excluded; native Oban and maintenance infrastructure remain enabled but no import/job workload is submitted. UI/LiveView, WebSockets, writes, imports, geocoding and background jobs were not benchmarked.

## Dataset, correctness and method

100,000 synthetic Berlin points spanning 2026-01-01–2026-01-02, one synthetic active Pro account. Fresh Rails schema, seeded without model callbacks, then native additive migrations. Both apps read the same database sequentially. Containers are confined to a private internal network, with no exposed ports.

Cases: `/api/v1/points` with 100 points (71,612 bytes) and 1000 points (716,060 bytes), and `/api/v1/tiles/points/10/550/335.mvt` covering all points (18,365 bytes). Preflight verified semantically identical JSON and byte-identical MVT (`preflight.json`). Every measured request must return HTTP 200 and the expected byte length. Per-response JSON semantic validation is not performed during load. Health is readiness-only; its different response bodies are excluded.

Closed-loop Go client, HTTP/1.1 keep-alive, identity encoding, no conditional validators, no redirects, 15-second timeout. Separate load client 2 CPU / 256 MiB. Main profiles: small JSON 16 and 64 clients; large JSON 4 and 16 clients; MVT 4 clients. Two repetitions, reversed Rails/Phoenix order in the second repetition. Each scenario/repetition gets a fresh app restart and a 3-second single-client warmup, then **12-second** measurement per profile. The higher concurrency in a scenario follows the lower one without restarting; skipped after a container death. One-worker supplement uses the same durations.

RPS = completed successful responses / actual elapsed time, including tail requests. p95 is the median of the per-run successful-response p95s; no pooled p95 or fixed-arrival SLA is claimed. Valid means no non-200 HTTP, body-size/transport errors, runner error or OOM. Short runs, only two repetitions, shared host activity and closed-loop coordinated omission limit confidence. Error-bar ranges are the two measured values, not confidence intervals. Raw failed responses are retained and excluded from successful comparisons.

RAM is cgroup working set (`memory.current − inactive_file`), sampled roughly once/second. Mean is per-run mean, then median across runs; peak is max sampled working set across the repetitions. Sampled peaks can miss a brief OOM spike. Cgroup `memory.peak`, `memory.events` and Docker's OOM/exit state retain enforcement evidence; memory.peak can include warmup/preceding concurrency. CPU is cgroup CPU time: 100% = one core, limit 200%. DB CPU is separate. Application measurement includes normal native housekeeping and sampling exec overhead.

## Small pages — 100 points

| App RAM limit | Version | Scenario / clients | Valid | RPS median [min–max] | p95 ms | Mean / peak app RAM MiB | App / DB CPU % |
|---|---|---|---|---|---:|---|---|
| 512 | Rails (2 workers) | points_100 / 16 | 2/2 | 177.3 [144.4–210.1] | 161 | 434 / 453 | 171 / 184 |
| 512 | Phoenix | points_100 / 16 | 2/2 | 53.5 [50.0–57.1] | 355 | 178 / 249 | 42 / 200 |
| 1024 | Rails (2 workers) | points_100 / 16 | 2/2 | 192.6 [191.7–193.5] | 147 | 449 / 484 | 165 / 192 |
| 1024 | Phoenix | points_100 / 16 | 2/2 | 60.3 [60.2–60.4] | 308 | 182 / 254 | 41 / 200 |

## Large pages — 1000 points

| App RAM limit | Version | Scenario / clients | Valid | RPS median [min–max] | p95 ms | Mean / peak app RAM MiB | App / DB CPU % |
|---|---|---|---|---|---:|---|---|
| 512 | Rails (2 workers) | points_1000 / 4 | 0/2 | OOM / failed | — | — / 509 | — |
| 512 | Phoenix | points_1000 / 4 | 2/2 | 27.3 [24.3–30.3] | 173 | 231 / 298 | 170 / 83 |
| 512 | Rails (2 workers) | points_1000 / 16 | 0/2 | OOM / failed | — | — / 510 | — |
| 512 | Phoenix | points_1000 / 16 | 0/2 | OOM / failed | — | — / 509 | — |
| 1024 | Rails (2 workers) | points_1000 / 4 | 2/2 | 34.2 [33.7–34.7] | 167 | 534 / 584 | 191 / 34 |
| 1024 | Phoenix | points_1000 / 4 | 2/2 | 29.1 [29.0–29.1] | 163 | 224 / 290 | 168 / 85 |
| 1024 | Rails (2 workers) | points_1000 / 16 | 2/2 | 32.7 [32.4–33.1] | 617 | 587 / 632 | 193 / 34 |
| 1024 | Phoenix | points_1000 / 16 | 2/2 | 32.0 [31.6–32.4] | 617 | 383 / 519 | 196 / 96 |

## Dense MVT tile

| App RAM limit | Version | Scenario / clients | Valid | RPS median [min–max] | p95 ms | Mean / peak app RAM MiB | App / DB CPU % |
|---|---|---|---|---|---:|---|---|
| 512 | Rails (2 workers) | points_tile / 4 | 2/2 | 3.7 [3.2–4.2] | 1156 | 342 / 373 | 5 / 199 |
| 512 | Phoenix | points_tile / 4 | 2/2 | 3.8 [3.7–3.9] | 1119 | 91 / 102 | 2 / 199 |
| 1024 | Rails (2 workers) | points_tile / 4 | 2/2 | 3.8 [3.8–3.9] | 1114 | 333 / 365 | 4 / 200 |
| 1024 | Phoenix | points_tile / 4 | 2/2 | 3.7 [3.7–3.8] | 1167 | 84 / 91 | 2 / 200 |

The tile covers all 100,000 points; this is a database-heavy workload. Interpret DB saturation and sparse per-run samples before comparing small RPS differences. It is not a low-density map tile benchmark.

## Rails at 512 MiB with one worker

| App RAM limit | Version | Scenario / clients | Valid | RPS median [min–max] | p95 ms | Mean / peak app RAM MiB | App / DB CPU % |
|---|---|---|---|---|---:|---|---|
| 512 | Rails (1 worker) | points_100 / 16 | 2/2 | 104.6 [103.6–105.5] | 207 | 334 / 349 | 88 / 101 |
| 512 | Rails (1 worker) | points_1000 / 4 | 2/2 | 15.8 [14.3–17.3] | 368 | 401 / 414 | 97 / 17 |
| 512 | Rails (1 worker) | points_1000 / 16 | 2/2 | 16.0 [14.2–17.7] | 1140 | 413 / 423 | 98 / 17 |
| 512 | Rails (1 worker) | points_tile / 4 | 2/2 | 3.6 [3.3–4.0] | 1245 | 290 / 309 | 4 / 200 |

Idle app working sets, after health readiness and before API warmup: 512 MiB Rails (2 workers): 253 MiB; 512 MiB Phoenix: 88 MiB; 1024 MiB Rails (2 workers): 262 MiB; 1024 MiB Phoenix: 88 MiB.

## CPU cost per successful response

Small JSON, 16 clients:

| Limit MiB | Version | App CPU ms / response | App + DB CPU ms / response |
|---|---|---:|---:|
| 512 | Rails (2 workers) | 10.1 | 20.8 |
| 512 | Phoenix | 8.0 | 45.6 |
| 1024 | Rails (2 workers) | 8.6 | 18.6 |
| 1024 | Phoenix | 6.9 | 40.2 |

Lower aggregate app CPU can reflect lower throughput. Compare CPU milliseconds per successful request, including DB work, before claiming an efficiency win.

## Errors and OOM

- 512 MiB / Phoenix / points_100 / 64 clients: valid 0/2, 1 OOM kills, 392 non-200 HTTP responses, 3080 transport/body errors.
- 512 MiB / Phoenix / points_1000 / 16 clients: valid 0/2, 2 OOM kills, 0 non-200 HTTP responses, 3061 transport/body errors.
- 512 MiB / Rails (2 workers) / points_1000 / 4 clients: valid 0/2, 7 OOM kills, 0 non-200 HTTP responses, 0 transport/body errors.
- 512 MiB / Rails (2 workers) / points_1000 / 16 clients: valid 0/2, 25 OOM kills, 0 non-200 HTTP responses, 30 transport/body errors.
- 1024 MiB / Phoenix / points_100 / 64 clients: valid 1/2, 0 OOM kills, 396 non-200 HTTP responses, 396 transport/body errors.

Non-200 counts and transport/body errors are distinct measures; a non-200 body can also fail the expected-length check. Do not sum them as unique failed requests. Native whole-container OOM and Rails worker OOM are distinguished in raw container state / cgroup events. A worker may restart while its parent container stays alive.

## Comparison with 2026-10-07

Previous native revision: `146d99212f25a3c773c4af785afc254d6828210f`. Previous report: `/Users/frey/projects/dawarich/benchmarks/rails-phoenix-20261007/report.md`.
Same app/DB resource caps, pinned Rails image, dataset, endpoints, response sizes, matched total DB pool and Go client. The current warmup is 3 seconds versus 2 seconds previously; measurement is 12 seconds versus 8 seconds in the previous main matrix (its four-client large-page supplement also used 12 seconds). Current profiles omit single-client measurements and MVT concurrency 8. Host load differs, so changes in absolute RPS are not solely attributable to code changes. Fresh Rails measurements provide the contemporaneous baseline.

Small JSON / 16 clients:

| Limit MiB | Version | Previous RPS | Current RPS | Previous mean RAM MiB | Current mean RAM MiB |
|---|---|---:|---:|---:|---:|
| 512 | Rails (2 workers) | 49.0 | 177.3 | 414 | 434 |
| 512 | Phoenix | 22.9 | 53.5 | 170 | 178 |
| 1024 | Rails (2 workers) | 80.7 | 192.6 | 449 | 449 |
| 1024 | Phoenix | 26.7 | 60.3 | 156 | 182 |

The tested `UserTimeZone` and `MapApi` source paths have no diff between the old and current frozen revisions. The prior observed per-request `pg_timezone_names` validation query remains in this source. This is an existing optimization candidate; this run does not establish its exact share of CPU or the full cause of any throughput gap. No performance patch or application configuration optimization beyond the stated pool/scheduler/worker settings was applied during testing.

## Artifacts and reproduction

`index.json` is the sole run manifest (48 measured runs); `runs/*.json` includes statuses, errors, timing, resource samples, cgroup counters and container state. `summary.json` / `summary-table.md`, `comparison.png` / `.svg`, `cpu-comparison.png` / `.svg`, `preflight.json` and saved preflight bodies retain the results. Source snapshot, image IDs, seed SQL, Go client, private env file, setup/cleanup scripts and server logs remain in the artifact directory.

Reproduce in a **new copy** of this artifact directory to preserve evidence. Local ARM64 Docker and pinned images are required; all helpers use a local Unix Docker context. Setup refuses existing benchmark names, creates fresh labelled containers and a private database, generates only synthetic secrets into a mode-0600 env file, loads schema, seeds and applies native migrations. No existing Dawarich database is selected. Build current native image from the frozen source with `docker build -f source/docker/Dockerfile --target native_runtime -t dawarich:benchmark-phoenix-20261008 source`. Rebuild client if needed with `GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o loadgen loadgen.go`.

```sh
python3 setup.py > setup.log 2>&1
python3 matrix.py > progress.log 2>&1
python3 rails-oneworker.py > rails-oneworker-progress.log 2>&1
python3 summarize.py > summary-table.md
python3 make-report.py
python3 plot.py
python3 cleanup.py
```

Plotting requires matplotlib / numpy (the previous artifact directory's private virtualenv is reusable). No dependency is added to the application. Benchmark containers, network and anonymous test volumes are removed after collection; the pinned image and local results remain. Cleanup requires this benchmark's ownership label and never targets unrelated containers.

## Full matrix

| RAM MiB | Version | Scenario | Clients | Valid | RPS median | p95 ms | App CPU % | DB CPU % | App RAM peak MiB | OOM kills |
|---:|---|---|---:|---|---:|---:|---:|---:|---:|---:|
| 512 | phoenix | points_100 | 16 | 2/2 | 53.5 | 355.1 | 42 | 200 | 248.8 | 0 |
| 512 | phoenix | points_100 | 64 | 0/2 | — | — | — | — | 419.8 | 1 |
| 512 | phoenix | points_1000 | 4 | 2/2 | 27.3 | 172.8 | 170 | 83 | 298.1 | 0 |
| 512 | phoenix | points_1000 | 16 | 0/2 | — | — | — | — | 509.2 | 2 |
| 512 | phoenix | points_tile | 4 | 2/2 | 3.8 | 1119.4 | 2 | 199 | 101.7 | 0 |
| 512 | rails | points_100 | 16 | 2/2 | 177.3 | 160.5 | 171 | 184 | 453.1 | 0 |
| 512 | rails | points_100 | 64 | 2/2 | 188.5 | 444.1 | 166 | 192 | 457.2 | 0 |
| 512 | rails | points_1000 | 4 | 0/2 | — | — | — | — | 508.8 | 7 |
| 512 | rails | points_1000 | 16 | 0/2 | — | — | — | — | 509.6 | 25 |
| 512 | rails | points_tile | 4 | 2/2 | 3.7 | 1155.7 | 5 | 199 | 373.5 | 0 |
| 512 | rails_1worker | points_100 | 16 | 2/2 | 104.6 | 206.5 | 88 | 101 | 349.0 | 0 |
| 512 | rails_1worker | points_1000 | 4 | 2/2 | 15.8 | 367.6 | 97 | 17 | 414.3 | 0 |
| 512 | rails_1worker | points_1000 | 16 | 2/2 | 16.0 | 1140.2 | 98 | 17 | 422.8 | 0 |
| 512 | rails_1worker | points_tile | 4 | 2/2 | 3.6 | 1244.9 | 4 | 200 | 308.9 | 0 |
| 1024 | phoenix | points_100 | 16 | 2/2 | 60.3 | 307.8 | 41 | 200 | 254.0 | 0 |
| 1024 | phoenix | points_100 | 64 | 1/2 | 58.5 | 1282.9 | 37 | 199 | 571.1 | 0 |
| 1024 | phoenix | points_1000 | 4 | 2/2 | 29.1 | 162.7 | 168 | 85 | 289.7 | 0 |
| 1024 | phoenix | points_1000 | 16 | 2/2 | 32.0 | 617.2 | 196 | 96 | 518.7 | 0 |
| 1024 | phoenix | points_tile | 4 | 2/2 | 3.7 | 1167.2 | 2 | 200 | 90.9 | 0 |
| 1024 | rails | points_100 | 16 | 2/2 | 192.6 | 146.8 | 165 | 192 | 484.1 | 0 |
| 1024 | rails | points_100 | 64 | 2/2 | 188.4 | 421.5 | 167 | 194 | 490.3 | 0 |
| 1024 | rails | points_1000 | 4 | 2/2 | 34.2 | 167.4 | 191 | 34 | 584.0 | 0 |
| 1024 | rails | points_1000 | 16 | 2/2 | 32.7 | 617.4 | 193 | 34 | 631.5 | 0 |
| 1024 | rails | points_tile | 4 | 2/2 | 3.8 | 1113.8 | 4 | 200 | 365.2 | 0 |


## Follow-up diagnosis — 2026-10-08

A controlled single-factor experiment confirmed repeated PostgreSQL timezone validation as a major cause of the small-page gap. On the same frozen image and fixture (2 CPU / 1 GiB, pool 10), memoizing the original validation result removed two timezone scans per request and improved repeated native throughput from about 58 to 171 RPS; p95 fell from about 333 to 114 ms. Restoring validation restored the slowdown. A larger pool alone did not help. This is a disposable-VM intervention; no production fix has been applied. [Detailed diagnosis](https://affine.dwri.xyz/workspace/c309ded7-e11e-4e72-ba6f-aec8a31a740b/NCzOrfmPz_Ho_8zh6HeVn).

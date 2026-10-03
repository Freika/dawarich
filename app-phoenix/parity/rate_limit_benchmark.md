# A13c PostgreSQL counter saturation gate

Run the branch's `scripts/rate_limit_smoke.sh` against both images on the controller's approved Docker host. The script creates its isolated Cloud/PgBouncer stack and removes it after each run. The PgBouncer pool and HTTP worker count both use `pool_size=4` from the smoke script.

Each run measures two phases: 900 points requests with one limiter UPSERT per request, then 500 tile requests with two UPSERTs per request. The synthetic benchmark account has a Pro plan. The tiles phase stays below the unchanged 600/30-second burst budget; points stay below the unchanged Pro quota. Every request must return HTTP 200. A throttled, failed, or timed-out request aborts the benchmark instead of appearing as a fast sample.

An independent sampler issues `SHOW POOLS` once per second throughout each phase, plus an initial and final sample. It records `cl_waiting`, `maxwait`, and `maxwait_us` by column name and requires an application pool row. JSON reports contain the concurrency, request and sample counts, p50/p95, maximum waiting clients, and the longest wait's seconds and microseconds.

From the repository root, using absolute report paths:

```sh
MODE=bench BENCH_ROLE=base BENCH_REPORT=/tmp/a13c-base-1.json IMAGE=dawarich:a13c-base sh app-phoenix/scripts/rate_limit_smoke.sh
MODE=bench BENCH_ROLE=branch BENCH_REPORT=/tmp/a13c-branch-1.json BENCH_BASELINE=/tmp/a13c-base-1.json IMAGE=dawarich:a13c sh app-phoenix/scripts/rate_limit_smoke.sh
MODE=bench BENCH_ROLE=base BENCH_REPORT=/tmp/a13c-base-2.json IMAGE=dawarich:a13c-base sh app-phoenix/scripts/rate_limit_smoke.sh
MODE=bench BENCH_ROLE=branch BENCH_REPORT=/tmp/a13c-branch-2.json BENCH_BASELINE=/tmp/a13c-base-2.json IMAGE=dawarich:a13c sh app-phoenix/scripts/rate_limit_smoke.sh
```

A branch run requires a baseline report and writes its report before checking the gates, so failed comparisons remain available. For **each phase**, it requires identical concurrency and request counts, actual pool samples, `max_cl_waiting=0`, p95 at most baseline p95 + 0.005 seconds, and maximum wait at most baseline wait + 0.005 seconds. It exits nonzero on a failed gate. The 5 ms maximum-wait tolerance is explicit in `RateLimitBench::WAIT_EPSILON`.

The controller additionally records the median base and branch p95 for each phase across the alternating runs, retaining the plan's median p95 comparison. The per-run paired comparison is stricter than that median check. A failed gate stops the slice for the controller's existing OQ2 decision process. Keep the JSON reports and container failure logs with the E2 evidence.

Related plan: `superpowers/plans/2026-10-02-phoenix-a13c-rate-limit-parity-plan.md`, E2 Step 5 and OQ2. Controller owns remote execution, images, plan rulings, and documentation synchronization.

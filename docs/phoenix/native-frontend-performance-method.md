# Native frontend performance method

Status: D0 harness prepared, no measurements. Last updated: 2026-10-10.
The approved milestones 7–8 plan governs D1–D4 scheduling. This document and
`scripts/benchmarks/native_frontend/` describe the private control contract.
Historical 2026-10-08 results are context, not a frontend-removal baseline.

## Controls and fixture

Compare pinned Rails, fresh pre-removal hybrid Phoenix, then the final native
candidate. Freeze source commits and clean build contexts before building.
Record image IDs and SHA-256 of the files actually running, not merely the build
tag. Phoenix controls/candidate use Elixir 1.20.4/OTP 27. Rails uses Ruby 3.4.9,
YJIT, two Puma workers with five threads each. Architectures must match.

| Resource | CPU | RAM | Swap / runtime |
| --- | --- | --- | --- |
| One app, individually | 2 | 512 then 1024 MiB | no swap; total web pool 10 |
| Private PostgreSQL/PostGIS | 2 | 1024 MiB | no swap; same pinned image |
| Private Redis | 0.5 | 128 MiB | no swap; persistence disabled |
| Generator | 2 | 512 MiB | no swap; k6, 32 preallocated/max VUs |

No separate background workers or offered jobs. In-process services remain
enabled and idle in both controls; report periodic work if observed. Keep host,
timezone, caching, compression and job settings matched. Report Docker/kernel,
image/runtime identities, host contention and unsupported metrics separately.
No absolute capacity, latency SLO or regression percentage is approved by D0.
Calibrate both controls first; ask the controller to approve passing workloads
and SLOs from the measured variation. Higher rates remain exploratory rows.

Generate one synthetic user with 100,000 points, 40 tracks, 40 visits, 20 trips,
20 imports and one monthly stat. Use the same original two-coordinate tracks,
fixed time windows and dense viewport as the historical fixture. No real traces.
Hash deterministic common-schema and seeded-data projections, excluding
credentials, session/API secrets, database names, hostnames and generated
authentication columns. Hash coordinate/data content as well as row counts.
Run schema/seed equality before and after native additive migrations and before
each matrix. Additive Phoenix tables are recorded separately; they do not alter
the common-schema fingerprint. Never hash an environment file or Repo config.
`provenance.matched_controls` refuses different common schema, seeded content,
workload or runtime budgets. `seal` refuses unknown fields and historical
Elixir versions. Every relevant identity change invalidates previous evidence.

## Ownership and capture safety

All Docker command vectors start with `docker --context orbstack`.
The controller supplies the run ID and unique names; all names belong to that
run namespace. Use a private internal network, isolated synthetic DB/Redis,
no published ports and no connection to host/shared/remote services.
Every created resource and built image has both labels:
`org.dawarich.benchmark.run` and
`org.dawarich.benchmark.harness=native-frontend-v1`.

Before creation, `Docker.require_absent` checks every supplied name and refuses
even an already owned resource. Unknown inspection errors fail closed. The only
Docker inspect output allowed is immutable ID, ownership labels and running
state. Never capture full Docker inspect, connection options or process args.
Cleanup first validates the entire supplied list, requires both matching labels,
refuses running containers, and removes by immutable ID. Stop only verified own
containers, then clean containers before the network. No force removal, volumes
flag, global name search or bulk stop. Images remain available for reproduction.
No anonymous data volumes are requested; D1 must use explicitly labelled volumes
with equivalent verification if its image introduces persistence mounts.

Secrets live in private mode-0600 files supplied at runtime, outside the
repository. Docker receives file paths, never inline passwords/tokens. Ruby
commands use `RAILS_ENV=test`, inline private `DATABASE_NAME` and private
`REDIS_URL` under the controller rules; Elixir uses its private test settings.
A production Rails runtime would require an explicit D1 controller exception
to the test-only rule before scheduling; D0 does not silently grant one.
Host Mix commands follow the track runner/runtime settings. Do not alter guarded
Cloud lifecycle files or bypass startup admission for benchmark convenience.

`artifacts.project` accepts only finite nonnegative numeric metrics, defined
boolean/enum fields, known route IDs and projected samples. It drops unknown
fields, raw URLs/queries, cookies, headers, signed sessions, SQL, params,
assigns and exceptions. It never tries to scrub arbitrary exception text.
`artifacts.write` writes exclusively, refuses symlinks/overwrites and uses 0600.
Keep stdout/stderr/server logs private and discard raw logs; publish projected
summaries only. Do not expose query-bearing k6 URLs through system tags or debug
logs. Artifact names use route IDs, phases and scalar counts, never credentials.
RSS sampling is limited to the owned container's processes; no host process
listing. Resource/query/browser probes belong to D3, not D0.

## Command preparation and D1 execution handoff

From the repository root, the implemented commands are:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/benchmarks/native_frontend/tests -v
PYTHONDONTWRITEBYTECODE=1 python3 scripts/benchmarks/native_frontend/cli.py --dry-run
```

The planner imports no Docker client and invokes no commands. Omitting
`--dry-run` refuses execution. Output uses symbolic controller inputs for names,
image IDs, build contexts and private file paths; it reads no environment values.
Its build vectors target `coexistence_runtime` for Rails and `native_runtime`
for fresh hybrid Phoenix, using the frozen source trees' `docker/Dockerfile`.
Hybrid frontend identity means the pre-removal bridge/assets/routes at that
source commit; prove it on preflight, not from a target name. Do not reuse the
historical Elixir 1.18.3 image. Pin local PostGIS, Redis and generator image IDs.

The returned setup vectors are preparation for D1, not a runnable complete
deployment. D1 must adapt the historical seed/session/preflight/k6 executor,
attach its read-only harness and private session files, check image mount
behavior, verify runtime pool/scheduler settings and wire every mutation through
ownership checks. Add no database credentials to generated/public commands.
Historical scripts remain read-only and must never be executed directly: they
use implicit Docker context, global names, raw logs and an obsolete SLO.

Preflight all ten workload URLs at low rate, without recording secrets: full
JSON semantics, nonempty byte-identical MVT, authenticated HTML identity and
fixture content. Migrated pages need semantic checks, not old markup equality.
Only validated responses count as goodput; D1 adds its named goodput/report tests.

The dry-run emits 120 ordered app exposures and 240 measured trials:
two RAM caps × three repetitions × ten routes × two controls × two phases.
Reverse app and route order on repetition two. Each exposure starts a fresh
app, warms for 30 s, measures the lower rate for 60 s, then higher for 60 s,
with up to 10 s drain after each phase. Higher follows lower and is more warmed;
compare controls within phases, not across them. Rates are in `workload.json`:
HTML 10/100; points 50/300; tracks 5/100; stats/visits 20/200; MVT 2/8 RPS.
The minimum allocated workload/drain time is 20,400 s (5 h 40 min), plus
startup, calibration, fixture/preflight and cleanup. Reserve 6–7 quiet hours
after separate image builds; split by cap if the controller cannot reserve this.
No concurrent browser/full-suite/load profiles. No host stress generators.

Retain every error, timeout, dropped arrival, generator limit, OOM/death and
invalid/skipped trial. Record achieved starts/completions/valid goodput and
completed-response p50/p95/p99 per trial; these quantiles exclude missing work.
Keep app RSS distinct from cgroup working set/current/peak and BEAM memory.
Do not erase overload rows or describe their partial goodput as passing capacity.

D2 validates signed LiveView join/diff/ref/event/heartbeat/reconnect against a
real browser before cohorts 1/10/50. HTTP101 alone is never a mounted user.
D3 adds query/resource/JS/lazy-worker/map lifecycle probes. D4 repeats matched
final-source trials and derives regression tolerances from control variation.
None of those measurements, validation adapters or execution gates ran in D0.

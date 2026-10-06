# Native Prometheus metrics (A12f-3o tasks 5–11)

The native web runtime supervises one TelemetryMetricsPrometheus.Core reporter
when `PROMETHEUS_EXPORTER_ENABLED` is exactly `true`. It opens no scrape
listener of its own. The idle worker role starts no reporter, Repo, Redis or Oban.
The development Procfile selects the native web endpoint.

GET/HEAD `/metrics` uses the normal native route metadata, host authorization
and SSL/proxy policy, with the existing limiter immediately after ForceSSL. It works in self-hosted and Cloud deployments. Disabled
returns 404 before authentication; missing/malformed/wrong Basic authentication
returns 401 with `Basic realm="Dawarich Metrics"` and body `Unauthorized`.
Basic scheme matching is case-insensitive, as in Rack. Valid `METRICS_USERNAME`/`METRICS_PASSWORD` returns
`text/plain; version=0.0.4`. Both credential comparisons hash to fixed lengths
and use constant-time comparison. Like the Rails constants, unset credentials
compare as empty strings; there is no invented default credential.

## Rails contract pinned at synced 1.15.3

Source: `config/initializers/yabeda.rb`, `config/routes.rb`,
`lib/dawarich/{metrics_basic_auth,aggregating_metrics}.rb`,
`app/services/{points/raw_data/*,imports/extraction_monitor}.rb`, and installed
Yabeda Rails/ActiveRecord/Puma/Sidekiq adapters. Native runtime metric names
change because the runtime changes. Application metric names remain stable.

| Rails family | Native family | Meaning / bounded labels |
| --- | --- | --- |
| rails_requests_total / rails_request_duration | dawarich_web_requests_total / dawarich_web_request_duration_seconds | method, route template, status; native time converted to seconds |
| Rails error responses | dawarich_web_errors_total | route template; includes HTTP error responses and rendered native exceptions without double counting |
| Puma running/request pressure | dawarich_web_active_requests | requests currently in the endpoint pipeline |
| activerecord_queries_total / query_duration | dawarich_db_queries_total / query_duration_seconds / errors_total | Repo module, no SQL or params |
| ActiveRecord pool busy/idle/waiting/size | dawarich_db_pool_busy / ready / waiting / size | DBConnection pool pressure, sampled every 15 seconds |
| ActiveRecord pool checkout time | dawarich_db_queue_duration_seconds | per-query pool wait, native time converted to seconds |
| process runtime | dawarich_runtime_memory_bytes / processes | BEAM total memory / process count, sampled every 15 seconds |
| sidekiq_jobs_executed/success/failed_total | dawarich_jobs_executed/success/failed_total | Oban start/success/exception, queue and worker |
| sidekiq_job_runtime / job_latency | dawarich_jobs_runtime_seconds / latency_seconds | completed and failed job histograms, queue and worker |
| Sidekiq queue/scheduled/retry/dead/busy gauges | dawarich_jobs_depth / busy / queue_latency_seconds / running_runtime_seconds | queue and persisted Oban state; includes native release workers |
| native delivery debt | dawarich_outbox_debt / oldest_due_seconds | due, scheduled, quarantined public.job_outbox rows |
| coexistence reverse debt | dawarich_commands_debt / oldest_due_seconds | due, leased, retrying, dead reverse commands |

No native metric claims an inert worker is a Sidekiq process. Queues and states
are reset to zero as work completes. Database debt collectors use bounded
statement timeouts on a periodic sampler, never scrape-time SQL. Failed debt reads retain the last valid sample.

Web/query buckets (seconds): 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1,
2.5, 5, 10, 30, 60, 120, 300, 600. Job buckets retain the source long-running
bounds: 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60,
120, 300, 1800, 3600, 21600. Native web histograms measure the whole endpoint
pipeline, not Rails view/db subspans. Pool busy is configured capacity minus
ready connections; ready/waiting are DBConnection measurements.

## Stable application families

| Family suffix (with dawarich_archive_ prefix) | Type | Labels / buckets |
| --- | --- | --- |
| operations_total | counter | operation, status |
| points_total | counter | operation: added, removed, restored |
| compression_ratio | histogram | encrypted/compressed blob bytes divided by original JSONL bytes; 0.1 through 1.0 in 0.1 steps |
| size_bytes | histogram | 1000000, 10000000, 50000000, 100000000, 500000000, 1000000000 |
| count_mismatches_total | counter | year, month |
| count_difference | gauge | user_id (retained intentional source label); absolute mismatch |
| verification_duration_seconds | histogram | status; 0.1, 0.5, 1, 2, 5, 10, 30, 60 |
| verification_failures_total | counter | check; stable native verifier failure enum, no exception message |

Archive producers emit during real archive/verify/clear/restore operations;
Unlinkable batches retain the archive/skipped outcome. Real concurrent deletion is covered by the mismatch gauges. Instrumentation does not change their storage, lock, return or failure contracts.
The extraction gauges retain
`dawarich_imports_extraction_oldest_age_seconds{state="pending|running"}` and
`dawarich_imports_extractions_stalled`. The existing supervised relay heartbeat
collects them every 10 seconds while metrics are enabled. Missing/unreadable ISO
start times count as stalled; the six-hour threshold is inclusive. Completed
and empty in-flight sets reset both ages and stalled count. Ages use DB time.
Native state producers store ISO8601 starts; arbitrary legacy non-ISO Rails
Time.zone.parse inputs are not covered by this implementation's parser.

## Optional Cloud drain source

Only an explicitly configured `SIDEKIQ_METRICS_URL` enables aggregation.
Requests use the internal Basic metrics credentials and bounded five-second
connect/read waits. Non-200 responses, transport failures and exceptions leave
the local scrape available. HELP/TYPE metadata is unique; identical raw source
series identities gain `process="web"` and `process="sidekiq"` labels.
Existing process labels and noncolliding samples are retained. This is an
operator scrape only, never web hand-back. Remove the target after G49; there
is no default Rails exporter target or Ruby dependency in the native exporter.
No backend was contacted during tests.

## Task 10 prerequisite gap and minimum seam

At the allocated baseline `8d6368fc3`, the plan's proposed owners
`points/move.ex`, `map_edits/publisher.ex`, and
`dawarich_web/api/tiles_controller.ex` do not exist. A census finds no equivalent
native point-position mutation, map publisher or tile request flow.
The move/tile port belongs to sync/route closure, not this metrics cut.

`Dawarich.Metrics.Map.definitions/0` supplies the retained eight map families,
buckets and labels as the minimum integration seam:

- `[:dawarich, :map, :move]`: count, duration, lock_wait, track_points,
  track_segments; metadata outcome. Times are native units.
- `[:dawarich, :map, :post_commit_failure]`: count; metadata operation.
- `[:dawarich, :map, :tile]`: count, duration; metadata layer, outcome.
  Duration is native units.

Map names: point_moves_total, point_move_duration_seconds,
point_move_lock_wait_seconds, point_move_track_points,
point_move_track_segments, post_commit_failures_total, tile_requests_total,
tile_request_duration_seconds, all under `dawarich_map_`.
Exact buckets are retained from Yabeda. There are no fake producer emissions.

Task 10 is **not complete**: its real move/tile/publish test and
M-F3O-MAP post-commit mutation require those native owners. No direct telemetry
test is claimed as producer proof. Do not accept map observability until the
owners emit these events and the prescribed real-flow test/mutation passes.

## Verification boundary

The assigned report records each named RED/GREEN/mutation/restored-GREEN run,
source oracle, branch commits and final compile/format/404/202/gitleaks gates.
This does not establish browser, Docker or release acceptance.
AFFiNE writes are prohibited by the assignment's security-sensitive delegate
rule; this repository document is the code-coupled handoff.

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
Queue latency uses only due available/retryable jobs. Executing jobs contribute
to running runtime independently; an executing-only queue has zero latency.

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
the local scrape available. HELP/TYPE metadata is unique; series with identical
metric names and parsed label maps gain `process="web"` and `process="sidekiq"`
labels, regardless of label order. Quoted values, escaped quotes, backslashes
and newlines are parsed for identity; original label text is retained in output.
Existing process labels and noncolliding samples are retained. This is an
operator scrape only, never web hand-back. Remove the target after G49; there
is no default Rails exporter target or Ruby dependency in the native exporter.
No backend was contacted during tests.

## Map application producers

`Dawarich.Metrics.Map.definitions/0` retains the eight Rails 1.15.3 map
families. The native owners are `Dawarich.Points.ApiPosition`,
`Dawarich.Points.PositionEffects`, `Dawarich.MapEdits.Publisher`, and
`Dawarich.Tiles.Http` through the point/track tile controllers.

| Family (with dawarich_map_ prefix) | Type | Labels / buckets |
| --- | --- | --- |
| point_moves_total | counter | outcome: success, conflict, timeout |
| point_move_duration_seconds | histogram | outcome; 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3 |
| point_move_lock_wait_seconds | histogram | outcome; 0.001, 0.005, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3 |
| point_move_track_points | histogram | no labels; 1, 100, 1000, 10000, 50000, 100000 |
| point_move_track_segments | histogram | no labels; 0, 1, 5, 10, 25, 50, 100 |
| post_commit_failures_total | counter | operation: publish, broadcast, stats, achievements |
| tile_requests_total | counter | layer: point_tiles, track_tiles; outcome |
| tile_request_duration_seconds | histogram | layer, outcome; 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3, 5 |

The move event `[:dawarich, :map, :move]` carries count, duration, lock_wait,
track_points and track_segments, with outcome metadata. Duration includes
synchronous publication and follow-up scheduling. Lock wait measures acquisition
of the track and point row locks. Successful tracked moves report the non-anomalous
recalculation point count and segment count. Conflicts retain the source default
of one point and the current track's segment count. Timeouts report one point and
zero segments, retaining the lock wait if acquisition completed; an acquisition
timeout reports zero lock wait. Untracked moves report one point and zero segments.
Invalid coordinates/history, authorization failures and missing points do not emit
move outcomes, matching the source service boundary.

`[:dawarich, :map, :post_commit_failure]` carries count and operation.
Tile-epoch/publication orchestration uses publish; the publisher separately records
broadcast exceptions and failed transport results. Stats and achievement scheduling
failures retain their respective operation labels. These rescued failures preserve
the committed point write and its successful move outcome. Tile epoch and
publication run in separate rescue boundaries, so a failed tile epoch does not
suppress the point-moved event. Stats retain standalone-aware
`Dawarich.Stats.Schedule.calculate`; achievements use
`Dawarich.Points.NativeEffects.achievements`, which produces native jobs in
standalone mode and the existing reverse command in coexistence mode.

The tile event `[:dawarich, :map, :tile]` carries count and duration, with layer
and outcome metadata. It measures the tile action after authorization: 200/204
map to success, 304 to not_modified, 400 to invalid, 503 to failure, and other
statuses to http_<status>. Conditional, empty and error responses each emit once.
All times use native units in telemetry and convert to seconds at the reporter.
No point IDs, users, coordinates, SQL or exception messages become map labels.

The real-flow test in `app-phoenix/test/dawarich/metrics/map_test.exs` covers
tracked and untracked moves, conflicts, cancellation before/after acquisition,
actual row-lock contention, all four post-commit operation labels, native tile
controllers and real SQL failures at the shared tile-query seam. It checks the
scraped counters, histogram counts/sums, native-time conversion and exact buckets.
M-F3O-MAP suppresses the post-commit failure event and must fail this test.

## Verification boundary

The assigned report records each named RED/GREEN/mutation/restored-GREEN run,
source oracle, branch commits and final compile/format/404/202/gitleaks gates.
This does not establish browser, Docker or release acceptance.
Review regressions cover reordered Rails/native archive labels and independent
queue latency/runtime gauges. DB assertions compare real query/error count
deltas and histogram sums with native telemetry converted to seconds. A real
single-connection pool proves busy/waiting values during checkout contention,
queue-duration conversion, and pressure reset after the client completes.
The map-effect integration contract is synchronized with the AFFiNE document
`Dawarich — Phoenix map move metrics and post-commit effects`
(`docId: yjj5hxEfF-DZJjCSVy_-o`). This repository document remains the
code-coupled handoff.

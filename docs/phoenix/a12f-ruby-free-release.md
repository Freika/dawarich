# Phoenix Ruby-free release: operator contracts

Baseline: Rails 1.15.3 integrated at `8d6368fc3187db758151a4d401547d93612d26bb`.
Controller rulings dated 2026-10-05 govern the first Phoenix release. This
document records the shared operator contract and the A12f-3o tasks 1–4 and
18–20 changes. The source telemetry census below pins names and configuration; native metrics
and Sentry owners document their implementation mappings;
A12f-4 owns final runtime activation and image acceptance.

## Shared operator contract

| Surface | Rails source contract | Phoenix disposition |
|---|---|---|
| `/sidekiq` | Admin session; self-hosted, or Cloud with both `SIDEKIQ_USERNAME` and `SIDEKIQ_PASSWORD` present. Cloud also challenges with Rack Basic auth. Unauthorized root GET redirects temporarily to `/` and sets error flash `You are not authorized to perform this action.` | GET/HEAD temporarily redirect authorized operators to `/settings/background_jobs`; retain role and Cloud Basic restrictions. No Sidekiq CRUD replacement. |
| `/api-docs`, `/api-docs/index.html` | Public rswag UI; Basic auth is disabled in `config/initializers/rswag_ui.rb`. | Public locally served Swagger UI, subject to existing host and SSL policy. |
| `/api-docs/v1/swagger.yaml` | `swagger/v1/swagger.yaml`, OpenAPI 3.0.1, title Dawarich API, version v1; rswag has no rewriting filter. | Exact stored bytes and `text/yaml`; HEAD has the same headers and no body. No generated alternate schema. |
| `/admin/flipper` and nested paths | Admin Flipper engine. `FeatureFlags` gates no behavior. | Terminal native 404; no alternate flag UI. Stored tables and historical migrations remain. |
| `/metrics` | Enabled only by exact `PROMETHEUS_EXPORTER_ENABLED=true`; Basic auth `METRICS_USERNAME`/`METRICS_PASSWORD`, realm `Dawarich Metrics`, including self-hosted. | Required native equivalent, owned by A12f-3o tasks 5–11. |
| Sentry/GlitchTip | `SENTRY_DSN`; `SENTRY_TRACES_SAMPLE_RATE` default 0.05, `SENTRY_PROFILES_SAMPLE_RATE` default 0.1. Logs default off; `SENTRY_ENABLE_LOGS` is case insensitive. | Required in the first release, owned by A12f-3o tasks 12–17. |
| Server PostHog | Cloud only, nonblank `POSTHOG_API_KEY`; `POSTHOG_HOST` defaults to EU ingestion. Rails captures rescued/unhandled and ActiveJob exceptions and user ID context; test mode suppresses delivery. | Retired. No native server client, boot child, identify/capture or telemetry forwarding. Browser PostHog remains with its existing owner. |
| Heroku `app.json` | Node and Ruby buildpacks, Dokku Rails migration hook and health check. | Retired; Docker is the supported Phoenix deployment. |

Rails normalizes `SELF_HOSTED` using true/1/yes/on/t, case folding, quotes and
whitespace. Native `LayoutAssigns.self_hosted?/1` retains this contract.
`RailsAuth` reuses encrypted Rails sessions and remember cookies. Redirects
must keep a fixed local destination and never derive it from query parameters.
Hand-back keys apply before native router pipelines during coexistence.

## Telemetry and lifecycle boundary

The shared source oracle is `config/routes.rb`, initializers `01_constants`,
`03_dawarich_settings`, `rswag_api`, `rswag_ui`, `sentry`, `yabeda`, `sidekiq`,
`prometheus_metrics_store`, `posthog`, plus `lib/dawarich/metrics_basic_auth.rb`,
`aggregating_metrics.rb` and `lib/sentry_log_redactor.rb`.

Source metrics aggregate web and Sidekiq exposition, deduplicate HELP/TYPE,
and distinguish colliding samples with `process=web|sidekiq`; a failed remote
scrape keeps local metrics. `SIDEKIQ_METRICS_URL` defaults to the internal
Sidekiq port 9394. Web process aggregation uses a shared mmap store, retaining
files of live PIDs during rolling restarts. The following census pins the
synced source declarations; native exporter mappings remain with their owner.

### Source metric census

Names below are Prometheus family names. `yabeda-prometheus` 0.9.1 joins group,
metric and declared unit with underscores; application metrics already contain
their semantic units in the name. `—` means no labels or no finite buckets.
Each histogram also exports `_bucket` (adding `le`, including `+Inf`), `_sum`
and `_count`. Counters count events/items; gauges are snapshots, even where
a gauge name ends in `_count`. Collision-only `process=web|sidekiq` labels
are added by `Dawarich::AggregatingMetrics`, independently of these declarations.

Application declarations: `config/initializers/yabeda.rb`. Emissions come from
`app/services/points/raw_data/{archiver,clearer,restorer,verifier}.rb`,
`points/move.rb`, `map_edits/publisher.rb`, vector-tile controllers and
`imports/extraction_monitor.rb`.

| Family | Type | Unit | Labels | Finite buckets |
|---|---|---|---|---|
| `dawarich_archive_operations_total` | counter | operations | operation, status | — |
| `dawarich_archive_points_total` | counter | points | operation | — |
| `dawarich_archive_compression_ratio` | histogram | ratio | — | 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0 |
| `dawarich_archive_count_mismatches_total` | counter | mismatches | year, month | — |
| `dawarich_archive_count_difference` | gauge | points | user_id | — |
| `dawarich_archive_size_bytes` | histogram | bytes | — | 1000000, 10000000, 50000000, 100000000, 500000000, 1000000000 |
| `dawarich_archive_verification_duration_seconds` | histogram | seconds | status | 0.1, 0.5, 1, 2, 5, 10, 30, 60 |
| `dawarich_archive_verification_failures_total` | counter | failures | check | — |
| `dawarich_map_point_moves_total` | counter | moves | outcome | — |
| `dawarich_map_point_move_duration_seconds` | histogram | seconds | outcome | 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3 |
| `dawarich_map_point_move_lock_wait_seconds` | histogram | seconds | outcome | 0.001, 0.005, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3 |
| `dawarich_map_point_move_track_points` | histogram | points | — | 1, 100, 1000, 10000, 50000, 100000 |
| `dawarich_map_point_move_track_segments` | histogram | segments | — | 0, 1, 5, 10, 25, 50, 100 |
| `dawarich_map_post_commit_failures_total` | counter | failures | operation | — |
| `dawarich_map_tile_requests_total` | counter | requests | layer, outcome | — |
| `dawarich_map_tile_request_duration_seconds` | histogram | seconds | layer, outcome | 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3, 5 |
| `dawarich_imports_extraction_oldest_age_seconds` | gauge | seconds | state | — |
| `dawarich_imports_extractions_stalled` | gauge | extractions | — | — |

Pinned collector declarations are in the bundled gems identified in
`Gemfile.lock`: `yabeda-rails` 0.11.0 (`lib/yabeda/rails.rb`),
`yabeda-sidekiq` 0.12.0 (`lib/yabeda/sidekiq.rb`),
`yabeda-activerecord` 0.1.2 (`lib/yabeda/active_record.rb`) and
`yabeda-puma-plugin` 0.9.0 (`lib/puma/plugin/yabeda.rb`). Shared bucket sets:

- **WEB**: 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60, 120, 300, 600.
- **JOB/SQL**: 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60, 120, 300, 1800, 3600, 21600.

| Family | Type | Unit | Labels | Finite buckets / condition |
|---|---|---|---|---|
| `rails_requests_total` | counter | requests | controller, action, status, format, method | — |
| `rails_request_duration_seconds`, `rails_view_runtime_seconds`, `rails_db_runtime_seconds` | histogram | seconds | controller, action, status, format, method | WEB |
| `rails_apdex_target_seconds` | gauge | seconds | — | Only when `YABEDA_RAILS_APDEX_TARGET` is configured |
| `sidekiq_jobs_enqueued_total` | counter | jobs | queue, worker | — |
| `sidekiq_jobs_rerouted_total` | counter | jobs | from_queue, to_queue, worker | — |
| `sidekiq_jobs_executed_total`, `sidekiq_jobs_success_total`, `sidekiq_jobs_failed_total` | counter | jobs | queue, worker | Server by default; failed adds error only with label opt-in |
| `sidekiq_running_job_runtime_seconds` | gauge | seconds | queue, worker | Server by default; max aggregation |
| `sidekiq_job_latency_seconds`, `sidekiq_job_runtime_seconds` | histogram | seconds/job | queue, worker | JOB/SQL; server by default |
| `sidekiq_jobs_waiting_count` | gauge | jobs | queue | Cluster collection |
| `sidekiq_active_workers_count` | gauge | busy workers | — | Cluster collection |
| `sidekiq_jobs_scheduled_count`, `sidekiq_jobs_retry_count`, `sidekiq_jobs_dead_count` | gauge | jobs | — | Cluster collection; retry adds queue only with segmentation opt-in |
| `sidekiq_active_processes` | gauge | processes | — | Cluster collection |
| `sidekiq_queue_latency` | gauge | seconds | queue | Cluster collection; no unit suffix declared |
| `activerecord_queries_total` | counter | queries | config, kind, cached, async | — |
| `activerecord_query_duration_seconds` | histogram | seconds | config, kind, cached, async | JOB/SQL |
| `activerecord_connection_pool_size`, `activerecord_connection_pool_connections`, `activerecord_connection_pool_busy`, `activerecord_connection_pool_dead`, `activerecord_connection_pool_idle` | gauge | connections | config | — |
| `activerecord_connection_pool_waiting` | gauge | threads | config | — |
| `activerecord_connection_pool_checkout_timeout_seconds` | gauge | seconds | config | — |
| `puma_backlog` | gauge | connections | index | — |
| `puma_running`, `puma_busy_threads`, `puma_pool_capacity`, `puma_max_threads` | gauge | threads | index | — |
| `puma_requests_count` | gauge | requests since worker start | index | — |
| `puma_workers`, `puma_booted_workers`, `puma_old_workers` | gauge | workers | — | Clustered Puma only |

Puma metrics use most-recent aggregation and require the control app enabled
by `config/puma.rb` when metrics are enabled. Rails buckets may be overridden
with `YABEDA_RAILS_BUCKETS`; SQL buckets with `YABEDA_ACTIVERECORD_BUCKETS`.
Rails controller names default to snake case (`YABEDA_RAILS_CONTROLLER_NAME_CASE`);
`YABEDA_RAILS_IGNORE_ACTIONS` defaults to empty. Sidekiq
`YABEDA_SIDEKIQ_DECLARE_PROCESS_METRICS` and
`YABEDA_SIDEKIQ_COLLECT_CLUSTER_METRICS` default to server-only.
`YABEDA_SIDEKIQ_RETRIES_SEGMENTED_BY_QUEUE` and
`YABEDA_SIDEKIQ_LABEL_FOR_ERROR_CLASS_ON_SIDEKIQ_JOBS_FAILED` default false.
Cluster gauges use most-recent aggregation. Exporter debug instrumentation is
not enabled by the app; if Yabeda debug is enabled it additionally declares
`prometheus_exporter_render_duration_seconds` (histogram, no labels; buckets
0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10).

### SDK configuration census

| Input | Source default / behavior | Phoenix requirement |
|---|---|---|
| `SENTRY_DSN` | Unset: initializer returns without initializing SDK; shared Sentry/GlitchTip DSN | Retain the deployed DSN contract |
| `SENTRY_TRACES_SAMPLE_RATE` | 0.05, parsed with `to_f` | Record SDK capability differences; do not claim unsupported tracing |
| `SENTRY_PROFILES_SAMPLE_RATE` | 0.1, parsed with `to_f` | Record SDK capability differences; do not claim unsupported profiling |
| `SENTRY_ENABLE_LOGS` | false; only case-insensitive true opts in | Errors remain independent of optional log forwarding |
| `SENTRY_CURRENT_ENV`, `SENTRY_ENVIRONMENT`, `RAILS_ENV`, `RACK_ENV` | First present in this order; fallback development (sentry-ruby 7.0.0) | Preserve deployment environment resolution |
| `POSTHOG_API_KEY` | Unset/blank or self-hosted: no source client | Retired server integration |
| `POSTHOG_HOST` | `https://eu.i.posthog.com` | Ignored by native server |
| `POSTHOG_PERSONAL_API_KEY` | nil; optional source feature-flag evaluation | No native server client |

Source Sentry uses active-support logger breadcrumbs, leaves Rails structured
logging disabled, and forwards INFO-or-higher Rails logs only on log opt-in.
PostHog source enables automatic rescued/unhandled and ActiveJob exceptions
and authenticated user ID context, queue limit 10000, feature-flag polling
30 seconds and request timeout 3 seconds; test mode suppresses delivery.
These source SDK settings are a census, not native delivery acceptance.

Source Sentry logs redact password/token/key/authorization/OTP/payment attributes
and email addresses. Phoenix must report real web, LiveView, Oban and release
command exceptions without additional PII; configuring an SDK alone does not
close that requirement. Native release seams are `Dawarich.Release`,
`Release.Lifecycle`, `CLI` and `Application.start/2`; `Front.children/2` still
selects coexistence at this baseline. No external DSN or analytics account is
needed for characterization.

Rails Flipper gems/initializer and PostHog gems/initializer remain read-only
oracles until A12f-4 task 22. Historical Flipper migrations remain native data
compatibility, not a live operator dependency. The existing Phoenix dependency
list, runtime configuration and application supervision contain no server
PostHog SDK or producer. `components/head.ex` still includes the browser script
when `POSTHOG_ENABLED=true`.

## Verification ownership

The source characterization batch has 39 examples and zero failures on the
allocated private Rails database. Swagger is copied aside and restored around
RSpec. Native task tests must prove routing, auth and terminal retirement
through Endpoint without a Rails request. Controller ruling 14 sets full ExUnit seed 404 as
the branch gate; seed 202 belongs to the integration head after each merge batch. Real Swagger rendering, release asset packaging and
Docker/Cloud smoke remain A12f-4/G44 release evidence; HTML assertions alone
do not establish image acceptance.

## Legacy Sidekiq redirect

GET/HEAD `/sidekiq` returns 302 with a fixed local Location
`/settings/background_jobs`; queries cannot select the destination. Guests and
nonadmins receive the source home redirect and Rails-compatible error flash.
Cloud admins need both configured Sidekiq credentials and the existing Basic
challenge (realm `Restricted Area`); credentials are compared as SHA-256
digests with constant-time comparison. Other Sidekiq methods/subpaths remain
outside this root redirect during coexistence.

The baseline JobHealth component lived on instance settings, rather than the
background page named in the plan. The existing component is reused on the
background page for admins only. The minimum Cloud destination seam extends
`AdminGate` and `AdminLiveAuth` for this read page, retaining the settings
hand-back key, supported user state, session identity and role rechecks.
HTTP GET/HEAD on the destination challenges missing or incorrect Cloud Basic
credentials before rendering. A successful Cloud request issues a random grant
in the encrypted, HttpOnly Phoenix session cookie. Redis holds its binding to
the authenticated Rails login, actor and current Basic configuration, with a
non-sliding one-hour expiry. Neither the grant nor Basic credentials are placed
in the signed, client-readable LiveView page token. Connected mounts use only
the current cookie context, including the Rails login identity independently
derived by SessionStore; an authorized page token cannot authorize another login.
The verified Rails authentication result is reused only within its request;
each fresh websocket request independently authenticates its current cookies.
Redis misses/errors, expiry, deletion, credential rotation and demotion reject
connected access. Reload the page with Basic credentials to obtain a new grant.
The existing private cache Redis connection stores these grants; Cloud HTTP
authorization returns 503 if grant storage is unavailable.

`LiveSocket` routes LiveView messages through `AuthorizedLiveChannel`, which
rechecks operator/admin authorization before delegating to the pinned framework
channel. This includes built-in `lv:clear-flash`, component events and internal
info messages that bypass ordinary lifecycle hooks. Ordinary LiveViews delegate
unchanged; uploads retain their existing channel. Lifecycle hooks also remain
for params and role refresh. The wrapper depends on the pinned channel's state
and callback contract, so framework upgrades must retain the real endpoint
channel regression. Authorized reconnects use the existing grant until expiry.
Self-hosted demotion clears the
cached health assign and hides the card while retaining background settings.
Self-hosted nonadmins still see their ordinary background settings. Cloud
nonadmins receive no operator access. Detailed job mutations and other Cloud
admin pages remain with A12f-3 task 17. ED-346 records the intentional UI change;
source fixture comparison still verifies the complete preexisting markup, and
separately verifies the added admin-only health card.

Shared decision history: AFFiNE `Dawarich — ADR-20261006-operator-session-grants
— Bind Cloud LiveView authorization to the current login`, document
`lhm4h4Ab4OmJufkmL-5dR`. The shared operator index is document
`GMf1eWxYiCJBDeGAzmf0F`.

## Native OpenAPI ownership

The operator router explicitly owns GET/HEAD docs and the v1 YAML on both
self-hosted and Cloud, with no self-hosted slice. Existing host authorization,
SSL, rate-limit and response-header plugs run normally. Unknown versions and
methods within `/api-docs` terminate with native 404. Coexistence can still
hand the namespace back using `DAWARICH_RAILS_ROUTES=api-docs`.
The YAML remains `swagger/v1/swagger.yaml`; A12f-4 task 15 must retain that
exact file in the final runtime image. No source bytes changed here.

## Swagger UI distribution

`swagger-ui-dist` is pinned to 5.33.1 in the existing npm lockfile. The UI
initializes SwaggerUIBundle with `/api-docs/v1/swagger.yaml`, local bundle/CSS,
deep linking and the built-in API preset. `validatorUrl: null` prevents sending
the document to an external validator. No CDN, alternate spec or standalone
preset is required. [Swagger installation documentation](https://swagger.io/docs/open-source-tools/swagger-ui/usage/installation/)
describes the distribution bundle used here.

The Docker builder copies exactly `swagger-ui-bundle.js`, `swagger-ui.css` and
`LICENSE` into `/out/public/api-docs`; the runtime COPY puts them in
`/var/app/public/api-docs`, before `public_dist` is staged for volume sync. The
ApiDocs handler only serves those filenames. PublicFiles leaves the namespace
to the normal Strangler/operator pipeline, so public static files cannot bypass
its hand-back, host or SSL policy or expose other npm artifacts. Native tests
copy the real installed distribution into an isolated public root and verify
served bytes, types, HEAD and denied extra files even with production static
serving enabled. A12f-4 must retain these COPY steps and the Swagger YAML while
removing Ruby from the image, then run the real UI/browser/image acceptance.

## Flipper retirement

`/admin/flipper` and all nested paths return an empty native 404 for every
method, hosting mode and user role. Explicit `retired: true` route metadata
keeps these approved retirements terminal even if the broader admin namespace
is pinned back during coexistence; no other routes bypass hand-back. The old
Flipper-specific rate-limit rule is removed. Tables and historical migrations
are untouched; Rails engine/gems/initializer removal stays A12f-4 task 22.

## Docker deployment and Heroku retirement

Docker is the supported Phoenix deployment for self-hosted installations and
Cloud. The removed `app.json` is retained in the Rails 1.15.3 reference at
`8d6368fc3187db758151a4d401547d93612d26bb`: it selected Node/Ruby buildpacks,
`bundle exec rails db:migrate` as a Dokku predeploy hook, and
`/api/v1/health` as startup health. Those buildpack and manifest deployment
paths are retired; there is no Phoenix Heroku replacement or support promise.

This operator branch does **not** activate the Ruby-free runtime. A12f-4 owns
final entrypoint/Procfile mapping, removal of Ruby, and Docker/Cloud/release
smoke. The current A12h opt-in `DAWARICH_PHOENIX_LIFECYCLE=true` requires
self-hosted mode and still refuses Cloud; it must not be presented as the
final Cloud deployment switch. Follow [A12h lifecycle](a12h-lifecycle.md) for
the current coexistence behavior. Use the following contracts with the
qualified release image after the controller completes A12f-4.

### Self-hosted compose contract

Use `docker/docker-compose.yml` with a pinned release image and your existing
PostGIS and Redis services. Redis remains required in A12f. The public web
port stays 3000, with host mapping `${DAWARICH_APP_PORT:-3000}:3000`. Set
`APPLICATION_HOSTS`, `APPLICATION_PROTOCOL`, `SELF_HOSTED`, database selectors
and `REDIS_URL` for your installation; preserve the existing `SECRET_KEY_BASE`
and encryption keys so stored sessions and encrypted data remain readable.
Keep credentials outside version control. The retained web argv
`bin/rails server -p 3000 -b ::` is a compatibility input to the native front
in the final image; it does not require a Ruby runtime there.

Persist the existing volume destinations:

| Destination | Purpose |
|---|---|
| `/var/app/public` | Served assets, including local Swagger UI; refreshed from image `public_dist` at boot. |
| `/var/app/storage` | Local attachment and generated-media objects. |
| `/var/app/tmp/imports/watched` | Watched import inbox. |
| PostgreSQL data directory | Location data, public ledger/outbox and private Phoenix/Oban schemas. |
| `/var/app/tmp` or an explicit `DAWARICH_COOKIE_FILE` parent | Writable native cookie/runtime path; preserve across CLI and web processes when using remote commands. |

Retain the compose Postgres backup mount `/dawarich_db_data` where your
installation uses it; it is separate from native application schema work.
Use `PUID`/`PGID` for ownership initialization and privilege dropping, rather
than compose `user:`. Run operator commands with the same UID:GID as the web
process, so generated storage and the cookie remain readable.

The qualified self-hosted web entrypoint keeps asset sync and database
creation/wait, then native migrate, seeds and readiness before listeners
start. Native commands are `dawarich migrate`, `dawarich seeds`,
`dawarich migrate status` and `dawarich eval 'Dawarich.Release.halt_unless_ready()'`.
Upgrade from Rails 1.15.3; older databases must first reach that retained Rails
upgrade boundary. Refusals stop boot rather than hiding failed migrations.
Schema work must have a single migration owner; do not launch simultaneous
old Rails and native boot writers. Preserve the public health URL
`/api/v1/health` and its JSON `status=ok` check; `/api/v1/ready` and `/ready`
are native readiness contracts supplied by A12f-1. Image gates must exercise
the retained healthcheck against the final runtime.

The retained `sidekiq-entrypoint.sh` / `sidekiq` compose service becomes inert
under `DAWARICH_PROCESS_ROLE=sidekiq_idle` in the final cut. It must not migrate,
seed, dequeue or duplicate jobs; native jobs run in the web application. This
branch leaves the real coexistence Sidekiq worker intact. Job-owner keys and
cron activation remain separate controller decisions, not a side effect of
visiting `/sidekiq` or starting an operator page.

### Cloud contract

The qualified Cloud image uses `cloud-entrypoint.sh` for web readiness/start
and `release.sh` for the single native migration/seed release phase. The web
phase does not run migrations or silently fall back to Rails. The old
`cloud-sidekiq-entrypoint.sh` worker slot is inert after the final mapping.
Share existing database/storage and native cookie permissions where required,
keep the web listener behind the existing proxy and host/HTTPS policy, and
configure both `SIDEKIQ_USERNAME`/`SIDEKIQ_PASSWORD` for operator redirects.

Cloud cut-over runs on a new Phoenix-only server. The old Rails 1.15.3
deployment is drain-only during the transition. The controller's A12f-3c
runbook owns traffic switching and rollback: pin new work to Rails, drain
native work to zero, stop Phoenix and start Rails against the same database.
No pending-work transfer or backup restore is implied by these Docker docs.
Backups remain ordinary pre-upgrade operator hygiene.

A12f-4 must run existing image/cloud/release smoke and Swagger UI browser
acceptance on the same qualified candidate. This branch has not built or
started a deployment image and does not claim those release gates passed.

## Server PostHog retirement

Native boot, web and Oban job execution ignore server `POSTHOG_API_KEY` and
`POSTHOG_HOST`; no PostHog application, supervisor child, telemetry forwarder
or identify/capture producer is retained. The synced baseline already had no
native server analytics seam, so this cut adds a real-flow regression guard
and documentation rather than introducing an unnecessary runtime client.
The guard restarts the native application with synthetic Cloud configuration,
serves the stored YAML through Endpoint and executes the owned version-check
Oban worker against a local HTTP server. A local transport trap rejects any
server analytics request; the required boot-emission mutation is detected.
The browser `app/javascript/posthog.js` and `components/head.ex` include are
unchanged. Rails PostHog initializer and gems remain source oracles until
A12f-4 task 22 removes Rails dependencies.

## A12f-3c current topology and ownership census

Observed 2026-10-06 at `8d6368fc3187db758151a4d401547d93612d26bb`
(Rails 1.15.3 sync already integrated), in `feat/a12f3c-a`. This is a source
census, not a production audit or permission to switch traffic. Cloud means
explicit `SELF_HOSTED=false` throughout this section.

Authority: project plan
`superpowers/plans/2026-10-06-phoenix-a12f-3c-cloud-cutover-drain-plan.md`,
tasks 1, 2 and 5; master `2026-10-05-phoenix-a12f-ruby-free-release-plan.md`,
controller rulings 2, 4 and 7. The controller assigns separate worktrees to
lifecycle, ownership/chains, observation/shutdown and actual image/runtime work.

### Old and new deployment roles

| Role | Current source contract | Required cutover boundary / owner |
| --- | --- | --- |
| OLD web | `Procfile.cloud`: `cloud-entrypoint.sh puma -C config/puma.rb -p 5000`; bootstrap, DB wait, private readiness, Phoenix-supervised Puma or standalone Rails fallback | Stop/unpublish OLD web at traffic switch. It must not be NEW's upstream. Task 5 fences OLD, not HTTP parity. |
| NEW web | No Phoenix-only Cloud selection at this head. `exec_under_phoenix` serializes `bundle exec puma ...` into `DAWARICH_RAILS_ARGS`; `Front.plan` allocates a loopback upstream | A12f-1 supplies native argv/front helpers; task 2 consumes them; A12f-4 owns final boot selection. Port 5000 and declared health contract must survive without Puma or upstream. |
| OLD worker | `cloud-sidekiq-entrypoint.sh sidekiq -C config/sidekiq.yml`; DB wait then `exec bundle exec` | Consume only previously accepted safe source work; fence new roots, children, cron, cache boot and reverse Poller. Task 7 supplies chain eligibility. |
| NEW worker | Existing `DAWARICH_PROCESS_ROLE=sidekiq_idle` selects `Application.children(:sidekiq_idle) == []` | Idle release process, no Repo, Sidekiq, Oban or cron. Native jobs run in NEW web's existing supervision tree. |
| Release/provisioner | Flag-off `release.sh`: Rails public migrations, then `Release.migrate()` private migrations. Native lifecycle is default-off and Cloud refuses in both shell and `Release.Lifecycle` | Package B/L1 supplies real Cloud provisioning, family decoders and account callbacks. NEW release owns migrations/seeds; web readiness observes only. Retain refusals until handoff. |

`app.cloud.json` probes `/api/v1/health` on 5000, startup attempts 10/wait 10.
It defines no predeploy script. Accepted Procfile argv should remain compatible.
Readiness failure currently permits Rails fallback in legacy mode; opt-in NEW
must stop on exits 1/3/4/5. This census does not relabel that coexistence as
native acceptance.

### Shared database, queue, storage and identity

Source Sidekiq uses `REDIS_URL` with `RAILS_JOB_QUEUE_DB` default **1**, independently
of the URL path. Native runtime uses the same queue selector; cache DB defaults
to 0. Source queues are the 23 named queues in `config/sidekiq.yml`; source cron
has 24 registrations in `config/schedule.yml`. Do not use cron loading alone as
a fence: installed sidekiq-cron 2.4.0 ScheduleLoader checks `enabled`, whereas
Launcher constructs the poller from positive `cron_poll_interval` independently.
Stored cron registrations must remain observable through drain.

Both deployments retain the same public rows, `public.job_outbox`, `phoenix.*`
and `oban.*`; private schemas are additive. Rails source public migrations and
native `Release.Native` share the exact Rails advisory key
`2053462845 * crc32(current_database)`. Native also uses migration lease/fences
and recorded release operations. Native migrations own private/Oban ledgers;
ordinary web readiness must not create tables, migrate, seed or invoke callbacks.
Cloud database CREATE/schema-owner rights and L1 provisioning are unproved at
this head; source schema-loading for tests does not prove NEW provisioning.

Registration copy authority is `ReleaseMigrations.V1_13_1.copy_registration_setting`:
the migration owner copies the source Redis cache entry
`dawarich/registration_enabled` into `phoenix.registration_setting`, preserving
an existing native row; a missing cache entry uses the explicit
`ALLOW_EMAIL_PASSWORD_REGISTRATION` environment policy. Copy happens under
existing exclusion. Do not derive it from new self-hosted
account defaults or run an independent web-time copy.

Storage service names remain `test`/`local`/`s3` (`config/storage.yml`,
`Dawarich.Storage.services!`), preserving each blob's stored `service_name` and
key. Local Rails and native layouts use `storage/<key[0:2]>/<key[2:4]>/<key>`;
test service uses `tmp/storage`. NEW/OLD need the same mount/object bucket and
signing/encryption inputs (`RailsSecret`, signed-storage owner A12b). Never copy
secret values into this census. Cloud bootstrap defaults UID/GID to 32767,
reexecutes with `gosu` and `HOME=APP_PATH/tmp`, and changes existing tmp/storage
ownership only when needed. Persistent public asset/storage mounts and access
by the retained 1.15.3 image require actual release-lane proof.

`JobOwnership` and native `Jobs.Ownership` share persisted owners and ordered
`FOR SHARE` effect locks; missing owners mean Sidekiq. The Lite archival cron
and archival mail keys form a joint unit. Owner flips are not permission to
invent an event: `JobCommands.produce` carries payload `source_job_id` into
outbox `event_id`, and `forward` accepts the original explicit ID. Delays,
locale, zone, operation and cron-slot identity must survive accepted forwarding.
Source enqueues made by accepted work are still new application publication;
retry/scheduled bookkeeping is distinct and must remain observable.

### Retained HTTP rows and envelopes

The supplied census lives at project `.scratch/route-ownership/`:
`route-ownership.md`, `classified-routes.json`, `counts.json`, `crosscheck.json`.
It inspected `4628a6659cf75db62b4cb09c813151268b01c630`, not this head: 374
rows (2 native, 195 conditional, 175 Rails, 2 redirect) for its self-hosted stand.
Its Cloud comparison leaves SELF_HOSTED unset, which still defaults true; its
2/184/186/2 totals do **not** prove explicit Cloud=false coverage. No custom
route-census harness or production queries were run here.

| Source registration | Native declaration/gate at this head | Disposition |
| --- | --- | --- |
| GET `/api/v1/health`, GET `/api/v1/ready` (`routes.rb:314–315`) | Neither is declared natively. Source health includes JobHealth; ready queries SQL/Redis and returns 503 on failure | Retained, unsupported natively here. A12f-1/2 owns envelope, status, headers and HEAD parity. No fabricated 200. |
| POST `/api/v1/subscriptions/callback` (`routes.rb:464`) | No native route; source SubscriptionsController owns authenticated subscription/family/cache effects | Retained, A11/A4/A12f-2 owner closure needed: auth, dedupe/watermark, rollback on failure. Route callbacks to NEW only after closure. |
| GET/POST `/users/sign_in` (Devise `routes.rb:268`) | AuthGate credentials handler requires opted-in flow and literal SELF_HOSTED=true | Retained; explicit Cloud=false cannot claim native credentials here. Provider/session tails belong to A11/A12f-2. |
| GET `/rails/active_storage/blobs/proxy/:signed_id/*filename` | Generic storage matching is insufficient; StorageGate explicitly returns false for blob proxy | Retained, A12b/A12f-2 owns signed proxy/representation/envelope parity and HEAD body suppression. |
| GET `/settings/background_jobs` (`routes.rb:66`) | A10Routes declares LiveView; AdminGate.background? requires self-hosted, supported user/settings and admitted GET/HEAD envelope | Retained, Cloud destination closure belongs to A12f-3 task 17/A12f-3o. Query duplicates, client markers and Turbo headers can hand back. |

Native redirects are not retirements. Unsupported Cloud envelopes, HEAD,
formats/content types, authenticated API keys and provider callbacks must be
closed by route owners before NEW is selected. Flipper/server PostHog/Heroku
retirement and Swagger/metrics/error-reporting are A12f-3o decisions, not this
package's changes.

### Accepted source work and native dependencies

The executable class census is `app-phoenix/test/support/rails_job_owners.ex`
and its inventory test: 125 application classes plus framework Active Storage
and Action Mailer jobs. `docs/phoenix/a12d3-schedules-drain.md` retains the
accepted-work dispositions; class labels alone never authorize deletion.
Accepted chains include Trips::CalculateAllJob, Tracks::ParallelGeneratorJob,
Tracks::RealtimeGenerationJob, Tracks::DailyGenerationJob, data migration
point/transportation/anomaly walkers, raw-data archive/verify/clear user chains,
integration schedulers (AirTrail/TeslaMate/Trek), digest scheduling/mail,
GoogleTakeout/GPX resumptions, EnhancedImport extraction and family callbacks.
Task 7 must settle any path requiring a fresh source child before switching.

Current dependencies remain: cache cron wrapper delegates to Rails; native
RailsCommands reverse kinds are not closed; source RailsCommands::Poller starts
on worker startup; cache_jobs publishes Cleaning/Preheating on Rails server boot;
Cloud User callbacks create welcome/explore/Manager and family work; Cloud family
release adapters refuse. L1/J1/J2 and source/native chain collision proofs are
external owner handoffs, not fulfilled by disabling these producers.

Source JobDrain observes queued/scheduled/retry/dead/busy/unknown work and SQL
bridge debt but lacks explicit reserved-fetch observation. Native Drain reports
outbox/reverse/release/Oban/generation/owner debt as observations, not permission
to stop OLD. Tasks 9/10 and actual G49 must close those observations. Ruling 7
rollback pins every key to Sidekiq, drains native work, stops Phoenix, then starts
Rails 1.15.3 on the same DB/storage; no transfer or backup restore is built here.

Baseline characterization: both existing Cloud/lifecycle regression files,
RSpec seed 101, **49 examples, 0 failures**. Swagger was copied aside/restored and no
schema/Swagger drift occurred. Implementation evidence is recorded separately
in `.scratch/orch/out/impl-a12f3c-a.report.md`.


## A12f-3c same-database rollback to Rails 1.15.3

Dated amendment: 2026-10-06, controller rulings 4 and 7. This procedure
supersedes native-to-Sidekiq transfer and snapshot-restore rollback instructions
at this additive boundary. It is manual: no cut-over or rollback script is added.
The controller retains stock Rails **1.15.3**, its actual launch argv and access
to the same database, storage services, object keys and signing/encryption inputs.
Release dates and image-retention windows are Eugene's release-time values
(ruling 11), not implementation blockers.

1. Fence incoming traffic, native/source new roots, cron, boot callbacks,
   subscriptions, manual commands and reverse producers. Keep Phoenix workers,
   relay and accepted native successors alive to finish already accepted work.
   Resolve any remaining native-to-Rails dependency before proceeding.
2. Enumerate **every** `Dawarich.Jobs.Registry.entries()` key and every persisted
   `phoenix.job_owners` row through the retained control plane. Inspect missing,
   unexpected and inconsistent rows; environment opt-ins are not the inventory.
   For each actual expected key invoke existing `dawarich:jobs:release[KEY]`.
   Verify `owner=sidekiq,pinned=true`, joint-key equality and no reacquisition
   after claimer restart. A held lock stops the operation without a partial
   joint flip; wait for its owner to finish. Never force it. Stock 1.15.3 lacks
   these port tools: use the retained coexistence reference, then stop it before
   stock Rails resumes. Do not invoke `rehome`.
3. Drain pre-fence outbox, Oban, recorded release operations, accepted workers
   and durable successors natively. Preserve event UUID, operation/run identity,
   original due time, locale and zone. Future/retry/quarantined/dead native work,
   unfinished generation chunks, reverse debt or unknown owners block rollback;
   pinning neither cancels work nor completes skipped effects. Use native
   `dawarich jobs status` and `dawarich jobs drain-status`, plus retained source
   status/drain observations. Require binary rollback `OBSERVED_EMPTY` with
   `certainty=OBSERVED`, every pin and no unresolved native work. A database or
   Redis read failure, stale registration or unknown payload is BLOCKED, never
   an empty result. Complete package D/task 13 observer handoff is a prerequisite
   to interpreting this checkpoint; an older output without certainty cannot
   satisfy it. Future work waits until due or receives its existing owner remedy;
   no promotion, deletion, transfer or forced acknowledgement is permitted.
4. Gracefully stop Phoenix web/jobs/relay/claimers and the retained control-plane
   helper/Poller. Independently verify process absence and no native writer or
   lease; re-inspect SQL/reverse/release debt after stop. Start stock Rails 1.15.3
   on the **same DB/storage**, using retained release argv. Cloud leaves old
   drain mode only now; if OLD is already stopped, restart its retained image.
   Self-hosted replacement allows downtime. Restore source boot, cron and enqueue
   controls once, after native absence, with incoming traffic still fenced.
5. Verify health/ready, login and cookies, existing API keys, representative
   Phoenix-era rows and fresh Rails writes, signed attachments and object bytes,
   every pin, zero native debt/writers, and exactly one observed source schedule
   slot/effect. Reopen traffic and producers only after these checks. Existing
   external mail/webhook delivery remains at least once across crashes; the
   SQL event collision proofs do not establish exactly-once external delivery.

Test/rehearsal commands run on the retained source reference after Ruby detection.
`KEY` is one inspected actual key, not a new all-keys command. `RDB` and
`TEST_REDIS_URL` are controller-assigned private selectors; never export
`DATABASE_NAME`. Use the detected activation (empty here, represented by true):

```zsh
true && RAILS_ENV=test DATABASE_NAME="$RDB" DATABASE_HOST=127.0.0.1 REDIS_URL="$TEST_REDIS_URL" asdf exec bundle exec rails "dawarich:jobs:release[$KEY]"
true && RAILS_ENV=test DATABASE_NAME="$RDB" DATABASE_HOST=127.0.0.1 REDIS_URL="$TEST_REDIS_URL" asdf exec bundle exec rails dawarich:jobs:status
true && RAILS_ENV=test DATABASE_NAME="$RDB" DATABASE_HOST=127.0.0.1 REDIS_URL="$TEST_REDIS_URL" asdf exec bundle exec rails dawarich:jobs:drain_status
```

Native artifact commands use its existing CLI and assigned DB/Redis environment.
Actual image/process/resource values belong to a separately authorized release
assignment. These commands do not authorize a deployment, SSH or traffic change.

### Additive boundary and staged ADR/G48 amendment

Exact dated amendment for the documentation owners of
[ADR0015](/Users/frey/projects/dawarich/docs/adr/0015-port-every-rails-migration-to-ecto-squashed-per-release.md)
and [release-tier G48](/Users/frey/projects/dawarich/superpowers/plans/2026-10-04-phoenix-release-tier-runbook.md):

> Amendment (2026-10-06), controller rulings 4 and 7: rollback at the first
> Phoenix boundary means retaining Phoenix-era writes and starting Rails 1.15.3
> on the same database/storage after fencing producers, pinning every ownership
> key to Sidekiq, draining all native work to zero without transfer, and stopping
> Phoenix and its control-plane writers. No backup restore or inverse migration
> is part of this procedure. `public.job_outbox`, `phoenix.*` and `oban.*` are
> additive. Public migration `20260925100000` changes `users.settings` defaults
> from 1000 to 500 meters and 60 to 30 minutes; `20260925100100` re-enqueues
> transportation backfills. Both are harmless to Rails 1.15.3, and both remain
> registered in `release_migrations/unreleased.ex`. A future non-additive
> schema/data change reopens ruling 4. Backups remain recommended production
> hygiene. Earlier general downgrade policy and migration decision history are
> retained; this is a bounded exception, not an arbitrary older-image guarantee.

These external inputs are read-only for package P. The amendment is staged here
for their owners; their obsolete snapshot/loss prerequisites are **superseded**
for this boundary, but those external files have not been edited.

### Deferred G48 rehearsal

Use staging/disposable populated Rails 1.15.3 data for **both Cloud and
self-hosted**. Upgrade the exact candidate, write synthetic Phoenix-era rows
and signed storage objects, and arrange pending plus executing native work.
Perform all five rollback steps above; demonstrate native effects and successors
finish with their original identities/due times, without Sidekiq transfer, and
stock Rails retains the post-upgrade data and attachments. An unpinned key and
an unresolved native job must each prevent traffic reopening; remedy them through
existing owner operations and finish the rehearsal. No mirrored automated gate
or fabricated mutation is added for documentation.

Record both image heads, isolated topology, ownership/debt/lease/process
observations, failure remedies and exact row/object/schedule effects in the
existing release-tier report. Reuse
[G02/G42/G47/G48/G49](/Users/frey/projects/dawarich/superpowers/plans/2026-10-04-phoenix-release-tier-runbook.md)
for Cloud topology, final image, upgrade, rollback and old shutdown evidence.
A feature-branch suite, same-image hand-back or a Rails-loaded test schema does
not close G48. Image/storage access and release windows remain release-owner
handoffs; no live rehearsal or acceptance is claimed here.


## A12f-3c operator cut-over and old shutdown handoff

Package P inspection head: `c86ff9db1` (2026-10-06), with Rails 1.15.3 sync,
package A source fences, package C reviewed chain/effect protection and task 2
native Cloud argv mapping integrated. The earlier census above remains historical
at its stated head. These are default-off preparations, not a production census
or release authorization. Explicit Cloud means `SELF_HOSTED=false`.

| Handoff | Current preparation / unresolved release prerequisite |
| --- | --- |
| A, tasks 2/5 | `DAWARICH_CLOUD_DRAIN_ONLY=true` admits only retained OLD Sidekiq argv, rejects web/release/manual boot and fresh roots/enqueues; cron loader disabled **and** `cron_poll_interval=0`; cache boot and reverse Poller disabled. Scheduled/retry transfer of previously accepted work remains observable. |
| Task 2 / A12f-1 | Native opt-in clears inherited Rails argv, maps supported Puma5000/TCP listener args through native helpers, terminates on readiness exits 1/3/4/5, and starts inert `sidekiq_idle` workers. See [native Cloud web handoff](a12f-3c-native-cloud-web.md). Legacy off-mode still coexists. A12f-4 owns the final Ruby-free image/process proof. |
| B/L1, tasks 3/4 | Not present as a completed Cloud proof here: lifecycle explicit Cloud/native opt-in still refuses. Account/trial/family/Manager/mail callbacks, release provisioning without CREATE, read-only web readiness, shared source/native row/object and registration authority proofs remain required. Loading a test schema is not provisioning evidence. |
| C, tasks 6/7 | Ordered effect/owner locks and UUIDv5 receipts coordinate source/native trip effects; accepted due time and root identity survive materialized children. Completed roots add no effects; partial roots finish only missing effects. SQL receipts do not promise exactly-once external delivery. |
| D, tasks 9/13 | Owner report supplies phased source observation and native shutdown/binary rollback contracts. They are **absent at this inspection head**; D review fix is being completed. Require its integrated candidate, named-test audit and final gates before using the new observer output or accepting rollback. |
| E, tasks 8/10 | Existing `cloud_smoke.sh` still characterizes coexistence. Two-deployment traffic switch, installed fetch quiet/settle/TERM and post-stop process/debt proof remain owner/release handoffs, not executed by P. |
| R1/J1/J2/L2/L3 | Retained HTTP envelopes, every source payload/reverse-kind disposition, migration exclusion/recorded-operation and registration-copy proofs remain per-owner acceptance inputs. Historical 125-class/78-kind/24-schedule totals alone are not closure. |

### Accepted work and identity dispositions

The [A12d3 retention map](a12d3-schedules-drain.md#source-job-retention-map)
remains the per-class inventory; supplement it with actual queued, scheduled,
retry, dead, busy and fetch observations at release time without logging payloads.

| Work | Required disposition before the affected checkpoint |
| --- | --- |
| Supported carried trip root/materialized children | Preserve original parent/run/event token, accepted due time and wrapper locale/zone. Source and native effects share durable per-effect/root receipts under ownership locks; already completed effects do not repeat, partial work finishes missing effects. |
| Legacy replayable parent with independently random child token; historical children without accepted schedule metadata | Retain/predrain under its owner before flipping. No inferred reconciliation or newly invented identity/due time. C's supported vector does not certify these tails. |
| Source-owned trip parent needing fresh source children under drain-only | Refuse before pending tally or child publication; retain unresolved accepted wrapper. Route through an already proved native-owner continuation only when its owner/identity contract is valid. No silent acknowledgement. |
| Parallel/realtime/daily tracks, migration walkers, archive chains, integration schedulers, digest/mail, resumable imports/extraction, family callbacks | Require their domain-specific continuation/effect proof or predrain. A source chain requiring fresh source children or a native-to-Rails callback blocks the affected switch. No generic allowlist or producer exemption is implied. |
| Retry/scheduled bookkeeping for accepted source work | Preserve original payload and due time; it may drain on OLD, provided the entire chain is isolated and proved safe. Not permission for fresh application enqueues. |
| Unknown/retired/dead or unreadable work | Preserve it and BLOCK the affected switch/shutdown until concrete owner disposition (ruling 10). Never deserialize arbitrary Ruby or bulk-delete for an empty status. |

### Checkpoint 1: switch traffic to NEW

Require the actual **NEW Phoenix-only** image, retained HTTP/HEAD/auth/API/storage
closure and L1 lifecycle/callback effects ready. Release owns public/private/Oban
migration, exclusion, seeds and registration copy; web readiness is observation
only. NEW/OLD share compatible public rows and `public.job_outbox`, additive
private ledgers, storage services/keys, mount/object access and signing inputs.
Verify actual UID/mount permissions and native reads/writes visible to retained
source jobs; no values or real user traces belong in the evidence.

Fence OLD web, boot/cache, cron loading **and polling**, manual jobs, callbacks,
framework/ActiveJob/Sidekiq publication and reverse Poller with installed controls.
Do not clear old cron registrations or pending payloads. Prove every remaining
accepted chain can settle without fresh source publication or native-to-Rails
effects, with owner/event collision tests and original identities. Only isolated
accepted source debt may remain at this checkpoint; unsupported/unknown debt
blocks its affected transition. Switch all HTTP and callbacks to NEW, remove OLD
web reachability, and prove NEW has no OLD upstream, Rails child or fallback.
Record listener argv, process tree, health/ready, representative HTTP envelopes,
source producer closure and accepted-debt dispositions in the release-tier report.

### Checkpoint 2: stop OLD after complete G49

This is a separate later checkpoint under producer quiescence. Use D's installed
Sidekiq-limit_fetch observation contract: configured/actual queues, every
scheduled/retry/dead/busy payload, queue lock busy/probed lists, installed
monitor registrations/heartbeats, orphan work and changing/unreadable reads.
Native SQL/reverse/release/generation observations supplement source Redis;
native `forward` alone cannot authorize OLD shutdown.

1. Before quieting, use source `phase: :pre_quiet`: healthy idle probes/processes
   may exist, but unresolved payload/effect debt and UNKNOWN block. Require the
   separate native `shutdown` observation; ordinary forward health is insufficient.
2. Quiet every independently identified OLD worker using its existing supported
   mechanism. Keep accepted effects alive until settled. Inspect source
   `phase: :quiet`: all registered workers must report literal stopping state
   (`Process#stopping?`, not Ruby truthiness of Redis `quiet`), and fetch/probe
   reservations must be released. SQL/reverse/release and native debt remain zero.
   The source CLI's default post-stop phase does not select a pre-TERM phase;
   the task-10 operator uses the existing observer API with the explicit phase.
3. Complete pre-TERM checks, gracefully TERM only authorized OLD processes, and
   independently inspect OS/container absence. Repeat source default
   `phase: :post_stop` plus native shutdown/debt/lease checks after stop. No source
   process/fetch registration, reservation, busy work or new payload may remain.
   Missing info, stale heartbeat, UNKNOWN/read error or newly appearing debt blocks
   completion. Observers do not quiet workers, signal processes or authorize stop.
4. Resume only native producers after process/debt absence is proved. Retain the
   Rails 1.15.3 image and storage access through Eugene's rollback window. If OLD
   has stopped, the retained image can still resume after the
   [same-DB rollback steps](#a12f-3c-same-database-rollback-to-rails-1153).

Source/native reads are not an atomic global snapshot. Producer quiescence,
settled accepted work, stopped consumers and independent post-stop reinspection
establish the boundary; two transient empty readings do not. D's review fix and
E's actual quiet/stop smoke are required before this procedure is accepted.

The release report must contain **both** checkpoints, exact candidate/image
heads, actual smoke and named mutation results, retained-work dispositions,
shared data/storage checks and observed process/debt absence. Use the existing
[G02/G42/G47/G48/G49 release-tier runbook](/Users/frey/projects/dawarich/superpowers/plans/2026-10-04-phoenix-release-tier-runbook.md).
No branch result here switches traffic, removes Rails support or closes the
rollback window.

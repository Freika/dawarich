# Phoenix Ruby-free release: operator contracts

Baseline: Rails 1.15.3 integrated at `8d6368fc3187db758151a4d401547d93612d26bb`.
Controller rulings dated 2026-10-05 govern the first Phoenix release. This
document records the shared operator contract and the A12f-3o tasks 1–4 and
18–20 changes. Metrics and Sentry owners document their detailed mappings;
A12f-4 owns final runtime activation and image acceptance.

## Shared operator contract

| Surface | Rails source contract | Phoenix disposition |
|---|---|---|
| `/sidekiq` | Admin session; self-hosted, or Cloud with both `SIDEKIQ_USERNAME` and `SIDEKIQ_PASSWORD` present. Cloud also challenges with Rack Basic auth. Unauthorized root GET redirects temporarily to `/` and sets error flash `You are not authorized to perform this action.` | GET/HEAD temporarily redirect authorized operators to `/settings/background_jobs`; retain role and Cloud Basic restrictions. No Sidekiq CRUD replacement. |
| `/api-docs`, `/api-docs/index.html` | Public rswag UI; Basic auth is disabled in `config/initializers/rswag_ui.rb`. | Public locally served Swagger UI, subject to existing host and SSL policy. |
| `/api-docs/v1/swagger.yaml` | `swagger/v1/swagger.yaml`, OpenAPI 3.0.1, title Dawarich API, version v1; rswag has no rewriting filter. | Exact stored bytes and `text/yaml`; HEAD has the same headers and no body. No generated alternate schema. |
| `/admin/flipper` and nested paths | Admin Flipper engine. `FeatureFlags` gates no behavior. | Terminal native 404; no alternate flag UI. Stored tables and historical migrations remain. |
| `/metrics` | Enabled only by exact `PROMETHEUS_EXPORTER_ENABLED=true`; Basic auth `METRICS_USERNAME`/`METRICS_PASSWORD`, realm `Dawarich Metrics`, including self-hosted. | Required native equivalent, owned by A12f-3o tasks 5–11. |
| Sentry/GlitchTip | `SENTRY_DSN`; traces default 0.05, profiles default 0.1. Logs default off; `SENTRY_ENABLE_LOGS` is case insensitive. | Required in the first release, owned by A12f-3o tasks 12–17. |
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
files of live PIDs during rolling restarts. Detailed names, types, units,
labels and buckets are pinned by the metrics owner against the synced Yabeda
and map/extraction producers, rather than inferred from this route census.

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
through Endpoint without a Rails request. Full ExUnit seeds 404 and 202 are
the branch merge gate. Real Swagger rendering, release asset packaging and
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
Self-hosted nonadmins still see their ordinary background settings. Cloud
nonadmins receive no operator access. Detailed job mutations and other Cloud
admin pages remain with A12f-3 task 17. ED-346 records the intentional UI change;
source fixture comparison still verifies the complete preexisting markup, and
separately verifies the added admin-only health card.

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

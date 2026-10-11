# Native production packaging and whole-app Rails fallback

X4 is a functional packaging smoke. Production rollout, X5 full partitions and standalone G44 acceptance remain separate controller gates. Performance/resource measurement is outside scope.

## Build the two artifacts

Run from the repository root with an explicitly selected Docker context. On the controller-authorized Mac mini use `colima`; on a private local stand use `orbstack`. Supply image tags, a run identity and private evidence directory through the environment.

```sh
: "${NATIVE_DOCKER_CONTEXT:?explicit Docker context required}"
: "${NATIVE_IMAGE:?native image tag required}"
: "${RAILS_FALLBACK_IMAGE:?Rails image tag required}"
: "${NATIVE_SMOKE_RUN:?run identity required}"
docker --context "$NATIVE_DOCKER_CONTEXT" build -f docker/Dockerfile \
  --target native_runtime --label "org.dawarich.x4=$NATIVE_SMOKE_RUN" -t "$NATIVE_IMAGE" .
docker --context "$NATIVE_DOCKER_CONTEXT" build -f docker/Dockerfile \
  --target coexistence_runtime --label "org.dawarich.x4=$NATIVE_SMOKE_RUN" -t "$RAILS_FALLBACK_IMAGE" .
```

The native builder uses native CSS/static declarations, esbuild splitting and `phx.digest`; it exports runtime i18n/achievement/timezone data separately. Rails frontend discovery belongs only to `rails_frontend_builder`. The native payload includes the release, geodata, local Swagger/OpenAPI, PWA/icons, MapLibre module/worker siblings, renderer modules/fonts and storage configuration. It rejects Ruby/gem tools and Rails application source. Root Rails sources remain available for the independent fallback build.

## Exercise the packaged runtime

Install `@playwright/test` and Chromium in a private package/cache directory and set `NATIVE_PLAYWRIGHT_ROOT` to that package root. The harness requires the local images `postgis/postgis:17-3.5-alpine` and `redis:7.4-alpine`. It never pulls database/service images or uses a host database/Redis. Run long builds/smokes in the controller's tmux session.

```sh
: "${NATIVE_PLAYWRIGHT_ROOT:?private Playwright package root required}"
: "${NATIVE_SMOKE_OUT:?private evidence directory required}"
bash app-phoenix/scripts/native_smoke.sh
```

The harness creates a labelled private Docker network, PostGIS volume and PostGIS/Redis/app containers. Listener ports are assigned dynamically to loopback. Secrets are generated per run in a private temporary directory and removed on exit. Only created resources are removed; existing names refuse. Both application instances and the database/Redis/network/volume are stopped/removed before returning. Images and evidence may remain. The controller checks at least 10 GB free before and after builds and runs `docker --context colima builder prune -af` after the build phase.

The native startup uses the existing `web-entrypoint.sh` with `DAWARICH_RAILS=off` and `DAWARICH_PHOENIX_LIFECYCLE=true`. The apparent `bin/rails server` argument is parsed by the unchanged lifecycle entrypoint into native release startup; the image has no Ruby executable. Native migration/bootstrap and readiness must succeed on the empty private database. The smoke sets `RAILS_ENV=test` for synthetic use and supplies both native and Rails Redis settings privately.

Checks cover health/readiness, synthetic points API, ordinary guest pages, account HTTP forms, authenticated LiveViews, admin pages, public sharing, lazy charts/editor/maps/studio, actual LiveView sockets and MapLibre workers, client PNG export and real Node/Xvfb PNG/PDF rendering. Positive payload/digest/CSS URL checks complement negative Hotwire/importmap/Sprockets/global checks. Receipts contain scalar counts and static asset paths; session state and keys are private and deleted. A failed step remains a failed smoke; no skip or partial result is acceptance.

## Switch the whole application to Rails

The harness stops/removes the native app, then starts the separately built `coexistence_runtime` image with `DAWARICH_RAILS=on`, `DAWARICH_PHOENIX_LIFECYCLE=false`, and the same synthetic database/Redis/session secret. It invokes `bundle exec rails server` directly as the whole application. It verifies health, data/API, authenticated documents, native-session compatibility and static Swagger/PWA/worker assets. The Rails container must have no BEAM process. This is an independent startup choice; it is never an upstream for a native request or refusal.

Operators must provision a compatible schema and preserve the configured session/encryption keys when switching artifacts. The smoke proves those contracts on synthetic data; it does not authorize deployment or assert compatibility for every external client. The native no-upstream endpoint test remains the routing oracle.

## Security and evidence

Cloud admission remains conditional and fail-closed. X4 does not change lifecycle/release/entrypoint guards or admit native Cloud without every validated configuration/direct-session-lease/HTTPS-Manager/canonical-host prerequisite. Targeted package/native dispatch/admission tests use the controller's X4 runner with private resources; no full ExUnit suite belongs to this task.

Evidence lives in the controller report: exact app SHA, image IDs/sizes, build exit statuses, package/digest receipts, browser/socket/worker/export PASS lines, independent Rails fallback evidence, named test RED/GREEN/mutation/restored GREEN, guard-file diff and final resource cleanup. Repository allocations and secrets are never committed. See [native development](native-frontend-development.md) and [architecture context](native-frontend-context.md).

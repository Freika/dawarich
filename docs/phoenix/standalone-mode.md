# Opt-in standalone Phoenix

Set `DAWARICH_RAILS=off` to run the native Phoenix listener without Puma or
Sidekiq. The flag selects the native release lifecycle regardless of the older
`DAWARICH_PHOENIX_LIFECYCLE` value. Without it, coexistence behavior is unchanged.
The web process owns Oban and claims every registered native job through the
existing ownership fences. Pinned ownership is respected; operators must drain
accepted Rails work before switching an existing deployment. The historical
worker role remains idle.

All eight native AuthGate flows are enabled automatically. Existing admission,
CSRF, session, account, and provider checks remain in force. Configure
`SELF_HOSTED=true` for the self-hosted authentication contract.

## Build and runtime

Install the locked npm and Mix dependencies first. With an isolated build
database and private Redis selected by `DATABASE_NAME` and `REDIS_URL`, run
`sh app-phoenix/scripts/standalone_build.sh`. It precompiles the public assets
and exports translations, achievements, importmap, and time zones using Rails
at build time, then compiles and packages the production release. Ruby 3.4.9
is needed for this build step only; use the project's asdf toolchain.

Retain `public/`, `tmp/phoenix/`, and native release data alongside the release.
Set `APP_PATH` to that application root. Runtime requires Erlang/OTP and the
native release dependencies; it never launches Ruby. Supply the usual database,
Redis, host, storage, encryption, and secret configuration. Persist the release
cookie using `DAWARICH_COOKIE_FILE`. The cookie directory must exist.

Run `bin/dawarich eval 'Dawarich.Release.migrate()'` and
`bin/dawarich eval 'Dawarich.Release.seed()'` with `DAWARICH_RAILS=off` before
`bin/dawarich start`. Fresh databases use the native baseline; existing supported
Rails ledgers receive the missing ordered native migrations. Startup checks
native readiness. Listener address comes from `BINDING` and `PORT`, or a supported
command encoded in `DAWARICH_NATIVE_ARGS`. Unsupported commands fail explicitly.

## Main settings and map seams

Standalone mode owns the general settings save form with native session and
CSRF admission, locale/timezone selection, email preferences and supporter
settings. Supporter verification remains a separate route.

Standalone self-hosted mode also owns the authenticated settings/progress reads,
point and track vector tiles, and date/import bounds used by the main map. Reads
are account scoped, exclude anomalous points, and use private cache headers.
Precompiled relative JavaScript imports resolve through the asset manifest.

These are minimum main-path seams under ruling 15. Robust outlier bounds,
antimeridian wrapping, complete vector-tile property/color parity and Cloud map
contracts remain for the map owners. Bounds currently return the exact extent.
Advanced speed coloring and unsupported map envelopes terminate with 422; map
execution failures terminate with 500. Their reason tags begin `standalone_map_`.

## Terminal hand-backs

The route admission checks remain active. In standalone mode each refused
request terminates natively instead of attempting a Rails connection:

| Family | Status | Stable reason |
| --- | --- | --- |
| Missing route | 404 | `missing_route` |
| Route constraint, disabled route or slice | 404 | `route_constraint`, `route_disabled`, `slice_disabled` |
| Unsupported browser envelope | 422 | `unsupported_envelope` |
| Native route gate refusal or exception | 500 | `native_gate` |
| API transport/body replay | 422 | `api_body` |
| Direct proxy or upstream access | 422 | `rails_proxy`, `rails_upstream` |
| Cable proxy upgrade | 422 | `cable_proxy` |

These are tonight's terminal errors under controller ruling 15, with edge-case
Rails parity deferred. API paths and JSON Accept receive JSON; browser requests
receive the native error page. HEAD errors have no body. Responses do not expose
internal failure details.

Every terminal response logs `[standalone.handback]` followed by JSON containing
method, path, reason, and status, and emits
`[:dawarich, :standalone, :handback]` with `%{count: 1}` and the same metadata.
Query strings, bodies, and request headers are excluded. With the existing
Prometheus exporter enabled, `dawarich_standalone_handbacks` counts these events
by method, reason, and status; paths are excluded from metric labels.

Stop the web release with `bin/dawarich stop` using the same cookie and node
configuration. Redis remains a runtime dependency and must be managed separately.

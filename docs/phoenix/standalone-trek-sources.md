# Standalone TREK source management

With `DAWARICH_RAILS=off`, the settings TREK pane supports connecting,
selecting trips, importing a selection, queuing a manual sync, and disconnecting
through the existing `/settings/trek_sources` URLs, including HTML suffixes
and the picker locale navigation. Coexistence keeps these
requests Rails-owned. Cloud native lifecycle refusal is unchanged.

All actions require an authenticated, active account with full access and an
owned TREK source. Writes require a valid Rails-compatible CSRF token. The shared
Rails verifier
accepts global and correctly path/method-bound per-form tokens, including padded
encodings. Disconnect forms verify their effective DELETE method when submitted
through POST with `_method=delete`. Missing, invalid, wrong-path and wrong-method
per-form tokens are refused before effects.

A Pro-plan refusal returns 303 with the Rails application flash. All native
Referer redirects use `DawarichWeb.RailsRedirect.back/2`. Admission compares the
parsed host to `request.host`, as Rails does; another scheme or port on that
host remains allowed. Root-relative paths retain queries and fragments.
Backslashes, userinfo, control or whitespace characters, protocol-relative
forms, malformed URLs and foreign hosts use the action's Rails fallback.
AFFiNE ADR: **Dawarich — ADR-20261007-native-safe-referer**
(document `eyGRi0ZnLfOXhFXdR_-rG`).
The syntax restrictions are an explicit controller security ruling, recorded
as ED-FIX-SA-TREK-REFERER-SYNTAX in `app-phoenix/parity/expected_diffs.md`.

| Native consumer | Fallback |
| --- | --- |
| TREK and map-frame Pro refusal | Application root |
| Achievement sharing | The achievement's page |
| Family and admin refusal | Application root |
| API-key rotation and miscellaneous settings | Application root |
| Visit update | Timeline for today with suggested status |
| Visit bulk deletion and merge | Timeline for today |
| Segment writes and track recalculation | Application root |

Visit deletion and bulk update retain their explicit Rails timeline redirects.
An unsafe Referer does not invalidate an otherwise admitted native write or
cause standalone replay/422. Existing authentication, CSRF, ownership, job
routing and coexistence route gates still apply. An AST guard test rejects
Referer handling outside the shared helper, including newly added handlers.
See `test/dawarich_web/rails_redirect_test.exs` and the named F1/F2/F3 request
regressions in the achievement, API-key, visit, segment, recalculation and
family tests. The signed achievement regression reproduces both browser
backslash/userinfo probes from the security review.

Connection verification precedes credential persistence; credentials use the
existing Active Record encryption format. Importing sources refuse credential
replacement and selection/sync changes. Disconnect remains available during
an import and keeps imported itineraries, marking them stopped.

Selection excludes archived and undated remote trips, preserves identifier
order, removes duplicates, and retains selections larger than a worker chunk.
The source claim and `imports.trek_import` outbox command commit together under
the existing job ownership lock. Clearing a selection rotates the token and
stops existing trips without removing their itinerary data. Manual sync emits
`imports.trek_sync`; existing native workers execute both command types.

The existing native TREK client resolves and validates the configured endpoint,
pins its resolved address through `Dawarich.Photos.ProviderHTTP`, and rejects
redirects. Provider failures are shown as alerts; HTTP 401 disables the source.

Rails references: `app/controllers/settings/trek_sources_controller.rb`,
`app/models/trip_source.rb`, `app/services/imports/trek_commands.rb`, and
`app/views/settings/trek_sources/select_trips.html.erb`.
Native entry point: `DawarichWeb.TrekSourceActions`; domain service:
`Dawarich.Imports.Trek.Sources`; selection page: `DawarichWeb.TrekSelection`.
Request verification: `app-phoenix/test/dawarich_web/standalone_trek_sources_test.exs`.

AFFiNE counterpart: **Dawarich — Standalone TREK source management**
(document `mR_e6js8xDRhZ3XmmmITa`).

# Standalone TREK source management

With `DAWARICH_RAILS=off`, the settings TREK pane supports connecting,
selecting trips, importing a selection, queuing a manual sync, and disconnecting
through the existing `/settings/trek_sources` URLs, including HTML suffixes
and the picker locale navigation. Coexistence keeps these
requests Rails-owned. Cloud native lifecycle refusal is unchanged.

All actions require an authenticated, active account with full access and an
owned TREK source. Writes require a valid Rails-compatible CSRF token.
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

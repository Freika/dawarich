# Standalone integration settings and photo imports

Controller ruling 15 limits this package to saving integration settings and
starting Immich/PhotoPrism imports. The A12f-3b-B plan is the execution source.

## HOT mounting handoff

Import `DawarichWeb.IntegrationFormRoutes` and invoke
`integration_form_routes()` in the router after the other pipeline declarations.
The macro defines its own `:integration_forms` pipeline, including session
lookup and `Api.Body` with `nested_form: "settings"`. It uses the router's
existing `put_api_tag/2` helper. Mount before any overlapping background-job
POST route. Do not reuse the flat-form `:standalone_settings` pipeline.

The module declares POST/PATCH/PUT `/settings/integrations` and POST
`/settings/background_jobs`. Route metadata uses
`{DawarichWeb.IntegrationActions, :enabled?}`: native handling is enabled when
`DAWARICH_RAILS=off`; coexistence retains the source route. The domain package
does not edit the shared router, strangler, slices or job registry.

## Settings contract

`Dawarich.Settings.Integrations.save/4` accepts the integration settings
allowlist. It casts SSL flags, validates every configured provider URL using
the existing Trek endpoint validator, and clears TeslaMate checkpoints when
the endpoint changes. Self-hosted private addresses remain supported; cloud
private addresses and metadata targets are rejected before contacting a
provider or saving settings.

Connection tests support Immich, PhotoPrism, AirTrail and TeslaMate. Immich
checks thumbnail permission when metadata contains an asset. A provider
failure still saves valid configuration, records `failed`, and redirects with
the save notice followed by provider alerts. Transport exceptions use a safe
native message rather than embedding request details. Invalid configuration
returns native errors without proxying.

The final save locks and re-reads the user's settings after network activity,
merges only requested fields and connection statuses, and preserves unrelated
concurrent writes. It applies the Rails save callback that removes trailing
slashes from Immich/PhotoPrism URLs before persistence. SQL failure rolls back. Updates require a valid session,
CSRF token, active account and the source full-access entitlement. Optional
photo-cache refresh clears that user's photo, search and thumbnail entries.

Standalone form rendering replaces stored API keys/passwords with `********`.
Submitting that unchanged marker preserves the current credential; submitting
an empty field clears it. Coexistence fixture rendering remains unchanged.
Settings and provider credentials are excluded from SQL logs and command
payloads. Provider error bodies are not included in alerts.

## Photo-import contract

`Dawarich.Imports.IntegrationCommands` accepts exactly `start_immich_import`
and `start_photoprism_import`. Authenticated, CSRF-protected POSTs redirect to
`/imports` with the source success notice after inserting a native command.
The source background-job controller does not apply the settings-save
full-access/active-account check to these POSTs; this producer preserves that
behavior.

Commands use the existing `imports.immich_geodata` and
`imports.photoprism_geodata` workers, capturing only the actor ID and normalized
time zone. UUID event/dedupe identities are per accepted request, as source
button submissions enqueue independently. Existing worker leases and import
publication fences remain responsible for processing and duplicate imports.

An owner pinned to Sidekiq yields 503 and accepts no command. Missing actors,
unknown/nested names and unsupported triggers are refused; no Rails command
is emitted. The standalone runtime's existing registry/claimer supplies native
ownership. No registry change is required for these existing leaves.

## Verification and remaining scope

The two task test files are `a12f3b_i01_test.exs` and `a12f3b_i04_test.exs`.
They exercise actual route macros, form parsing, encrypted session cookies,
CSRF, local HTTP provider responses, owner pins, SQL footprints, secret
masking, checkpoint reset, concurrent setting preservation and rollback.
Each named selector has RED/GREEN/mutation/restored-GREEN evidence in the
controller-assigned implementation report. The retained Rails request/service
and dispatcher batch characterizes the source without changing shared fixture
generators.

HOT must mount the routes and verify the final Endpoint/Strangler path.
Trek source/picker/sync (I02/I03), the non-photo I04 trigger forms, Immich
enrichment/verifier (I05), scheduled children (I06), and rare exception/legacy
envelope parity remain deferred under ruling 15. Seed 202 belongs to the
controller's integration head. This package does not accept a Ruby-free
release or change drain/rollback policy.

# Standalone integration settings, producers and enrichment

The A12f-3b-B plan covers integration settings and producers. The E061
follow-up closes its omitted I04 dispatcher names and I05 Immich verifier
prerequisites under the A12f-3b-E plan.

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

## Background-job producer contract

`Dawarich.Imports.IntegrationCommands` accepts `start_immich_import`,
`start_photoprism_import`, `start_airtrail_import`, `start_teslamate_import`,
`start_reverse_geocoding` and `continue_reverse_geocoding`.
Authenticated, CSRF-protected POSTs insert a native command and retain the
source redirect: photo imports use `/imports`, AirTrail uses
`/settings/integrations`, TeslaMate adds `?service=teslamate`, and geocoding
uses `/settings/background_jobs`.
The source background-job controller does not apply the settings-save
full-access/active-account check to these POSTs; this producer preserves that
behavior.

Commands use the existing `imports.immich_geodata` and
`imports.photoprism_geodata` workers, capturing only the actor ID and normalized
time zone. UUID event/dedupe identities are per accepted request, as source
button submissions enqueue independently. Existing worker leases and import
publication fences remain responsible for processing and duplicate imports.
AirTrail and TeslaMate commands capture only the actor ID. Geocoding uses the
existing native worker with cursor zero, actor locale and the source force
mode; forced runs retain the paid-provider guard. Geocoding HTTP triggers
retain the source self-host-only restriction.

An owner pinned to Sidekiq yields 503 and accepts no command. Missing actors,
unknown/nested names and unsupported triggers are refused; no Rails command
is emitted. The standalone runtime's existing registry/claimer supplies native
ownership. No registry change is required for these existing leaves.

An accepted TeslaMate sync blocked by another lease snoozes for sixty seconds
with the same native job/event identity. It remains incomplete for G49 and
resumes after lease release. Direct synchronous callers retain their skipped
response. Scheduler children retain deterministic slot identities and replay
receipts; this follow-up does not transfer accepted work back to Rails.

## Immich enrichment verification

The existing authenticated enrichment API uses the native verifier as its
default enqueue hook while retaining explicit callback overrides. Successful
PUT submissions create the existing checking notification and schedule
verification ten seconds later. Verification performs GET requests only.

The verifier retains the source defaults, twenty-asset batches, accumulated
confirmed and pending counts, immediate remaining-batch children and
thirty-second retries, bounded to three passes. Coordinates use the source
0.00001 tolerance, including zero. Missing or soft-deleted actors, missing
notifications, changed configuration and provider/malformed-response errors
retain the source outcomes. Completion updates the same localized notification
and publishes its native broadcast event. Processed receipts and the
notification row lock commit each effect and continuation atomically; queued
continuations remain visible as incomplete work to G49.

## Verification and remaining scope

The task test files are `a12f3b_i01_test.exs`, `a12f3b_i04_test.exs`,
`a12f3b_i05_test.exs` and `a12f3b_e061_test.exs`.
They exercise actual route macros, form parsing, encrypted session cookies,
CSRF, local HTTP provider responses, owner pins, SQL footprints, secret
masking, checkpoint reset, concurrent setting preservation and rollback.
Each named selector has RED/GREEN/mutation/restored-GREEN evidence in the
controller-assigned implementation report. The retained Rails request/service
and dispatcher batch characterizes the source without changing shared fixture
generators.

HOT must mount the routes and verify the final Endpoint/Strangler path.
Trek source/picker forms (I02/I03), I06 producer surfaces and rare
exception/legacy envelope parity keep their separate owner records. E062's accepted
Trek sync proof is unchanged by E061. Seed 202 belongs to the
controller's integration head. This package does not accept a Ruby-free
release or change drain/rollback policy.

Cloud native lifecycle remains refused until the external L1 handoff,
including when `DAWARICH_RAILS=off`. Current migration ledgers do not bypass
that refusal: readiness reports `:schemas_behind`, and migration and seed
commands refuse without writes. `a12f3b_e061_cloud_guard_test.exs` verifies
this constraint alongside the unchanged baseline release Cloud tests.

## TeslaMate effect ownership reconciliation

Finalization preserves the explicit native realtime owner path: filter anomalies
synchronously, then publish `tracks.generate_realtime` to the existing outbox
with the sync event dedupe key. Standalone mode with retained Sidekiq owner rows
uses the native anomaly-arrival worker and debounced realtime-track worker.
Both paths use `Tracks.BackfillCommands`; standalone emits no Rails commands.

With Rails enabled and a Sidekiq realtime owner, the existing `publish/3`
helper preserves anomaly ownership selection and the exact realtime reverse
payload. Backfill retains its legacy-ingest option. R02 checks the explicit
native path over a two-timestamp range and the retained-Sidekiq standalone
path through anomaly execution. The TeslaMate sync contracts retain exact
coexistence rows. R01 visits remains the integrated durable debouncer contract.

AirTrail's native client requests a fresh socket through OTP's request-specific
`socket_opts`, retaining the close header and TLS verification. A close header
alone permits reuse of an already pooled connection. The existing connection
test warms the pool, serves both possible sockets, and asserts the fresh socket
was used; it also retains the close-header assertion. This deterministic
contract protects the local HTTP integration tests and normal client calls
from stale pooled sessions without retries or timeout changes.

## Standalone transaction regression

Integration saves use a regular `Repo.transaction/1`, which starts a transaction
when no outer transaction exists. A top-level `mode: :savepoint` leaves Postgrex
idle and causes `DBConnection.TransactionError` before the normal form can save.
Sandboxed tests already have a database transaction and therefore concealed
this runtime failure. Ecto Sandbox supplies its own savepoint handling for
ordinary transactions.

`StandaloneIntegrationsFlowTest` checks out a connection with `sandbox: false`,
loads the actual integration form, submits blank Immich fields with SSL
verification enabled, follows the save redirect and verifies persisted settings.
A database constraint then rejects a changed SSL flag and verifies rollback and
connection usability. Existing integration tests retain provider, concurrent
merge, masking and sandbox rollback coverage.

The shared AFFiNE counterpart is **Dawarich — Standalone integration settings
and photo imports**. The sweep-2 fix report records RED/GREEN/mutation and final
gate evidence.

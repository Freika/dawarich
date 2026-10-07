# Rails bugs fixed in the Phoenix port

This register records Rails bugs fixed in the port (controller ruling 17).
The controller compiles other packages' reports for the release-wide changelog.
Repository source anchors identify the current implementation; runtime allocations
and private records are excluded.

## S02 shared trip thumbnails — DRB-023

Rails exposes a previously granted trip photo after a trip date edit excludes it:
warm GET and HEAD can still return 200 until the ten-minute grant expires.
Rails sources: `app/controllers/api/v1/shared/photos_controller.rb:42` (cached
ID authorization), `app/controllers/api/v1/shared/photos_controller.rb:63`
(window-blind key), and `app/controllers/api/v1/shared/photos_controller.rb:86`
(current trip window is read only on a cache miss).

Phoenix binds grants to the current owner, resource window and privacy zones
at `app-phoenix/lib/dawarich/shared_api/closure.ex:16` and
`app-phoenix/lib/dawarich/shared_api/photos.ex:32`. Standalone native requests
and coexistence proxy requests apply the same policy. The proxy guard in
`app-phoenix/lib/dawarich_web/shared_photo_guard.ex` denies excluded GET/HEAD
before Rails forwarding, including `api_shared` slice handoff; valid requests
retain Rails authorization and responses.

Named regressions in `app-phoenix/test/dawarich_web/a12f3b_s02_test.exs`:
S02F2, “warm thumbnail grants expire when the shared trip window excludes the
photo”; S02C1, “mounted coexistence GET and HEAD revoke excluded trip thumbnails
before Rails handoff”. Both require 404/404 without a provider thumbnail fetch.
S02C1V checks that missing native family-viewer recognition cannot bypass the
current scope on Rails handoff. S02C1O checks that native owner unavailability
cannot bypass that scope. S02C2 verifies the fixed/deferred register entries.

Rails remains unchanged. DRB-023 records its deferred repair; no additional
DRB or ED row was added. S02F1's poisoned-zone-key race is Phoenix-specific:
Rails memoizes zones within each request, so it is not a second Rails bug.
An in-flight request can finish using its already captured policy; these tests
establish denial for subsequent requests, not cancellation of in-flight responses.

CHANGELOG-ready: Fix shared trip thumbnails remaining accessible after trip
boundary changes. Phoenix now checks the current shared scope and privacy zones
before serving or forwarding GET/HEAD thumbnails in standalone and coexistence.

AFFiNE decision counterpart: `kcLrxKCKEyl9xcbirP9V9`.

## Failed media purge loses its storage retry target

- Symptom: a failed physical deletion leaves private poster, route-video or
  export media in storage after Active Storage has destroyed the blob row;
  later source lookups cannot find the blob to retry the deletion.
- Rails source: `app/services/posters/purge_commands.rb:21`,
  `app/services/exports/purge_commands.rb:21`, and
  `app/services/rails_commands/a8_handlers.rb:29` call `blob.purge_later`.
  Installed Active Storage 8.1.3.1's `app/models/active_storage/blob.rb:335-338`
  destroys the blob before deleting storage; its purge job takes that blob.
- Phoenix: `app-phoenix/lib/dawarich/posters/purge_worker.ex:51` deletes storage
  while the guarded blob row is locked, before removing rows. Errors roll back
  rows and variant child changes; retries retain the target. Export/route-video
  consumers already retain object keys and services durably in Oban jobs.
- Regression: `F1 captured poster purge retains failed storage work until retry
  and drain completion` in
  `app-phoenix/test/dawarich/a12f3b_e13_purge_retry_test.exs`.
- Expected difference: ED-A12F3B-E13-F1 in
  `app-phoenix/parity/expected_diffs.md`. Native path fixed; retained Rails-owned coexistence is DRB-025.

## E13 F2 shared native media purge ordering

- Rails symptom: storage deletion failure leaves private media stored after its
  blob/variant rows disappear; serialized purge retries cannot recover the blob.
- Source: installed Active Storage 8.1.3.1 `app/models/active_storage/blob.rb:335–338`
  and `app/jobs/active_storage/purge_job.rb:6–11`; media handlers are
  `app/services/posters/purge_commands.rb:21`,
  `app/services/exports/purge_commands.rb:21`, and
  `app/services/rails_commands/a8_handlers.rb:29`.
- Phoenix: `app-phoenix/lib/dawarich/exports/purge_worker.ex` and
  `app-phoenix/lib/dawarich/storage/native_purge.ex` retain eligible storage rows,
  reserve purge metadata for native download/upload revocation, and delete all
  eligible parent/variant objects before row removal. Storage errors retain
  retry/drain debt. Existing key-only jobs still delete their durable targets.
- Regression: `F2 every shared native producer retains blob and variant rows
  through storage failure and serialized retry`, in
  `app-phoenix/test/dawarich/a12f3b_e13_shared_purge_test.exs`.
- Expected difference: ED-A12F3B-E13-F2. Original Rails job and all hand-backs
  characterized by F3; Rails-owned coexistence remains preserved in DRB-025.

## F17 Google Takeout continuation progress regression

- Rails symptom: a late or retried RecordsImporter continuation overwrites newer
  visible import progress with its older constant index. The actual Rails importer
  reproduced **2,000 → 1,000** in the rollback-only fix2 source probe.
- Rails sources: `app/services/imports/broadcaster.rb:10` unconditionally writes
  processed; `app/services/google_maps/records_importer.rb:23` calls it with the
  supplied continuation index after each batch.
- Phoenix: `app-phoenix/lib/dawarich/imports/gpx_progress.ex:13` uses a fenced SQL
  maximum. `app-phoenix/lib/dawarich/imports/continuation_receipt.ex:6` admits
  work only after durable predecessors commit, retaining every pending/deferred
  event rather than canceling lower indices. Event cursors and writer counters
  commit together; a predecessor retry finishes its suffix without reducing
  progress in standalone or coexistence.
- Regression: `retrying a predecessor never lowers durable import progress`
  in `app-phoenix/test/dawarich/imports/continuation_order_test.exs`, both modes.
  Delivery regressions also prove a deferred event survives an overtaking attempt
  and all source points are applied once under all four-event delivery permutations.
- F17 progress: no ED/DRB row added; no plan ledger is assigned for this correction.
  This central register and the scoped reports record the divergence for the
  controller's release changelog. Rails production remains unchanged.

CHANGELOG-ready: Keep Google Takeout import progress monotonic when continuation
workers retry or arrive out of order, while preserving all pending source rows.

AFFiNE counterpart: `ovFWRqfzsy2Jb5n1NB4Qc`.

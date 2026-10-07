# Rails bugs fixed in the Phoenix port — draft register

Status: **DRAFT**, compiled 2026-10-07 under master-plan ruling 17. This is a release-wide evidence register, not deployment or release acceptance. [User-facing draft](CHANGELOG-phoenix-draft.md); [deferred source register](deferred-rails-bugs.md); [intentional differences](../../app-phoenix/parity/expected_diffs.md).

Sources are all 471 top-level controller Markdown reports dated 2026-10-06/07 at the snapshot, plus the three registers on `feat/phoenix-port` at `5088704cce284a765cfb540d3eb87377246e4871`. Report references below identify external evidence by filename and line; no runtime allocation is part of this document. Commit ancestry is checked against that pinned integration revision, not a moving branch. A follow-up audit checked 14 new/updated reports (8 new files); it adds the completed real-consumer correction from `fix2-fix-exports-redelivery.report.md` and the carried-forward progress entry from `fix3-a12f3a-f17.report.md`. Later reports/merges require a refresh.

**Reading the evidence:** “integrated” means the commit exists in that integration history; “feature only” means its local commit exists but was not integrated at the snapshot. Source anchors are the report/commit revision's lines and can move. Installed-gem anchors belong to Active Storage 8.1.3.1, not repository paths. “unverified” means the report/ledger did not establish that field or the local commit/test check could not confirm it. Tests cited here are original evidence, not tests rerun by this documentation task.

**Deployment scope:** standalone means native requests/jobs; coexistence distinguishes native-owned work from Rails-owned consumers. These scope statements do not establish a Cloud rollout. Self-hosted/Cloud-specific matrices are unverified unless stated. Native Cloud lifecycle remains refused in every mode pending external L1 handoff. Rails remains unchanged by this documentation task; some historical shared-code fixes below also changed Rails and are identified as such.

FRB IDs identify defects, not packages or follow-up patches. Provider client coverage and media-purge reports are consolidated by root cause. Phoenix-only regressions, restored parity, runtime/wire differences, retired products, and intentionally preserved failures are excluded from confirmed fixes.

## Report-backed corrections and accepted release differences

### FRB-001 — Shared trip thumbnail authorization survives a boundary edit

Previously granted trip thumbnails remain accessible by GET/HEAD for up to ten minutes after a trip edit excludes them. Current owner, trip window and privacy policy are checked before native serving or Rails forwarding.

- Rails: `app/controllers/api/v1/shared/photos_controller.rb:42,63,86`.
- Phoenix: `app-phoenix/lib/dawarich/shared_api/closure.ex:16; app-phoenix/lib/dawarich/shared_api/photos.ex:32; app-phoenix/lib/dawarich_web/shared_photo_guard.ex:23,34`.
- Fix/acceptance history: `be97f8bb4` (integrated); `4d371c3ee` (integrated); `d6da46f9f` (integrated); `ad2515432` (integrated).
- Modes: standalone and coexistence, including Rails slice handoff.
- Evidence: fix2-a12f3b-s02.report.md:78; rereview2-a12f3b-s02.report.md:58. Ledger: DRB-023; no additional ED row.
- Test (S02F2): “warm thumbnail grants expire when the shared trip window excludes the photo” in `app-phoenix/test/dawarich_web/a12f3b_s02_test.exs`.
- Test (S02C1): “mounted coexistence GET and HEAD revoke excluded trip thumbnails before Rails handoff” in `app-phoenix/test/dawarich_web/a12f3b_s02_test.exs`.
- Limits: Subsequent requests are denied; in-flight responses retain their captured policy. S02F1 is Phoenix-specific, not a second Rails defect. Rails remains unchanged.

### FRB-002 — Failed physical media deletion loses its retry target

Storage deletion can fail after the blob/variant rows disappear, leaving private files stored and serialized retries unable to recover their targets. Native cleanup keeps guarded rows and durable storage identities until all eligible object deletions succeed; pending native capabilities are revoked.

- Rails: `app/services/posters/purge_commands.rb:21; app/services/exports/purge_commands.rb:21; app/services/rails_commands/a8_handlers.rb:29; app/controllers/trips_controller.rb:65; app/models/trip.rb:15; Active Storage 8.1.3.1 app/models/active_storage/blob.rb:335-338 and app/jobs/active_storage/purge_job.rb:6-11`.
- Phoenix: `app-phoenix/lib/dawarich/posters/purge_worker.ex:51; app-phoenix/lib/dawarich/storage/native_purge.ex:16,46; app-phoenix/lib/dawarich/exports/purge_worker.ex:30,39 (668862bf3),167-184 (76e0c260d); app-phoenix/lib/dawarich/trips/attachments.ex:188`.
- Fix/acceptance history: `7232bbfa9` (integrated); `668862bf3` (integrated); `79ba18bef` (integrated); `76e0c260d` (feature only); `e50845403` (feature only).
- Modes: standalone and native-owned coexistence cleanup; Rails-owned coexistence remains defective.
- Evidence: fix-a12f3b-e-media.report.md:47; fix2-a12f3b-e-media.report.md:67; rereview3-a12f3b-e-media.report.md:60; impl-fix-exports-redelivery.report.md:55; impl-a12f3a-t-edges.report.md:50; rereview-fix-exports-redelivery.report.md:9. Ledger: ED-A12F3B-E13-F1/F2; DRB-025; ED-FIX-EXPORTS-PURGE in scoped export docs.
- Test: “F1 captured poster purge retains failed storage work until retry and drain completion” in `app-phoenix/test/dawarich/a12f3b_e13_purge_retry_test.exs`.
- Test: “F2 every shared native producer retains blob and variant rows through storage failure and serialized retry” in `app-phoenix/test/dawarich/a12f3b_e13_shared_purge_test.exs`.
- Test: “backup and export redelivery purge every generation storage before rows” in `app-phoenix/test/dawarich/user_data/export_worker_test.exs`.
- Test: “T04: signed trip attachments persist and dependent purge retries storage before rows” in `app-phoenix/test/dawarich/trips/rich_attachments_test.exs`.
- Limits: Deduplicates F1/F2, export redelivery and trip attachment reports. F4 graph collection is a Phoenix defect, not another inherited bug. ED-522 pending-import cleanup shares the storage-before-row principle, but its exact commit/test provenance is separately listed below.
- Coverage extension needing provenance: ED-522 describes the same lost-target defect for pending imports; `pending_imports/purge_worker_test.exs` names “a failed object delete retains recoverable cleanup work and retry cannot purge a newly shared blob”. Exact originating Rails line and fix commit are **unverified**; do not count it as a separate inherited bug.

### FRB-003 — An upload can be claimed by a different account

Another authenticated user possessing an unattached signed upload can claim its bytes for an import. A server-side upload receipt binds admission to the uploader.

- Rails: `app/controllers/imports_controller.rb:158,164`.
- Phoenix: `app-phoenix/lib/dawarich/storage/upload_receipts.ex:4,12; app-phoenix/lib/dawarich/imports/upload_admission.ex:18`.
- Fix/acceptance history: `3c5808570` (feature only).
- Modes: native import admission in standalone and coexistence; Rails-owned admission is unchanged.
- Evidence: impl-fix-imports-storage.report.md:57. Ledger: none added.
- Test: “another user cannot claim an upload created in the victim session” in `app-phoenix/test/dawarich_web/import_storage_security_test.exs`.

### FRB-004 — Import deletion leaves a prepared download usable

An application-issued prepared-download capability can remain usable while asynchronous cleanup waits. Native-owned deletion revokes the capability at deletion commit and retains durable object cleanup.

- Rails: `app/models/import.rb:195-196; app/services/imports/prepared_download_purge_commands.rb:33; Active Storage 8.1.3.1 app/models/active_storage/attachment.rb:150-152`.
- Phoenix: `app-phoenix/lib/dawarich/imports/import_blob_purges.ex:66; app-phoenix/lib/dawarich/imports/prepared_download_purge_worker.ex:43`.
- Fix/acceptance history: `3c5808570` (feature only); `91b09c4e7` (feature only).
- Modes: standalone regardless of stored owner, and native-owned coexistence; Rails-owned coexistence preserves delayed revocation.
- Evidence: impl-fix-imports-storage.report.md:57; fix2-fix-imports-storage.report.md:13,51. Ledger: DRB-029 added by follow-up; no shared ED row.
- Test: “deleting an import revokes its prepared blob capability immediately” in `app-phoenix/test/dawarich_web/import_storage_security_test.exs`.
- Limits: An already-issued external object-storage URL remains governed by deletion/expiry. The follow-up is a native ordering repair, not a second inherited defect.

### FRB-005 — Legacy extraction replay repeats terminal effects

Ordinary legacy extraction jobs have no expected-request identity by default and can process and publish effects again. Terminal effects and event settlement commit together; replay of the same completed event is inert.

- Rails: `app/jobs/enhanced_import/extract_job.rb:43`.
- Phoenix: `app-phoenix/lib/dawarich/enhanced_import/request_fence.ex:49`.
- Fix/acceptance history: `3c5808570` (feature only).
- Modes: native extraction dispatch in standalone/native-owned coexistence.
- Evidence: impl-fix-imports-storage.report.md:57. Ledger: none added.
- Test: “the same completed extraction event does not execute its effects twice through dispatch” in `app-phoenix/test/dawarich/enhanced_import/request_fence_test.exs`.
- Limits: Typed Rails extraction already fences identity; the dropped native typed payload was a Phoenix defect. No permanent exactly-once guarantee is claimed.

### FRB-006 — An old removal retry can remove newer extraction data

Ordinary legacy removal defaults to no expected identity and operates on the current extraction. Each batch/reset is fenced to its accepted request, and completed requests are recognized.

- Rails: `app/jobs/enhanced_import/destroy_job.rb:7; app/services/enhanced_import/destroy.rb:15`.
- Phoenix: `app-phoenix/lib/dawarich/enhanced_import/destroy_gpx_worker.ex:30; app-phoenix/lib/dawarich/enhanced_import/request_fence.ex:70`.
- Fix/acceptance history: `3c5808570` (feature only).
- Modes: native legacy extraction removal in standalone/native-owned coexistence.
- Evidence: impl-fix-imports-storage.report.md:57. Ledger: none added.
- Test: “a retried old removal cannot delete a newer extraction through dispatch” in `app-phoenix/test/dawarich/enhanced_import/request_fence_test.exs`.
- Limits: Typed Rails removal already has an expected-request fence.

### FRB-007 — An old upload capability can recreate purged storage

A still-valid disk upload token can write its purged key again. Publication requires a live locked upload receipt, including a purge between staging and publication.

- Rails: `Active Storage 8.1.3.1 app/controllers/active_storage/disk_controller.rb:24; lib/active_storage/service/disk_service.rb:21`.
- Phoenix: `app-phoenix/lib/dawarich_web/active_storage.ex:141`.
- Fix/acceptance history: `3c5808570` (feature only).
- Modes: native disk upload handling in standalone and coexistence.
- Evidence: impl-fix-imports-storage.report.md:57. Ledger: none added.
- Test: “a successful purge cannot be undone with the old upload capability” in `app-phoenix/test/dawarich_web/import_storage_security_test.exs`.
- Test: “purge between upload staging and publication prevents object resurrection” in `app-phoenix/test/dawarich_web/import_storage_security_test.exs`.
- Limits: Rails behavior is source-backed; the report does not claim a Rails HTTP token-replay experiment.

### FRB-008 — Failed GPX retries repeat failure notifications

A failed GPX import remains eligible for processing, whose rescue creates another failure notification on retry. Handled failure, notification and terminal receipt commit together; marker recovery does not repeat them.

- Rails: `app/services/imports/gpx_legacy.rb:20,28; app/services/imports/create.rb:47`.
- Phoenix: `app-phoenix/lib/dawarich/imports/gpx_lifecycle.ex:110,123; app-phoenix/lib/dawarich/imports/import_state.ex:96; app-phoenix/lib/dawarich/imports/lease.ex:37`.
- Fix/acceptance history: `efd232870` (integrated).
- Modes: accepted native GPX work in standalone and coexistence.
- Evidence: fix-a12f3b-e-imports.report.md:71. Ledger: none added.
- Test: “R1 real GPX failure survives marker rejection without processing or notifying twice” in `app-phoenix/test/dawarich/a12f3b_e09_test.exs`.
- Limits: The marker-rejection reproduction is native. Rails source establishes analogous failed-job retries; no Rails broker-ack crash reproduction is claimed.

### FRB-009 — Demo adoption changes another account’s tag

With inconsistent persisted place/tag ownership, a real visit to a demo place marks another owner’s linked demo tag as real. Only demo tags belonging to the import owner are adopted.

- Rails: `app/models/visit.rb:114-120; app/models/concerns/taggable.rb:8`.
- Phoenix: `app-phoenix/lib/dawarich/enhanced_import/item_writer.ex:92-96`.
- Fix/acceptance history: `474c7910d` (feature only).
- Modes: native enhanced-import writer; deployment-mode-specific proof unverified.
- Evidence: fix-a12f3a-f17.report.md:153; fix2-a12f3a-f17.report.md:158. Ledger: none added.
- Test: “an imported visit adopts a matched demo place” in `app-phoenix/test/dawarich/imports/continuation_review_test.exs`.
- Limits: Actual Rails callback probe reproduced this with inconsistent persisted references. No HTTP exploit is claimed.

### FRB-010 — A late Takeout continuation lowers import progress

An older worker overwrites newer progress; the source probe reproduced 2,000 → 1,000 (a retried predecessor lowered `processed`). Unfinished accepted predecessors order continuation admission, and continuation progress uses a database maximum, so retrying a predecessor never lowers durable import progress and no deferred continuation is cancelled.

- Rails: `app/services/imports/broadcaster.rb:10; app/services/google_maps/records_importer.rb:23; app/jobs/import/google_takeout_job.rb:11`.
- Phoenix: `app-phoenix/lib/dawarich/imports/continuation_receipt.ex:6,92; app-phoenix/lib/dawarich/imports/gpx_progress.ex:13; app-phoenix/lib/dawarich/imports/lease.ex:95`.
- Fix/acceptance history: `a403f9219`, `5d0581805`, `bc4c398b2` (feat/a12f3a-f17, merged `5ef730845`; re-reviewed x3, 24 delivery permutations in both modes).
- F17 progress: no ED/DRB row added (the Rails defect is fixed natively, not preserved).

### FRB-011 — Provider redirects disclose credentials

Cross-host redirects forward photo or integration credentials to a different host. Native clients refuse redirects without contacting the destination, including AirTrail HTTPS and TeslaMate paths.

- Rails: `app/services/photos/thumbnail.rb:19; app/services/immich/verify_enrichment.rb:19; app/services/air_trail/client.rb:16; app/services/tesla_mate/client.rb:83`.
- Phoenix: `app-phoenix/lib/dawarich/photos/provider_http.ex:58; app-phoenix/lib/dawarich/immich/enrichment.ex:124; app-phoenix/lib/dawarich/air_trail/client.ex:13; app-phoenix/lib/dawarich/imports/teslamate/client.ex:68`.
- Fix/acceptance history: `82bd3677b` (feature only); `36391927e` (feature only).
- Modes: native provider requests in standalone and coexistence; direct Rails provider calls remain unchanged.
- Evidence: impl-fix-photo-provider-client.report.md:42; fix2-fix-photo-provider-client.report.md:64. Ledger: none added.
- Test: “photo provider redirects never forward credentials to another host” in `app-phoenix/test/dawarich/photos/provider_client_test.exs`.
- Test: “verification worker refuses cross-host redirects without forwarding its Immich key” in `app-phoenix/test/dawarich/photos/provider_verification_test.exs`.
- Test: “other user-configured integration providers refuse redirects, invalid bases and oversized streams” in `app-phoenix/test/dawarich/photos/provider_inventory_test.exs`.
- Limits: Actual Rails probes confirmed Immich, AirTrail and TeslaMate disclosure. No Rails TLS-verification bypass is claimed.

### FRB-012 — Provider replies grow memory without a bound

Photo thumbnails, verification, connection checks and integration imports accept oversized replies into memory. Shared transport cancels cumulative responses above 32 MiB, including error replies, before completion.

- Rails: `app/services/photos/thumbnail.rb:19; app/services/immich/verify_enrichment.rb:19; app/services/immich/connection_tester.rb:47,70; app/services/photoprism/connection_tester.rb:33; app/services/immich/request_photos.rb:37; app/services/photoprism/request_photos.rb:68; app/services/air_trail/client.rb:16; app/services/tesla_mate/client.rb:83; app/services/trek/client.rb:56,68`.
- Phoenix: `app-phoenix/lib/dawarich/photos/provider_http.ex:91,121 (82bd3677b); app-phoenix/lib/dawarich/settings/integrations/connection.ex:149; app-phoenix/lib/dawarich/imports/integrations/immich.ex:81; app-phoenix/lib/dawarich/imports/integrations/photoprism.ex:63; app-phoenix/lib/dawarich/imports/trek/client.ex:42`.
- Fix/acceptance history: `82bd3677b` (feature only); `36391927e` (feature only).
- Modes: native provider calls in standalone and coexistence; Rails-owned calls unchanged.
- Evidence: impl-fix-photo-provider-client.report.md:42; fix2-fix-photo-provider-client.report.md:64. Ledger: none added.
- Test: “every photo response is capped during streaming before the provider finishes” in `app-phoenix/test/dawarich/photos/provider_client_test.exs`.
- Test: “verification and integration clients cancel oversized valid JSON before its terminator” in `app-phoenix/test/dawarich/photos/provider_verification_test.exs`.
- Test: “other user-configured integration providers refuse redirects, invalid bases and oversized streams” in `app-phoenix/test/dawarich/photos/provider_inventory_test.exs`.
- Limits: Supersedes the limited success-response cap/handoff described in older ED-195. Atlas has a separate 8 MiB limit in FRB-033.

### FRB-013 — Provider error text reflects credentials

An enrichment provider’s reason phrase can echo credentials into returned API errors. Errors contain trusted status text only.

- Rails: `app/services/immich/enrich_photos.rb:67`.
- Phoenix: `app-phoenix/lib/dawarich/photos/enrichment.ex:169`.
- Fix/acceptance history: `82bd3677b` (feature only).
- Modes: native photo enrichment in standalone and coexistence.
- Evidence: impl-fix-photo-provider-client.report.md:42; rereview-fix-photo-provider-client.report.md:86. Ledger: none added.
- Test: “enrichment errors contain only trusted status text when upstream echoes credentials” in `app-phoenix/test/dawarich/photos/provider_client_test.exs`.
- Limits: The Rails probe used an upstream that deliberately echoed synthetic credentials; ordinary responses are not claimed to always disclose them.

### FRB-014 — Malformed provider bases fetch the wrong resource

Appending an asset path to a query-bearing base can fetch the provider root and incorrectly confirm an asset. Clients validate configured base URLs before appending resource paths.

- Rails: `app/services/photos/thumbnail.rb:50; app/services/immich/verify_enrichment.rb:20; app/services/immich/connection_tester.rb:47,70; app/services/photoprism/connection_tester.rb:33; app/services/immich/request_photos.rb:37; app/services/photoprism/request_photos.rb:68; app/services/air_trail/client.rb:16; app/services/tesla_mate/client.rb:83; app/services/trek/client.rb:56,68`.
- Phoenix: `app-phoenix/lib/dawarich/photos/provider_http.ex:11,33; app-phoenix/lib/dawarich/immich/enrichment.ex:124; native integrations through the same transport`.
- Fix/acceptance history: `82bd3677b` (feature only); `36391927e` (feature only).
- Modes: native provider calls in standalone and coexistence; Rails-owned calls unchanged.
- Evidence: impl-fix-photo-provider-client.report.md:42; fix2-fix-photo-provider-client.report.md:64. Ledger: none added.
- Test: “photo clients validate configured base URLs before appending resource paths” in `app-phoenix/test/dawarich/photos/provider_client_test.exs`.
- Test: “verification and integration clients reject malformed bases instead of confirming the root” in `app-phoenix/test/dawarich/photos/provider_verification_test.exs`.
- Test: “other user-configured integration providers refuse redirects, invalid bases and oversized streams” in `app-phoenix/test/dawarich/photos/provider_inventory_test.exs`.

### FRB-015 — A restore loses tile invalidation during a cache outage

Points can commit while the old tile token remains; a duplicate replay inserts no points and skips invalidation. Accepted point writes publish durable owner-routed invalidation. Native workers and the port’s strict Rails-owned command consumer retain retry work on cache failure.

- Rails: `app/services/users/import_data/points.rb:115-117; app/services/tile_epoch.rb:21-24,55`.
- Phoenix: `app-phoenix/lib/dawarich/user_data/restore/point_writer.ex:81-85; existing RailsEffects.tile_epoch and Points.TileEpochWorker; app/services/points/tile_epoch_command.rb:7-17; app/services/points/arrival_commands.rb:12`.
- Fix/acceptance history: `660180efa` (feature only); `f0f12e185` (feature only).
- Modes: standalone and coexistence, including the real Rails-owned port command consumer after f0f12e185; original direct Rails writers remain best effort.
- Evidence: impl-fix-exports-redelivery.report.md:55; fix2-fix-exports-redelivery.report.md:25,68. Ledger: DRB-028; ED-FIX-EXPORTS-TILE in scoped export docs.
- Test: “restore cache outage retains durable invalidation through duplicate replay” in `app-phoenix/test/dawarich/user_data/restore_points_test.exs`.
- Test: “R2 retains Rails-owned tile invalidation through a real cache outage and consumes it after recovery” in `spec/services/rails_commands/poller_spec.rb:62`, verified in `f0f12e185`.
- Limits: The port-owned command consumer is hardened; original Rails direct writes remain unchanged. This follow-up is a port consumption repair, not a new inherited Rails bug.
- Review history: `rereview-fix-exports-redelivery.report.md:31` reproduced lost Rails-owned intent. `fix2-fix-exports-redelivery.report.md:25` resolves that R2 through the actual strict consumer; R1 retains and characterizes inherited physical purge loss. The earlier CHANGES verdict must not be mistaken for the current consumer state.

### FRB-016 — An unsupported response format commits an area write

A valid create/update can persist and enqueue relabel work before returning 406; retrying a create can duplicate it. Format negotiation happens before mutation; missing/foreign update targets still return 404.

- Rails: `app/controllers/areas_controller.rb:12-13,28-29`.
- Phoenix: `app-phoenix/lib/dawarich_web/area_actions.ex:11-19`.
- Fix/acceptance history: `4d27354a9` (integrated).
- Modes: native area POST/PATCH/PUT in standalone and coexistence.
- Evidence: impl-fix-area-writes.report.md:73. Ledger: ED-FIX-AREA-NEGOTIATION; no DRB for this corrected ordering.
- Test: “area Accept negotiation selects Rails Turbo responses before any write” in `app-phoenix/test/dawarich_web/area_writes_regression_test.exs`.
- Limits: Radius coercion remains deliberately preserved as DRB-026.

### FRB-017 — Bootstrap credentials are written to logs

The initial account’s credentials are printed in the debug log during install. Native bootstrap omits account credentials from logs.

- Rails: `db/seeds.rb:17`.
- Phoenix: `app-phoenix/lib/dawarich/seeds/bootstrap_user.ex:35`.
- Fix/acceptance history: `4d4ea6929` (integrated).
- Modes: self-hosted native bootstrap; Cloud lifecycle remains refused.
- Evidence: expected_diffs.md ED-532; docs/phoenix/a12h-lifecycle.md. Ledger: ED-532.
- Test: “seed credentials are usable but absent from logs” in `app-phoenix/test/dawarich/seeds/bootstrap_user_test.exs`.
- Limits: This concerns initial installation, not a claim that all historic logs are scrubbed.

### FRB-018 — Localized titles double-escape apostrophes

Some translated document titles display the literal entity instead of an apostrophe. The native document title escapes once.

- Rails: `app/helpers/application_helper.rb:45; app/views/layouts/application.html.erb:4`.
- Phoenix: `app-phoenix/lib/dawarich_web/layouts.ex:17; app-phoenix/lib/dawarich_web/layouts/root.html.heex:4`.
- Fix/acceptance history: `ba56fd03e` (integrated); `8c69f9404` (integrated).
- Modes: native page rendering; self-hosted/Cloud-specific test matrix unverified.
- Evidence: expected_diffs.md ED-551; deferred-rails-bugs.md DRB-019. Ledger: ED-551; DRB-019 is already corrected, not preserved.
- Test: “unverified: ED-551 names the locale corpus, not an exact regression title”.
- Limits: ED-551 explicitly accepts the correction; do not reintroduce it for parity. The test-only acceptance commit is not claimed to introduce the renderer; the originating renderer fix commit is unverified.

## Older ED corrections needing release reconciliation

These contrasts are present in the pinned ED register. They are kept visible here so earlier fixes are not silently lost, but their current fix provenance/activation is **unverified**. They are not user-facing release claims until the missing fields and current behavior are checked. Named tests below identify existing evidence where available; they do not fill an unknown fix commit.

| ID / evidence | Reported symptom and native difference | Rails file:line | Phoenix fix commit / test | Deployment modes and limits |
| --- | --- | --- | --- | --- |
| FRB-019 / ED-237 | A checksum-invalid disk upload can remove an existing object; native staging preserves it. | `Active Storage 8.1.3.1 lib/active_storage/service/disk_service.rb:21-26,207-212` | **unverified** commit; **unverified** exact test name | native disk uploads; Cloud/self-hosted matrix unverified. |
| FRB-020 / ED-253 | Corrupt cross-account import dependents can be deleted; native deletion refuses them. | `app/services/imports/destroy.rb (line unverified)` | **unverified** commit; “foreign-user child linkage is refused before deleting or changing status” (`app-phoenix/test/dawarich/imports/destroy_worker_test.exs`); precise defect coverage unverified | native GPX deletion; some Rails forwarders also guard it. |
| FRB-021 / ED-362 | A yearly digest failure leaves duplicate cleanup committed; native calculation rolls both writes back. | `unverified` | **unverified** commit; “failure rolls back digest writes and reports the original exception” (`app-phoenix/test/dawarich/digests/calculation_test.exs`); precise defect coverage unverified | native calculation; historical ED says inert until caller switches. |
| FRB-022 / ED-382 | Point deletion commits before counters/follow-ups; native changes and intent are atomic. | `app/controllers/points_controller.rb (precise deletion line unverified)` | **unverified** commit; “points redirects counters and intent projection match Rails” (`app-phoenix/test/dawarich_web/map_writes_parity_test.exs`); precise defect coverage unverified | native map point deletion; activation proof unverified. |
| FRB-023 / ED-274 | Family location-request creation partially commits before an email enqueue failure; native writes are atomic. | `app/services/families/create_location_request.rb (line unverified)` | **unverified** commit; “a failure after the first write rolls every table back and hands the request to Rails” (`app-phoenix/test/dawarich_web/api/family_writes_golden_test.exs`); precise defect coverage unverified | native family API; current legacy action reconciliation unverified. |
| FRB-024 / ED-086 | An invitation-mail worker can run before its invitation commits and send nothing; native intent commits with invitation. | `unverified` | **unverified** commit; **unverified** exact test name | native invitation command ownership only. |
| FRB-025 / ED-484 | Orphan cleanup can detach a newly committed active visit; native locked eligibility rechecks keep it. | `unverified` | **unverified** commit; “new active reference or FK conflict keeps the place and references intact” (`app-phoenix/test/dawarich/places/orphans_test.exs`); precise defect coverage unverified | native single-place and sweep owners; historical ED says disabled ownership. |
| FRB-026 / ED-480 | Expired range state or repeat generation loses/repeats work; native durable ranges retain selected windows and receipts. | `unverified` | **unverified** commit; **unverified** exact test name | native range/generation owners; historical ED says disabled ownership. |
| FRB-027 / ED-433 | Repeated successful recalculation jobs can repeat notices; native terminal effects settle per retained event. | `unverified` | **unverified** commit; **unverified** exact test name | accepted native recalculation; marker retention bounds deduplication. |
| FRB-028 / ED-490 | Eviction of consumed trial-welcome claims permits replay; revised callers use durable claims. | `unverified` | **unverified** commit; “two real PG welcome contenders permit exactly one claim” (`app-phoenix/test/dawarich/trial/welcome_claim_test.exs`); precise defect coverage unverified | revised Rails/native authority; first switch permits one residual replay and needs Eugene activation review. |
| FRB-029 / ED-491 | Losing registration cache resets admin policy to environment default; initialized native policy uses durable state. | `unverified` | **unverified** commit; “native registration reads copied false and stored nil without Redis” (`app-phoenix/test/dawarich/auth/registration_setting_test.exs`); precise defect coverage unverified | initialized native readers/writers after copy; source continuity and activation review required. |
| FRB-030 / ED-405 | A delayed realtime setup survives disconnect/early toggle and can duplicate subscriptions; shared controller cancels it. | `unverified` | **unverified** commit; **unverified** exact test name | shared Rails/Phoenix browser controller; historical Rails baseline defect may already be repaired. |
| FRB-031 / ED-185 | Raw geocoding responses are printed to stdout; native provider diagnostics omit response bodies. | `Freika geocoder fork (exact file/line unverified)` | **unverified** commit; **unverified** exact test name | native geocoding; current error-reporting policy/activation unverified. |
| FRB-032 / ED-008 | A failed migration leaves an already enqueued job; native version ledger records intents atomically. | `data-migration/job enqueue call sites (exact files/lines unverified)` | **unverified** commit; **unverified** exact test name | native release migrator; nontransactional/version details need current proof. |
| FRB-042 / ED-006 | Session lock-timeout changes can reach another client through transaction pooling; native migration refuses nonzero timeout. | `db/migrate/20260816120000* and 20260818201239* (exact filenames/lines unverified)` | **unverified** commit; **unverified** exact test name | native migrator; current pinned-connection reconciliation unverified. |
| FRB-043 / ED-542 | Readable activity bytes with wrong checksum/size or empty content can be imported; native reader rejects them. | `Active Storage download and activity backfill caller (exact file/line unverified)` | **unverified** commit; **unverified** exact test name | native activity backfill; ED explicitly requires Eugene acceptance before ownership/lifecycle activation. |
| FRB-044 / ED-135 | A long velocity string can be truncated by the Ruby float parser, changing its value; native parser reads the whole string. | `app/services/transportation_modes/feature_extractor.rb:37; Ruby strtod implementation (exact line unverified)` | **unverified** commit; **unverified** exact test name | native feature extraction; correction-versus-parser-difference ruling unverified. |

## Proposed Rails map-matching branch comparisons

These reports compare Phoenix with `feat/map-matching`, not the Rails 1.15.3 release reference. The port fixes are retained for controller review, but inclusion as **Rails 1.15.3 release bugs is unverified**. Do not fold them into the confirmed release list merely because their port commits are integrated. No new ED/DRB row was added by these packages.

### FRB-033 — Atlas responses can exhaust memory

Atlas health/version/match calls buffer arbitrarily large replies. Advertised and cumulative streamed bytes are capped at 8 MiB.

- Rails: `feat/map-matching:app/services/map_matching/atlas/client.rb:93,110`.
- Phoenix: `app-phoenix/lib/dawarich/map_matching/atlas/client.ex:139-146,169-179`.
- Fix history: `0d17811fc` (integrated).
- Modes: native Atlas calls; deployment-mode matrix unverified.
- Evidence: fix-mm-b.report.md:63.
- Test: “rejects oversized Content-Length responses for every Atlas call” in `app-phoenix/test/dawarich/map_matching/atlas/client_test.exs`.
- Test: “rejects oversized streams without Content-Length before completion” in `app-phoenix/test/dawarich/map_matching/atlas/client_test.exs`.
- Limits: Comparison is the proposed Rails map-matching branch, not verified Rails 1.15.3 behavior.

### FRB-034 — Atlas drip replies can run indefinitely

An idle-read timeout resets on each read, letting a drip-fed reply hold requests/workers indefinitely. A 75-second total request deadline also bounds the network operation.

- Rails: `feat/map-matching:app/services/map_matching/atlas/client.rb:89-93`.
- Phoenix: `app-phoenix/lib/dawarich/map_matching/atlas/client.ex:79,85-122,128-165,181-185`.
- Fix history: `0d17811fc` (integrated).
- Modes: native Atlas calls; deployment-mode matrix unverified.
- Evidence: fix-mm-b.report.md:63.
- Test: “cuts off a drip response at the overall request deadline” in `app-phoenix/test/dawarich/map_matching/atlas/client_test.exs`.
- Limits: Comparison is the proposed Rails map-matching branch, not verified Rails 1.15.3 behavior.

### FRB-035 — Provider diagnostics retain arbitrary strings

Malformed provider statistics can persist arbitrary strings, potentially including trace text, in diagnostic metrics. Only numeric values from the metric allowlist are retained.

- Rails: `feat/map-matching:app/services/map_matching/processor.rb:86,96`.
- Phoenix: `app-phoenix/lib/dawarich/map_matching/processor.ex:126`.
- Fix history: `3694efd40` (integrated).
- Modes: native map matching; deployment-mode matrix unverified.
- Evidence: impl-mm-c.report.md:16.
- Test: “data has no PII” in `app-phoenix/test/dawarich/map_matching/processor_test.exs`.
- Limits: Comparison is the proposed Rails map-matching branch. This is not a claim that matched paths contain no user data.

### FRB-036 — A matching claim commits without its job

Enqueue failure after claim commit leaves unusable pending state or fails the surrounding operation. Claim and job insertion commit/rollback together, with SQL errors isolated.

- Rails: `feat/map-matching:app/services/tracks/map_matching/enqueuer.rb:30; app/jobs/tracks/map_match_job.rb:8`.
- Phoenix: `app-phoenix/lib/dawarich/tracks/map_matching/enqueuer.ex:8,17,100`.
- Fix history: `9e4eae732` (feature only).
- Modes: native matching enqueuer; deployment-mode matrix unverified.
- Evidence: impl-mm-d.report.md:12.
- Test: “claim and Oban insert commit together; an insert failure rolls the claim back” in `app-phoenix/test/dawarich/tracks/map_matching/enqueuer_test.exs`.
- Limits: Proposed Rails branch comparison; no Rails 1.15.3 claim.

### FRB-037 — Matching claims fingerprint stale input

Input is read before the track lock, allowing a concurrent edit to produce an outdated claimed digest. Input and its fingerprint are loaded under the row lock.

- Rails: `feat/map-matching:app/services/tracks/map_matching/enqueuer.rb:25`.
- Phoenix: `app-phoenix/lib/dawarich/tracks/map_matching/enqueuer.ex:32,39`.
- Fix history: `9e4eae732` (feature only).
- Modes: native matching enqueuer; deployment-mode matrix unverified.
- Evidence: impl-mm-d.report.md:12.
- Test: “digest is computed under the row lock: a concurrent input change between read and claim cannot publish a stale digest” in `app-phoenix/test/dawarich/tracks/map_matching/enqueuer_test.exs`.
- Limits: Proposed Rails branch comparison; no Rails 1.15.3 claim.

### FRB-038 — Skipped matching overwrites a concurrent result

Skipped publication occurs without the claim lock and can overwrite another result. Skipped publication shares the track lock and is idempotent.

- Rails: `feat/map-matching:app/services/tracks/map_matching/enqueuer.rb:81`.
- Phoenix: `app-phoenix/lib/dawarich/tracks/map_matching/enqueuer.ex:32,68,73`.
- Fix history: `9e4eae732` (feature only).
- Modes: native matching enqueuer; deployment-mode matrix unverified.
- Evidence: impl-mm-d.report.md:12.
- Test: “skipped is written under the lock and is idempotent” in `app-phoenix/test/dawarich/tracks/map_matching/enqueuer_test.exs`.
- Limits: Proposed Rails branch comparison; no Rails 1.15.3 claim.

### FRB-039 — Abandoned matching claims require manual recovery

A pending claim whose enqueue did not finish stays stuck without a later manual enqueuer call. A periodic bounded sweep recovers stale pending work without duplicate active jobs.

- Rails: `feat/map-matching:app/services/tracks/map_matching/enqueuer.rb:62`.
- Phoenix: `app-phoenix/lib/dawarich/tracks/map_matching/sweeper.ex:8; app-phoenix/config/runtime.exs:105`.
- Fix history: `9e4eae732` (feature only).
- Modes: native non-test matching cron; deployment-mode matrix unverified.
- Evidence: impl-mm-d.report.md:12.
- Test: “stale pending older than 1 h is re-enqueued by the sweeper, fresh pending is not” in `app-phoenix/test/dawarich/tracks/map_matching/sweeper_test.exs`.
- Limits: Proposed Rails branch comparison; no Rails 1.15.3 claim.

### FRB-040 — Re-enabling matching exposes an obsolete path

Edits while matching is disabled retain the former matched state/digest. Changed input invalidates displayability before checking the disabled setting.

- Rails: `feat/map-matching:app/services/tracks/map_matching/enqueuer.rb:21`.
- Phoenix: `app-phoenix/lib/dawarich/tracks/map_matching/enqueuer.ex:44,52`.
- Fix history: `9e4eae732` (feature only).
- Modes: native matching enqueuer; deployment-mode matrix unverified.
- Evidence: impl-mm-d.report.md:12.
- Test: “input change while disabled clears displayability, re-enable does not show the old path” in `app-phoenix/test/dawarich/tracks/map_matching/enqueuer_test.exs`.
- Limits: Proposed Rails branch comparison; no Rails 1.15.3 claim.

### FRB-041 — Narrow demo controls overlap attribution

The proposed Rails matching demo overlays route controls with map attribution on narrow screens. Controls sit above attribution and translated labels wrap.

- Rails: `feat/map-matching:app/views/admin/settings/_section.html.erb:41`.
- Phoenix: `app-phoenix/lib/dawarich_web/components/admin_experimental/demo.html.heex:31`.
- Fix history: unverified.
- Modes: standalone browser probe only.
- Evidence: impl-mm-f10.report.md:15,54.
- Test: “unverified: browser probe named demo controls do not overlap attribution at 390px”.
- Limits: The report snapshot was still awaiting a commit and full-suite completion. Proposed Rails branch comparison; omit from publishable release claims until verified.

## Deferred Rails defects and retained policies

This summary follows [deferred-rails-bugs.md](deferred-rails-bugs.md), with later report-backed rows explicitly identified. “Required preservation” in that source is a policy/plan requirement, not proof that every unusual response branch is implemented. Suggested repairs are not authorized by this compilation.

| IDs | Deliberately preserved or required parity | Decision / boundary |
| --- | --- | --- |
| DRB-001 | Mobile ID-token exchange accepts absent/blank nonce. | Explicit retained legacy policy; Eugene/client rollout decision required before tightening. |
| DRB-002–004 | Structured year inputs, malformed digest toponyms and post-2037 residency queries fail. | Separate validation/schema repair; no blanket normalization approved. |
| DRB-005–007, DRB-009 | Malformed timezone/date/pagination inputs fail. | Older ED fallback/normalization needs reconciliation; completed parity is not asserted here. |
| DRB-008, DRB-010 | Malformed import extraction cards and invalid export archive names fail. | Preserve failure; repair payload/name policy separately. |
| DRB-011–012 | Invitation route quirks and malformed sharing settings/durations fail, sometimes after a write. | Keep authorization, consent and existing partial-effect boundaries. |
| DRB-013 | Digest enqueue precedes a possibly failing sent marker; marker means enqueue, not successful delivery. | Duplicate-mail risk retained; no exactly-once SMTP promise. |
| DRB-014–018 | Malformed stats/insights/digest/settings data breaks pages or navbar. | Validation/migration needed; old ED defaults are not accepted fixes by this task. |
| DRB-020 | Invalid JSON share creation returns HTML 500; failed live replacement still publishes ended events. | Explicit preservation under ruling 13. |
| DRB-021–022 | Timeline JSON key order and cleanup delay assignment are unspecified. | Native timeline keys are deterministic but values/parity are preserved; no new user-facing bug claim. |
| DRB-024 | A route video with a blank stored name fails retention instead of expiring. | Malformed-record failure preserved. |
| DRB-025 | Rails-owned physical purge loses failed deletion targets. | Preserved Rails consumer; native fix is FRB-002. Controller must reconcile stronger both-consumer review criteria. |
| DRB-026 | Area numericality and integer casting disagree, accepting a zero stored radius from a positive fraction. | Explicit preservation; FRB-016 fixes format ordering only. |
| DRB-027 | A live signed backup/export link grants bytes to any bearer, including guests/foreign accounts. | **NEEDS EUGENE DECISION:** owner-only download policy versus retained bearer behavior. Report-backed row in `e5b48b6e1`, `impl-fix-exports-redelivery.report.md:18`; independently verified by `rereview-fix-exports-redelivery.report.md:51`. Not in the pinned integration deferred register. |
| DRB-029 | Rails-owned import deletion leaves prepared redirect/disk capabilities usable until async purge. | Preserved source consumer; native revocation is FRB-004. Report-backed row in `de698433d`, `fix2-fix-imports-storage.report.md:13`. Not in the pinned integration deferred register. |

DRB-019 is already corrected by accepted ED-551 (FRB-018), not a deliberately preserved Phoenix bug. DRB-023 is the deferred Rails repair for the fixed Phoenix thumbnail leak (FRB-001). DRB-028 is the deferred Rails cache repair for FRB-015, recorded in `e5b48b6e1`; native-consumer retry and the port’s Rails-owned durable command consumer are fixed; original Rails direct writers retain best-effort loss. DRB-027/028/029 identities come from those reports/commits and must be reconciled with subsequent integration edits, not silently renumbered here.

ED-542 (FRB-043) also explicitly needs Eugene acceptance before native ownership/lifecycle activation. No ruling here authorizes Cloud native lifecycle, changes signed-link policy, or edits the ED/DRB ledgers.

## Provider transport corrections merged after consolidation

### FRB-045 — Immich enrichment verification follows unsafe requests


Rails verification follows cross-host redirects with the Immich key, buffers
oversized EXIF responses, and confirms a provider root response after appending
an asset path to a query-bearing base. Actual `Immich::VerifyEnrichment` loopback
probes reproduce all three defects, including 33,554,473-byte valid JSON.
Rails sources: `app/services/immich/verify_enrichment.rb:19` and `:20`.

Phoenix's real verification worker now delegates its default transport to
`ProviderHTTP` with the configured base separate from the asset path and its
existing five-second timeout. A redirect, malformed base or oversized response
cannot confirm the asset; notification/pass/event behavior remains unchanged.
Phoenix sources: `app-phoenix/lib/dawarich/immich/enrichment.ex:88` and `:124`;
shared policy at `app-phoenix/lib/dawarich/photos/provider_http.ex:33`.

Named tests in `app-phoenix/test/dawarich/photos/provider_verification_test.exs`:
“verification worker refuses cross-host redirects without forwarding its Immich
key”; “verification and integration clients cancel oversized valid JSON before
its terminator”; “verification and integration clients reject malformed bases
instead of confirming the root”. Each has RED, GREEN and its named mutation;
the real worker runs without an HTTP override in coexistence and standalone.

CHANGELOG-ready: Prevent Immich verification from disclosing credentials through
redirects or confirming oversized responses and unrelated provider resources.
No ED/DRB row added; these extend the existing photo corrections under ruling 17.

### FRB-046 — Integration provider transports skip the shared request limits


Immich and PhotoPrism connection checks and geodata imports now share native
provider validation and streaming bounds. PhotoPrism preview-token caching and
import ownership checks remain in their existing callers. Rails counterparts
buffer and concatenate unchecked bases at
`app/services/immich/connection_tester.rb:47`, `:70`,
`app/services/photoprism/connection_tester.rb:33`,
`app/services/immich/request_photos.rb:37`, and
`app/services/photoprism/request_photos.rb:68`.

The whole-tree census also found direct transports in user-configured AirTrail,
TeslaMate and TREK clients. All now use `ProviderHTTP`. TREK retains its existing
SSRF resolver and connects to that approved address with the original hostname;
TeslaMate retains its existing retry classification and attempt budget.
AirTrail and TeslaMate refuse redirects and malformed bases; one trailing slash
is still normalized. Native integration bodies above 32 MiB close while streaming.

Actual Rails probes show oversized JSON and query-base root responses accepted
by AirTrail, TeslaMate and TREK. Rails sources:
`app/services/air_trail/client.rb:16`, `app/services/tesla_mate/client.rb:83`, and
`app/services/trek/client.rb:56`, `:68`. Phoenix sources:
`app-phoenix/lib/dawarich/air_trail/client.ex:13`,
`app-phoenix/lib/dawarich/imports/teslamate/client.ex:68`, and
`app-phoenix/lib/dawarich/imports/trek/client.ex:42`.

Named regression: “other user-configured integration providers refuse redirects,
invalid bases and oversized streams” in
`app-phoenix/test/dawarich/photos/provider_inventory_test.exs`. Two AirTrail
regressions in `app-phoenix/test/dawarich/air_trail/client_test.exs` separately
refuse cross-host HTTPS redirects with certificate verification enabled/skipped.
All have RED, GREEN and named mutations. Existing malformed double-slash success
expectations now require refusal; no retry counts or timeouts were widened.

CHANGELOG-ready: Bound native integration responses and reject redirects and
malformed integration endpoints before provider data can be accepted.
No ED/DRB row added; controller owns ledger consolidation.
AFFiNE counterpart remains `5-hALFzd96DSlwiLB8lt5`.

# Rails bugs fixed in the Phoenix port — draft register

Status: **DRAFT**, consolidated 2026-10-07 under master-plan ruling 17. [User-facing draft](CHANGELOG-phoenix-draft.md); [deferred source register](deferred-rails-bugs.md); [intentional differences](../../app-phoenix/parity/expected_diffs.md).

The integration snapshot is `3a20a0279c164472b7d9b129576709acff94a552` on `feat/phoenix-port`. The audit reads every `## Rails bugs fixed (changelog)` section in the 391 top-level `*.report.md` files present at the snapshot (232 sections), then checks merge history and commit ancestry. Repeated report bullets and provider-package supplements are consolidated by defect. Unmerged fix-rxstats and mm-e reports are excluded. Report filenames and section lines identify external controller evidence; no runtime allocation belongs in this register.

The final delta audits all 109 top-level reports modified after 2026-10-07 13:30 and the branches merged after consolidation (`2db1646d3` / `060633521`), through integration head `069b5dbcd`. Earlier fix-rxstats evidence is now included because that branch merged as `31b4bbe9e`; unmerged L1 guard-flip evidence remains excluded. FRB-066–069 were already added by integrated owners; the delta extends existing entries and adds FRB-070–083 without counting repeated report bullets twice.

FRB-001–083 are unique register IDs, with one CHANGELOG-ready line each. Earlier IDs were renumbered or consolidated; explicit legacy anchors preserve existing links. Older ED candidates without established Rails/fix/test provenance remain in an appendix without confirmed FRB IDs. The withdrawn disabled-map-matching invalidation claim is not a release fix. The digest season change for 27 timezone aliases restores Phoenix parity and is not a Rails bug.

Source lines refer to the report or named source revision and may move. Tests are the implementation evidence; this documentation task reruns only tests that read these registers. Proposed Rails map-matching comparisons are clearly marked and must not be represented as Rails 1.15.3 defects. Native and retained Rails consumers have separate boundaries. Rails remains unchanged by this documentation task. Native Cloud lifecycle remains refused in every mode pending external L1 handoff; this register is not deployment acceptance.

## Consolidated fixes

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

- Test files: `app-phoenix/test/dawarich_web/a12f3b_s02_test.exs`.

- CHANGELOG-ready: Stop serving shared trip thumbnails after a trip boundary edit excludes them, including requests forwarded to Rails.

### FRB-002 — Failed physical media deletion loses its retry target

Storage deletion can fail after the blob/variant rows disappear, leaving private files stored and serialized retries unable to recover their targets. Native cleanup keeps guarded rows and durable storage identities until all eligible object deletions succeed; pending native capabilities are revoked.

- Rails: `app/services/posters/purge_commands.rb:21; app/services/exports/purge_commands.rb:21; app/services/rails_commands/a8_handlers.rb:29; app/controllers/trips_controller.rb:65; app/models/trip.rb:15; Active Storage 8.1.3.1 app/models/active_storage/blob.rb:335-338 and app/jobs/active_storage/purge_job.rb:6-11`.
- Phoenix: `app-phoenix/lib/dawarich/posters/purge_worker.ex:51; app-phoenix/lib/dawarich/storage/native_purge.ex:16,46; app-phoenix/lib/dawarich/exports/purge_worker.ex:30,39 (668862bf3),167-184 (76e0c260d); app-phoenix/lib/dawarich/trips/attachments.ex:188`.
- Fix/acceptance history: `7232bbfa9` (integrated); `668862bf3` (integrated); `79ba18bef` (integrated); `76e0c260d` (integrated); `e50845403` (integrated).
- Modes: standalone and native-owned coexistence cleanup; Rails-owned coexistence remains defective.
- Evidence: fix-a12f3b-e-media.report.md:47; fix2-a12f3b-e-media.report.md:67; rereview3-a12f3b-e-media.report.md:60; impl-fix-exports-redelivery.report.md:55; impl-a12f3a-t-edges.report.md:50; rereview-fix-exports-redelivery.report.md:9. Ledger: ED-A12F3B-E13-F1/F2; DRB-025; ED-FIX-EXPORTS-PURGE in scoped export docs.
- Test: “F1 captured poster purge retains failed storage work until retry and drain completion” in `app-phoenix/test/dawarich/a12f3b_e13_purge_retry_test.exs`.
- Test: “F2 every shared native producer retains blob and variant rows through storage failure and serialized retry” in `app-phoenix/test/dawarich/a12f3b_e13_shared_purge_test.exs`.
- Test: “backup and export redelivery purge every generation storage before rows” in `app-phoenix/test/dawarich/user_data/export_worker_test.exs`.
- Test: “T04: signed trip attachments persist and dependent purge retries storage before rows” in `app-phoenix/test/dawarich/trips/rich_attachments_test.exs`.
- Limits: Deduplicates F1/F2, export redelivery and trip attachment reports. F4 graph collection is a Phoenix defect, not another inherited bug. ED-522 pending-import cleanup shares the storage-before-row principle, and the import cleanup report supplies its source/test provenance below.
- Pending-import extension: Rails `app/models/import.rb:12-13,22`; Phoenix `app-phoenix/lib/dawarich/imports/prepared_download_purge_worker.ex:7,24`. Evidence: impl-fix-rximports.report.md:51; test “unavailable storage retains blob metadata until physical purge succeeds” in `app-phoenix/test/dawarich/fix_rximports_test.exs`. ED-522 shares this storage-before-metadata root cause; no new ED/DRB row was added.
- Account-deletion extension: Rails `app/services/users/destroy.rb:20,142`; Phoenix `app-phoenix/lib/dawarich/users/destroy_effects.ex:29` and shared `app-phoenix/lib/dawarich/exports/purge_worker.ex:49`. Test “deletion commits purge and after-commit intents once and storage failure keeps its ledger” in `app-phoenix/test/dawarich/users/standalone_deletion_test.exs`; evidence `impl-fix-sa-account-deletion.report.md`. Reuses ED-A12F3B-E13-F1/F2; no new DRB or separate storage-ordering defect.
- Trip preview extension: fix-a12f3a-t-edges.report.md:39; Rails `app/models/trip.rb:15`; Phoenix `app-phoenix/lib/dawarich/trips/attachments.ex:185`; test “R1: trip purge removes preview graph storage-first and revokes capabilities while preserving shared variants”.

- Test files: `app-phoenix/test/dawarich/a12f3b_e13_purge_retry_test.exs`; `app-phoenix/test/dawarich/a12f3b_e13_shared_purge_test.exs`; `app-phoenix/test/dawarich/fix_rximports_test.exs`; `app-phoenix/test/dawarich/trips/review_findings_test.exs`; `app-phoenix/test/dawarich/trips/rich_attachments_test.exs`; `app-phoenix/test/dawarich/user_data/export_worker_test.exs`.

- CHANGELOG-ready: Keep failed native media deletion retryable until eligible files are physically removed. Rails-owned cleanup retains its existing limitation.

### FRB-003 — An upload can be claimed by a different account

Another authenticated user possessing an unattached signed upload can claim its bytes for an import. A server-side upload receipt binds admission to the uploader.

- Rails: `app/controllers/imports_controller.rb:158,164`.
- Phoenix: `app-phoenix/lib/dawarich/storage/upload_receipts.ex:4,12; app-phoenix/lib/dawarich/imports/upload_admission.ex:18`.
- Fix/acceptance history: `3c5808570` (integrated).
- Modes: native import admission in standalone and coexistence; Rails-owned admission is unchanged.
- Evidence: impl-fix-imports-storage.report.md:57. Ledger: none added.
- Test: “another user cannot claim an upload created in the victim session” in `app-phoenix/test/dawarich_web/import_storage_security_test.exs`.

- Test files: `app-phoenix/test/dawarich_web/import_storage_security_test.exs`.

- CHANGELOG-ready: Bind import uploads to the account that created them.

### FRB-004 — Import deletion leaves a prepared download usable

An application-issued prepared-download capability can remain usable while asynchronous cleanup waits. Native-owned deletion revokes the capability at deletion commit and retains durable object cleanup.

- Rails: `app/models/import.rb:195-196; app/services/imports/prepared_download_purge_commands.rb:33; Active Storage 8.1.3.1 app/models/active_storage/attachment.rb:150-152`.
- Phoenix: `app-phoenix/lib/dawarich/imports/import_blob_purges.ex:66; app-phoenix/lib/dawarich/imports/prepared_download_purge_worker.ex:43`.
- Fix/acceptance history: `3c5808570` (integrated); `91b09c4e7` (integrated).
- Modes: standalone regardless of stored owner, and native-owned coexistence; Rails-owned coexistence preserves delayed revocation.
- Evidence: impl-fix-imports-storage.report.md:57; fix2-fix-imports-storage.report.md:13,51. Ledger: DRB-029 added by follow-up; no shared ED row.
- Test: “deleting an import revokes its prepared blob capability immediately” in `app-phoenix/test/dawarich_web/import_storage_security_test.exs`.
- Limits: An already-issued external object-storage URL remains governed by deletion/expiry. The follow-up is a native ordering repair, not a second inherited defect.
- Cleanup-owner extension: fix3-fix-imports-storage.report.md:48; all native removals revoke before either cleanup owner runs. Tests “native destruction revokes issued links before either cleanup owner runs” and “native ZIP removal authorizes every owned attachment before revoking” in `import_deletion_security_test.exs` and `zip_deletion_security_test.exs` (on/off, Oban/Sidekiq). Rails-initiated deletion remains unchanged.

- Test files: `app-phoenix/test/dawarich_web/import_deletion_security_test.exs`; `app-phoenix/test/dawarich_web/import_storage_security_test.exs`; `app-phoenix/test/dawarich_web/zip_deletion_security_test.exs`.

- CHANGELOG-ready: Revoke native prepared-import downloads when the import is deleted. Previously issued external storage links remain subject to deletion or expiry.

### FRB-005 — Legacy extraction replay repeats terminal effects

Ordinary legacy extraction jobs have no expected-request identity by default and can process and publish effects again. Terminal effects and event settlement commit together; replay of the same completed event is inert.

- Rails: `app/jobs/enhanced_import/extract_job.rb:43`.
- Phoenix: `app-phoenix/lib/dawarich/enhanced_import/request_fence.ex:49`.
- Fix/acceptance history: `3c5808570` (integrated).
- Modes: native extraction dispatch in standalone/native-owned coexistence.
- Evidence: impl-fix-imports-storage.report.md:57. Ledger: none added.
- Test: “the same completed extraction event does not execute its effects twice through dispatch” in `app-phoenix/test/dawarich/enhanced_import/request_fence_test.exs`.
- Limits: Typed Rails extraction already fences identity; the dropped native typed payload was a Phoenix defect. No permanent exactly-once guarantee is claimed.

- Test files: `app-phoenix/test/dawarich/enhanced_import/request_fence_test.exs`.

- CHANGELOG-ready: Prevent completed extraction retries from repeating their saved effects.

### FRB-006 — An old removal retry can remove newer extraction data

Ordinary legacy removal defaults to no expected identity and operates on the current extraction. Each batch/reset is fenced to its accepted request, and completed requests are recognized.

- Rails: `app/jobs/enhanced_import/destroy_job.rb:7; app/services/enhanced_import/destroy.rb:15`.
- Phoenix: `app-phoenix/lib/dawarich/enhanced_import/destroy_gpx_worker.ex:30; app-phoenix/lib/dawarich/enhanced_import/request_fence.ex:70`.
- Fix/acceptance history: `3c5808570` (integrated).
- Modes: native legacy extraction removal in standalone/native-owned coexistence.
- Evidence: impl-fix-imports-storage.report.md:57. Ledger: none added.
- Test: “a retried old removal cannot delete a newer extraction through dispatch” in `app-phoenix/test/dawarich/enhanced_import/request_fence_test.exs`.
- Limits: Typed Rails removal already has an expected-request fence.

- Test files: `app-phoenix/test/dawarich/enhanced_import/request_fence_test.exs`.

- CHANGELOG-ready: Prevent an older extraction-removal retry from deleting a newer extraction.

### FRB-007 — An old upload capability can recreate purged storage

A still-valid disk upload token can write its purged key again. Publication requires a live locked upload receipt, including a purge between staging and publication.

- Rails: `Active Storage 8.1.3.1 app/controllers/active_storage/disk_controller.rb:24; lib/active_storage/service/disk_service.rb:21`.
- Phoenix: `app-phoenix/lib/dawarich_web/active_storage.ex:141`.
- Fix/acceptance history: `3c5808570` (integrated).
- Modes: native disk upload handling in standalone and coexistence.
- Evidence: impl-fix-imports-storage.report.md:57. Ledger: none added.
- Test: “a successful purge cannot be undone with the old upload capability” in `app-phoenix/test/dawarich_web/import_storage_security_test.exs`.
- Test: “purge between upload staging and publication prevents object resurrection” in `app-phoenix/test/dawarich_web/import_storage_security_test.exs`.
- Limits: Rails behavior is source-backed; the report does not claim a Rails HTTP token-replay experiment.

- Test files: `app-phoenix/test/dawarich_web/import_storage_security_test.exs`.

- CHANGELOG-ready: Prevent an old upload capability from recreating a file after it has been purged.

### FRB-008 — Failed GPX retries repeat failure notifications

A failed GPX import remains eligible for processing, whose rescue creates another failure notification on retry. Handled failure, notification and terminal receipt commit together; marker recovery does not repeat them.

- Rails: `app/services/imports/gpx_legacy.rb:20,28; app/services/imports/create.rb:47`.
- Phoenix: `app-phoenix/lib/dawarich/imports/gpx_lifecycle.ex:110,123; app-phoenix/lib/dawarich/imports/import_state.ex:96; app-phoenix/lib/dawarich/imports/lease.ex:37`.
- Fix/acceptance history: `efd232870` (integrated).
- Modes: accepted native GPX work in standalone and coexistence.
- Evidence: fix-a12f3b-e-imports.report.md:71. Ledger: none added.
- Test: “R1 real GPX failure survives marker rejection without processing or notifying twice” in `app-phoenix/test/dawarich/a12f3b_e09_test.exs`.
- Limits: The marker-rejection reproduction is native. Rails source establishes analogous failed-job retries; no Rails broker-ack crash reproduction is claimed.
- Normal-discovered GPX extension: fix2-fix-standalone-zip.report.md:26; Phoenix `app-phoenix/lib/dawarich/imports/normal_lifecycle.ex:138,154`; test “normal-discovered GPX notification is exactly once after interrupted failure in on” and its off counterpart in `app-phoenix/test/dawarich/imports/interrupted_failure_test.exs`. ED-FIX-ACCEPTED-IMPORT-DISPOSITION; no new DRB.

- Test files: `app-phoenix/test/dawarich/a12f3b_e09_test.exs`.

- CHANGELOG-ready: Avoid duplicate failure notifications when retrying an accepted failed GPX import.

### FRB-009 — Demo adoption changes another account’s tag

With inconsistent persisted place/tag ownership, a real visit to a demo place marks another owner’s linked demo tag as real. Only demo tags belonging to the import owner are adopted.

- Rails: `app/models/visit.rb:114-120; app/models/concerns/taggable.rb:8`.
- Phoenix: `app-phoenix/lib/dawarich/enhanced_import/item_writer.ex:92-96`.
- Fix/acceptance history: `474c7910d` (integrated).
- Modes: native enhanced-import writer; deployment-mode-specific proof unverified.
- Evidence: fix-a12f3a-f17.report.md:153; fix2-a12f3a-f17.report.md:158. Ledger: none added.
- Test: “an imported visit adopts a matched demo place” in `app-phoenix/test/dawarich/imports/continuation_review_test.exs`.
- Limits: Actual Rails callback probe reproduced this with inconsistent persisted references. No HTTP exploit is claimed.

- Test files: `app-phoenix/test/dawarich/imports/continuation_review_test.exs`.

- CHANGELOG-ready: Keep another account’s demo tags unchanged when importing a visit into inconsistently linked demo data.

### FRB-010 — A late Takeout continuation lowers import progress

An older worker overwrites newer progress; the source probe reproduced 2,000 → 1,000 (a retried predecessor lowered `processed`). Unfinished accepted predecessors order continuation admission, and continuation progress uses a database maximum, so retrying a predecessor never lowers durable import progress and no deferred continuation is cancelled.

- Rails: `app/services/imports/broadcaster.rb:10; app/services/google_maps/records_importer.rb:23; app/jobs/import/google_takeout_job.rb:11`.
- Phoenix: `app-phoenix/lib/dawarich/imports/continuation_receipt.ex:6,92; app-phoenix/lib/dawarich/imports/gpx_progress.ex:13; app-phoenix/lib/dawarich/imports/lease.ex:95`.
- Fix/acceptance history: `a403f9219`, `5d0581805`, `bc4c398b2` (feat/a12f3a-f17, merged `5ef730845`; re-reviewed x3, 24 delivery permutations in both modes).
- F17 progress: no ED/DRB row added (the Rails defect is fixed natively, not preserved).
- Modes: standalone and coexistence accepted continuations.
- Evidence: fix2-a12f3a-f17.report.md:158; rereview2-a12f3a-f17.report.md:84; fix3-a12f3a-f17.report.md:184. F17 progress: no ED/DRB row added.
- Test: “retrying a predecessor never lowers durable import progress” in `app-phoenix/test/dawarich/imports/continuation_order_test.exs`.
- Limits: Automatic Rails Takeout retries remain disabled; the defect concerns delayed/manual accepted continuations.

- Test files: `app-phoenix/test/dawarich/imports/continuation_order_test.exs`.

- CHANGELOG-ready: Keep Google Takeout import progress from going backwards when an older continuation finishes late.

<a id="frb-045--immich-enrichment-verification-follows-unsafe-requests"></a>
<a id="frb-046--integration-provider-transports-skip-the-shared-request-limits"></a>

### FRB-011 — Provider redirects disclose credentials

Cross-host redirects forward photo or integration credentials to a different host. Native clients refuse redirects without contacting the destination, including AirTrail HTTPS and TeslaMate paths.

- Rails: `app/services/photos/thumbnail.rb:19; app/services/immich/verify_enrichment.rb:19; app/services/air_trail/client.rb:16; app/services/tesla_mate/client.rb:83`.
- Phoenix: `app-phoenix/lib/dawarich/photos/provider_http.ex:58; app-phoenix/lib/dawarich/immich/enrichment.ex:124; app-phoenix/lib/dawarich/air_trail/client.ex:13; app-phoenix/lib/dawarich/imports/teslamate/client.ex:68`.
- Fix/acceptance history: `82bd3677b` (integrated); `36391927e` (integrated).
- Modes: native provider requests in standalone and coexistence; direct Rails provider calls remain unchanged.
- Evidence: impl-fix-photo-provider-client.report.md:42; fix2-fix-photo-provider-client.report.md:64. Ledger: none added.
- Test: “photo provider redirects never forward credentials to another host” in `app-phoenix/test/dawarich/photos/provider_client_test.exs`.
- Test: “verification worker refuses cross-host redirects without forwarding its Immich key” in `app-phoenix/test/dawarich/photos/provider_verification_test.exs`.
- Test: “other user-configured integration providers refuse redirects, invalid bases and oversized streams” in `app-phoenix/test/dawarich/photos/provider_inventory_test.exs`.
- Limits: Actual Rails probes confirmed Immich, AirTrail and TeslaMate disclosure. No Rails TLS-verification bypass is claimed.
- Provider coverage: fix2-fix-photo-provider-client.report.md:76 covers Immich verification, connection checks, geodata imports, AirTrail, TeslaMate and TREK through the same root-cause correction. Former provider-package entries are consolidated here, not counted again.

- Test files: `app-phoenix/test/dawarich/photos/provider_client_test.exs`; `app-phoenix/test/dawarich/photos/provider_inventory_test.exs`; `app-phoenix/test/dawarich/photos/provider_verification_test.exs`.

- CHANGELOG-ready: Prevent photo and integration redirects from sending credentials to another host.

### FRB-012 — Provider replies grow memory without a bound

Photo thumbnails, verification, connection checks and integration imports accept oversized replies into memory. Shared transport cancels cumulative responses above 32 MiB, including error replies, before completion.

- Rails: `app/services/photos/thumbnail.rb:19; app/services/immich/verify_enrichment.rb:19; app/services/immich/connection_tester.rb:47,70; app/services/photoprism/connection_tester.rb:33; app/services/immich/request_photos.rb:37; app/services/photoprism/request_photos.rb:68; app/services/air_trail/client.rb:16; app/services/tesla_mate/client.rb:83; app/services/trek/client.rb:56,68`.
- Phoenix: `app-phoenix/lib/dawarich/photos/provider_http.ex:91,121 (82bd3677b); app-phoenix/lib/dawarich/settings/integrations/connection.ex:149; app-phoenix/lib/dawarich/imports/integrations/immich.ex:81; app-phoenix/lib/dawarich/imports/integrations/photoprism.ex:63; app-phoenix/lib/dawarich/imports/trek/client.ex:42`.
- Fix/acceptance history: `82bd3677b` (integrated); `36391927e` (integrated).
- Modes: native provider calls in standalone and coexistence; Rails-owned calls unchanged.
- Evidence: impl-fix-photo-provider-client.report.md:42; fix2-fix-photo-provider-client.report.md:64. Ledger: none added.
- Test: “every photo response is capped during streaming before the provider finishes” in `app-phoenix/test/dawarich/photos/provider_client_test.exs`.
- Test: “verification and integration clients cancel oversized valid JSON before its terminator” in `app-phoenix/test/dawarich/photos/provider_verification_test.exs`.
- Test: “other user-configured integration providers refuse redirects, invalid bases and oversized streams” in `app-phoenix/test/dawarich/photos/provider_inventory_test.exs`.
- Limits: Supersedes the limited success-response cap/handoff described in older ED-195. Atlas has a separate 8 MiB limit in FRB-033.
- Provider coverage: fix2-fix-photo-provider-client.report.md:76 covers Immich verification, connection checks, geodata imports, AirTrail, TeslaMate and TREK through the same root-cause correction. Former provider-package entries are consolidated here, not counted again.

- Test files: `app-phoenix/test/dawarich/photos/provider_client_test.exs`; `app-phoenix/test/dawarich/photos/provider_inventory_test.exs`; `app-phoenix/test/dawarich/photos/provider_verification_test.exs`.

- CHANGELOG-ready: Limit photo and integration response sizes so oversized provider replies cannot grow memory without a bound.

### FRB-013 — Provider error text reflects credentials

An enrichment provider’s reason phrase can echo credentials into returned API errors. Errors contain trusted status text only.

- Rails: `app/services/immich/enrich_photos.rb:67`.
- Phoenix: `app-phoenix/lib/dawarich/photos/enrichment.ex:169`.
- Fix/acceptance history: `82bd3677b` (integrated).
- Modes: native photo enrichment in standalone and coexistence.
- Evidence: impl-fix-photo-provider-client.report.md:42; rereview-fix-photo-provider-client.report.md:86. Ledger: none added.
- Test: “enrichment errors contain only trusted status text when upstream echoes credentials” in `app-phoenix/test/dawarich/photos/provider_client_test.exs`.
- Limits: The Rails probe used an upstream that deliberately echoed synthetic credentials; ordinary responses are not claimed to always disclose them.

- Test files: `app-phoenix/test/dawarich/photos/provider_client_test.exs`.

- CHANGELOG-ready: Keep provider-supplied credentials out of enrichment error messages.

### FRB-014 — Malformed provider bases fetch the wrong resource

Appending an asset path to a query-bearing base can fetch the provider root and incorrectly confirm an asset. Clients validate configured base URLs before appending resource paths.

- Rails: `app/services/photos/thumbnail.rb:50; app/services/immich/verify_enrichment.rb:20; app/services/immich/connection_tester.rb:47,70; app/services/photoprism/connection_tester.rb:33; app/services/immich/request_photos.rb:37; app/services/photoprism/request_photos.rb:68; app/services/air_trail/client.rb:16; app/services/tesla_mate/client.rb:83; app/services/trek/client.rb:56,68`.
- Phoenix: `app-phoenix/lib/dawarich/photos/provider_http.ex:11,33; app-phoenix/lib/dawarich/immich/enrichment.ex:124; native integrations through the same transport`.
- Fix/acceptance history: `82bd3677b` (integrated); `36391927e` (integrated).
- Modes: native provider calls in standalone and coexistence; Rails-owned calls unchanged.
- Evidence: impl-fix-photo-provider-client.report.md:42; fix2-fix-photo-provider-client.report.md:64. Ledger: none added.
- Test: “photo clients validate configured base URLs before appending resource paths” in `app-phoenix/test/dawarich/photos/provider_client_test.exs`.
- Test: “verification and integration clients reject malformed bases instead of confirming the root” in `app-phoenix/test/dawarich/photos/provider_verification_test.exs`.
- Test: “other user-configured integration providers refuse redirects, invalid bases and oversized streams” in `app-phoenix/test/dawarich/photos/provider_inventory_test.exs`.
- Provider coverage: fix2-fix-photo-provider-client.report.md:76 covers Immich verification, connection checks, geodata imports, AirTrail, TeslaMate and TREK through the same root-cause correction. Former provider-package entries are consolidated here, not counted again.

- Test files: `app-phoenix/test/dawarich/photos/provider_client_test.exs`; `app-phoenix/test/dawarich/photos/provider_inventory_test.exs`; `app-phoenix/test/dawarich/photos/provider_verification_test.exs`.

- CHANGELOG-ready: Validate photo and integration base URLs before requesting an asset, avoiding the wrong resource or an incorrect verification result.

### FRB-015 — A restore loses tile invalidation during a cache outage

Points can commit while the old tile token remains; a duplicate replay inserts no points and skips invalidation. Accepted point writes publish durable owner-routed invalidation. Native workers and the port’s strict Rails-owned command consumer retain retry work on cache failure.

- Rails: `app/services/users/import_data/points.rb:115-117; app/services/tile_epoch.rb:21-24,55`.
- Phoenix: `app-phoenix/lib/dawarich/user_data/restore/point_writer.ex:81-85; existing RailsEffects.tile_epoch and Points.TileEpochWorker; app/services/points/tile_epoch_command.rb:7-17; app/services/points/arrival_commands.rb:12`.
- Fix/acceptance history: `660180efa` (integrated); `f0f12e185` (integrated).
- Modes: standalone and coexistence, including the real Rails-owned port command consumer after f0f12e185; original direct Rails writers remain best effort.
- Evidence: impl-fix-exports-redelivery.report.md:55; fix2-fix-exports-redelivery.report.md:25,68. Ledger: DRB-028; ED-FIX-EXPORTS-TILE in scoped export docs.
- Test: “restore cache outage retains durable invalidation through duplicate replay” in `app-phoenix/test/dawarich/user_data/restore_points_test.exs`.
- Test: “R2 retains Rails-owned tile invalidation through a real cache outage and consumes it after recovery” in `spec/services/rails_commands/poller_spec.rb:62`, verified in `f0f12e185`.
- Limits: The port-owned command consumer is hardened; original Rails direct writes remain unchanged. This follow-up is a port consumption repair, not a new inherited Rails bug.
- Review history: `rereview-fix-exports-redelivery.report.md:31` reproduced lost Rails-owned intent. `fix2-fix-exports-redelivery.report.md:25` resolves that R2 through the actual strict consumer; R1 retains and characterizes inherited physical purge loss. The earlier CHANGES verdict must not be mistaken for the current consumer state.

- Test files: `app-phoenix/test/dawarich/user_data/restore_points_test.exs`; `spec/services/rails_commands/poller_spec.rb`.

- CHANGELOG-ready: Retain tile-cache refresh work through a cache outage when restoring points, including the durable command processed by Rails during coexistence.

### FRB-016 — An unsupported response format commits an area write

A valid create/update can persist and enqueue relabel work before returning 406; retrying a create can duplicate it. Format negotiation happens before mutation; missing/foreign update targets still return 404.

- Rails: `app/controllers/areas_controller.rb:12-13,28-29`.
- Phoenix: `app-phoenix/lib/dawarich_web/area_actions.ex:11-19`.
- Fix/acceptance history: `4d27354a9` (integrated).
- Modes: native area POST/PATCH/PUT in standalone and coexistence.
- Evidence: impl-fix-area-writes.report.md:73. Ledger: ED-FIX-AREA-NEGOTIATION; no DRB for this corrected ordering.
- Test: “area Accept negotiation selects Rails Turbo responses before any write” in `app-phoenix/test/dawarich_web/area_writes_regression_test.exs`.
- Limits: Radius coercion remains deliberately preserved as DRB-026.

- Test files: `app-phoenix/test/dawarich_web/area_writes_regression_test.exs`.

- CHANGELOG-ready: Reject unsupported area response formats before saving changes or scheduling follow-up work.

### FRB-017 — Bootstrap credentials are written to logs

The initial account’s credentials are printed in the debug log during install. Native bootstrap omits account credentials from logs.

- Rails: `db/seeds.rb:17`.
- Phoenix: `app-phoenix/lib/dawarich/seeds/bootstrap_user.ex:35`.
- Fix/acceptance history: `4d4ea6929` (integrated).
- Modes: self-hosted native bootstrap; Cloud lifecycle remains refused.
- Evidence: expected_diffs.md ED-532; docs/phoenix/a12h-lifecycle.md. Ledger: ED-532.
- Test: “seed credentials are usable but absent from logs” in `app-phoenix/test/dawarich/seeds/bootstrap_user_test.exs`.
- Limits: This concerns initial installation, not a claim that all historic logs are scrubbed.

- Test files: `app-phoenix/test/dawarich/seeds/bootstrap_user_test.exs`.

- CHANGELOG-ready: Omit initial account credentials from native installation logs.

### FRB-018 — Localized titles double-escape apostrophes

Some translated document titles display the literal entity instead of an apostrophe. The native document title escapes once.

- Rails: `app/helpers/application_helper.rb:45; app/views/layouts/application.html.erb:4`.
- Phoenix: `app-phoenix/lib/dawarich_web/layouts.ex:17; app-phoenix/lib/dawarich_web/layouts/root.html.heex:4`.
- Fix/acceptance history: `ba56fd03e` (integrated); `8c69f9404` (integrated).
- Modes: native page rendering; self-hosted/Cloud-specific test matrix unverified.
- Evidence: expected_diffs.md ED-551; deferred-rails-bugs.md DRB-019. Ledger: ED-551; DRB-019 is already corrected, not preserved.
- Test: “year_ca matches Rails except title double-escaping (ED-551)”, “digests_ca matches Rails except title double-escaping (ED-551)” and “digest_full_fr matches Rails except title double-escaping (ED-551)” in `app-phoenix/test/dawarich_web/stats_parity_test.exs`.
- Limits: ED-551 explicitly accepts the correction; do not reintroduce it for parity. The test-only acceptance commit is not claimed to introduce the renderer; the originating renderer fix commit is unverified.

- CHANGELOG-ready: Display apostrophes correctly in translated document titles.

<a id="frb-033--atlas-responses-can-exhaust-memory"></a>

### FRB-019 — Atlas responses can exhaust memory

Atlas health/version/match calls buffer arbitrarily large replies. Advertised and cumulative streamed bytes are capped at 8 MiB.

- Rails: `feat/map-matching:app/services/map_matching/atlas/client.rb:93,110`.
- Phoenix: `app-phoenix/lib/dawarich/map_matching/atlas/client.ex:139-146,169-179`.
- Fix history: `0d17811fc` (integrated).
- Modes: native Atlas calls; deployment-mode matrix unverified.
- Evidence: fix-mm-b.report.md:63.
- Test: “rejects oversized Content-Length responses for every Atlas call” in `app-phoenix/test/dawarich/map_matching/atlas/client_test.exs`.
- Test: “rejects oversized streams without Content-Length before completion” in `app-phoenix/test/dawarich/map_matching/atlas/client_test.exs`.
- Limits: Comparison is the proposed Rails map-matching branch, not verified Rails 1.15.3 behavior.
- Ledger: no ED/DRB row added; comparison is with the proposed Rails map-matching branch, not Rails 1.15.3.

- Test files: `app-phoenix/test/dawarich/map_matching/atlas/client_test.exs`.

- CHANGELOG-ready: Limit Atlas responses to prevent oversized replies from exhausting memory.

<a id="frb-034--atlas-drip-replies-can-run-indefinitely"></a>

### FRB-020 — Atlas drip replies can run indefinitely

An idle-read timeout resets on each read, letting a drip-fed reply hold requests/workers indefinitely. A 75-second total request deadline also bounds the network operation.

- Rails: `feat/map-matching:app/services/map_matching/atlas/client.rb:89-93`.
- Phoenix: `app-phoenix/lib/dawarich/map_matching/atlas/client.ex:79,85-122,128-165,181-185`.
- Fix history: `0d17811fc` (integrated).
- Modes: native Atlas calls; deployment-mode matrix unverified.
- Evidence: fix-mm-b.report.md:63.
- Test: “cuts off a drip response at the overall request deadline” in `app-phoenix/test/dawarich/map_matching/atlas/client_test.exs`.
- Limits: Comparison is the proposed Rails map-matching branch, not verified Rails 1.15.3 behavior.
- Ledger: no ED/DRB row added; comparison is with the proposed Rails map-matching branch, not Rails 1.15.3.

- Test files: `app-phoenix/test/dawarich/map_matching/atlas/client_test.exs`.

- CHANGELOG-ready: Bound the total time spent waiting for an Atlas reply, including drip-fed responses.

<a id="frb-035--provider-diagnostics-retain-arbitrary-strings"></a>

### FRB-021 — Provider diagnostics retain arbitrary strings

Malformed provider statistics can persist arbitrary strings, potentially including trace text, in diagnostic metrics. Only numeric values from the metric allowlist are retained.

- Rails: `feat/map-matching:app/services/map_matching/processor.rb:86,96`.
- Phoenix: `app-phoenix/lib/dawarich/map_matching/processor.ex:126`.
- Fix history: `3694efd40` (integrated).
- Modes: native map matching; deployment-mode matrix unverified.
- Evidence: impl-mm-c.report.md:16.
- Test: “data has no PII” in `app-phoenix/test/dawarich/map_matching/processor_test.exs`.
- Limits: Comparison is the proposed Rails map-matching branch. This is not a claim that matched paths contain no user data.
- Ledger: no ED/DRB row added; comparison is with the proposed Rails map-matching branch, not Rails 1.15.3.

- CHANGELOG-ready: Store only numeric allowlisted map-matching diagnostics.

<a id="frb-036--a-matching-claim-commits-without-its-job"></a>

### FRB-022 — A matching claim commits without its job

Enqueue failure after claim commit leaves unusable pending state or fails the surrounding operation. Claim and job insertion commit/rollback together, with SQL errors isolated.

- Rails: `feat/map-matching:app/services/tracks/map_matching/enqueuer.rb:30; app/jobs/tracks/map_match_job.rb:8`.
- Phoenix: `app-phoenix/lib/dawarich/tracks/map_matching/enqueuer.ex:8,17,100`.
- Fix history: `9e4eae732` (integrated).
- Modes: native matching enqueuer; deployment-mode matrix unverified.
- Evidence: impl-mm-d.report.md:12.
- Test: “claim and Oban insert commit together; an insert failure rolls the claim back” in `app-phoenix/test/dawarich/tracks/map_matching/enqueuer_test.exs`.
- Limits: Proposed Rails branch comparison; no Rails 1.15.3 claim.
- Ledger: no ED/DRB row added; comparison is with the proposed Rails map-matching branch, not Rails 1.15.3.
- Final follow-up evidence: fix-mm-d.report.md:33; fix2-mm-d.report.md:46. Strict OFF preserves stored matching state; disabled invalidation is not a shipped fix.

- Test files: `app-phoenix/test/dawarich/tracks/map_matching/enqueuer_test.exs`.

- CHANGELOG-ready: Commit map-matching claims and processing jobs together.

<a id="frb-037--matching-claims-fingerprint-stale-input"></a>

### FRB-023 — Matching claims fingerprint stale input

Input is read before the track lock, allowing a concurrent edit to produce an outdated claimed digest. Input and its fingerprint are loaded under the row lock.

- Rails: `feat/map-matching:app/services/tracks/map_matching/enqueuer.rb:25`.
- Phoenix: `app-phoenix/lib/dawarich/tracks/map_matching/enqueuer.ex:32,39`.
- Fix history: `9e4eae732` (integrated).
- Modes: native matching enqueuer; deployment-mode matrix unverified.
- Evidence: impl-mm-d.report.md:12.
- Test: “digest is computed under the row lock: a concurrent input change between read and claim cannot publish a stale digest” in `app-phoenix/test/dawarich/tracks/map_matching/enqueuer_test.exs`.
- Limits: Proposed Rails branch comparison; no Rails 1.15.3 claim.
- Ledger: no ED/DRB row added; comparison is with the proposed Rails map-matching branch, not Rails 1.15.3.
- Final follow-up evidence: fix-mm-d.report.md:33; fix2-mm-d.report.md:46. Strict OFF preserves stored matching state; disabled invalidation is not a shipped fix.

- Test files: `app-phoenix/test/dawarich/tracks/map_matching/enqueuer_test.exs`.

- CHANGELOG-ready: Capture map-matching input under the track lock so concurrent edits cannot claim stale input.

<a id="frb-038--skipped-matching-overwrites-a-concurrent-result"></a>

### FRB-024 — Skipped matching overwrites a concurrent result

Skipped publication occurs without the claim lock and can overwrite another result. Skipped publication shares the track lock and is idempotent.

- Rails: `feat/map-matching:app/services/tracks/map_matching/enqueuer.rb:81`.
- Phoenix: `app-phoenix/lib/dawarich/tracks/map_matching/enqueuer.ex:32,68,73`.
- Fix history: `9e4eae732` (integrated).
- Modes: native matching enqueuer; deployment-mode matrix unverified.
- Evidence: impl-mm-d.report.md:12.
- Test: “skipped is written under the lock and is idempotent” in `app-phoenix/test/dawarich/tracks/map_matching/enqueuer_test.exs`.
- Limits: Proposed Rails branch comparison; no Rails 1.15.3 claim.
- Ledger: no ED/DRB row added; comparison is with the proposed Rails map-matching branch, not Rails 1.15.3.
- Final follow-up evidence: fix-mm-d.report.md:33; fix2-mm-d.report.md:46. Strict OFF preserves stored matching state; disabled invalidation is not a shipped fix.

- Test files: `app-phoenix/test/dawarich/tracks/map_matching/enqueuer_test.exs`.

- CHANGELOG-ready: Keep skipped map-matching publication from overwriting a concurrent result.

<a id="frb-039--abandoned-matching-claims-require-manual-recovery"></a>

### FRB-025 — Abandoned matching claims require manual recovery

A pending claim whose enqueue did not finish stays stuck without a later manual enqueuer call. A periodic bounded sweep recovers stale pending work without duplicate active jobs.

- Rails: `feat/map-matching:app/services/tracks/map_matching/enqueuer.rb:62`.
- Phoenix: `app-phoenix/lib/dawarich/tracks/map_matching/sweeper.ex:8; app-phoenix/config/runtime.exs:105`.
- Fix history: `9e4eae732` (integrated).
- Modes: native non-test matching cron; deployment-mode matrix unverified.
- Evidence: impl-mm-d.report.md:12.
- Test: “stale pending older than 1 h is re-enqueued by the sweeper, fresh pending is not” in `app-phoenix/test/dawarich/tracks/map_matching/sweeper_test.exs`.
- Limits: Proposed Rails branch comparison; no Rails 1.15.3 claim.
- Ledger: no ED/DRB row added; comparison is with the proposed Rails map-matching branch, not Rails 1.15.3.
- Final follow-up evidence: fix-mm-d.report.md:33; fix2-mm-d.report.md:46. Strict OFF preserves stored matching state; disabled invalidation is not a shipped fix.

- Test files: `app-phoenix/test/dawarich/tracks/map_matching/sweeper_test.exs`.

- CHANGELOG-ready: Recover abandoned map-matching claims automatically.

<a id="frb-041--narrow-demo-controls-overlap-attribution"></a>

### FRB-026 — Narrow demo controls overlap attribution

The proposed Rails matching demo overlays route controls with map attribution on narrow screens. Controls sit above attribution and translated labels wrap.

- Rails: `feat/map-matching:app/views/admin/settings/_section.html.erb:41`.
- Phoenix: `app-phoenix/lib/dawarich_web/components/admin_experimental/demo.html.heex:31`.
- Integration: merge `ec9d95ed1` (feat/mm-f10).
- Modes: standalone browser probe only.
- Evidence: impl-mm-f10.report.md:15,54.
- Test: “demo controls do not overlap attribution at 390px” (recorded browser probe in impl-mm-f10.report.md; no ExUnit test is claimed).
- Limits: browser-probe evidence; proposed Rails map-matching UI comparison, not a Rails 1.15.3 release claim.
- Ledger: no ED/DRB row added; comparison is with the proposed Rails map-matching branch, not Rails 1.15.3.

- CHANGELOG-ready: Keep map-matching demo controls clear of attribution on narrow screens.

<a id="frb-040--re-enabling-matching-exposes-an-obsolete-path"></a>

### FRB-027 — Optional map matching delays a completed track operation

Rails proposed map matching waits synchronously for a track row lock or error reporter after the track operation completes. Phoenix defers preparation, locking and reporting until successful outer commit, with bounded optional-supervisor admission.

- Rails: `feat/map-matching:app/services/tracks/map_matching/enqueuer.rb:12,44`; `app/services/tracks/track_builder.rb:106`.
- Phoenix: `app-phoenix/lib/dawarich/tracks/map_matching/enqueuer.ex:6`; `app-phoenix/lib/dawarich/tracks/map_matching/deferred.ex:34`; `app-phoenix/lib/dawarich/tracks/builder.ex:39`.
- Test: “F2 completed builder returns while enabled enqueue waits on an independent row lock” in `app-phoenix/test/dawarich/tracks/map_matching/review_regression_test.exs`.
- Ledger: no ED/DRB row added. This supersedes the earlier disabled-invalidation claim, which the strict OFF ruling withdrew.

- Evidence: fix2-mm-d.report.md:46.

- Test files: `app-phoenix/test/dawarich/tracks/map_matching/review_regression_test.exs`.

- CHANGELOG-ready: Keep optional map matching from delaying an already completed track operation.

<a id="frb-047--a-signed-route-video-upload-can-be-adopted-across-accounts"></a>

### FRB-028 — A signed route-video upload can be adopted across accounts

Rails resolves any valid signed blob before attaching it to the requesting user's
route video, including a blob attached to another account's record. Phoenix
loads only owner-compatible blobs and repeats that admission under the blob row
lock in the attachment transaction. Unknown attachment owners are refused.
Unattached uploads and compatible same-owner attachments remain supported.

- Rails: `app/controllers/route_videos_controller.rb:18`.
- Phoenix: `app-phoenix/lib/dawarich/route_videos/writes.ex:52`.
- Tests: `F1 on refuses another owner blob at adoption` and `F1 off refuses another owner blob at adoption` in `app-phoenix/test/dawarich/media_ownership_test.exs`.
- Ledger: ED-FIX-MEDIA-OWNERSHIP; download bearer policy stays open in DRB-027.

- CHANGELOG-ready: Refuse adopting another account's attached route-video media.

<a id="frb-048--deferred-poster-purges-leave-old-native-downloads-usable"></a>

### FRB-029 — Deferred poster purges leave old native downloads usable

Rails queues physical deletion without immediate logical revocation. Native
legacy poster purge producers now mark eligible parent and variant blobs before
queueing. Already accepted old payloads mark their graph before execution and
retain the marker and durable targets on storage failure. They execute through
the shared storage-first purge helper, preserving arguments and event receipts.
Rails-owned coexistence purges retain their existing behavior (DRB-025).

- Rails: `app/services/posters/purge_commands.rb:14`.
- Phoenix: `app-phoenix/lib/dawarich/posters/purge_worker.ex:10`; `app-phoenix/lib/dawarich/posters/command.ex:39`.
- Tests: `F2 on legacy poster purge immediately revokes parent and variants` and `F2 off legacy poster purge immediately revokes parent and variants` in `app-phoenix/test/dawarich/media_ownership_test.exs`.
- Ledger: ED-FIX-MEDIA-OWNERSHIP; extends FRB-002's shared storage repair.

- CHANGELOG-ready: Revoke native poster download capabilities while deferred purge retries wait.

<a id="frb-049--accepted-rails-poster-jobs-bypass-the-native-handoff-fences"></a>

### FRB-030 — Accepted Rails poster jobs bypass the native handoff fences

An accepted source poster job can generate after its command switches to Oban,
or while a native poster lease remains live. The retained Rails wrapper now
forwards accepted work using its original job ID when Oban owns the command;
source-owned generation holds the shared poster lease and locks command ownership
through the effect. Lease contention raises for retry, preserving the work.
The lease and ownership checks apply in coexistence and standalone drain modes.

- Rails: `app/jobs/posters/create_job.rb:7` (original); corrected wrapper at `:9`.
- Phoenix counterpart: `app-phoenix/lib/dawarich/posters/generation.ex:19` and `app-phoenix/lib/dawarich/posters/publication.ex:12`.
- Tests: `F5 on/off forwards accepted source work to its command owner` and `F5 on/off refuses source generation while a native poster lease is live` in `spec/jobs/posters/media_ownership_spec.rb` (four individually named cases).
- Ledger: ED-FIX-MEDIA-OWNERSHIP; no deferred row added.

- CHANGELOG-ready: Fence accepted Rails poster generation during native job ownership handoff.

<a id="frb-050--demo-removal-can-alter-another-accounts-dependent-records"></a>

### FRB-031 — Demo removal can alter another account's dependent records

Rails demo destruction selects the requesting user's demo records but follows
unscoped dependent associations. A persisted point owned by a second account
can lose its visit/track links; a foreign extracted visit/place/track can lose
its import link. Notes, shares and place/tag joins can also cross account
boundaries. This corrects that inherited defect under controller ruling 17;
Rails remains unchanged.

Native demo removal scopes point updates, extracted import links and dependent
writes to the requesting owner. It locks the owner's demo graph and returns
the existing native error with full rollback when foreign points, notes,
shares, visits or place/tag joins make cleanup unsafe. Unconstrained foreign
import references remain unchanged after marker deletion, matching an
owner-scoped deletion without rewriting the foreign record. Place/trip
deletion receives an explicit owner-scoped option for its final writes.

- Rails: `app/services/demo_data/destroyer.rb:16`, `app/models/visit.rb:10`, `app/models/track.rb:23`, `app/models/import.rb:8`.
- Phoenix: `app-phoenix/lib/dawarich/demo_data/cleanup_scope.ex:39`; `app-phoenix/lib/dawarich/demo_data/destroyer.ex:25`, `:57`.
- Tests in `app-phoenix/test/dawarich/demo_data_destroyer_test.exs`: `demo destroy refuses foreign point associations without changing either owner`; `demo destroy leaves foreign extracted records linked to the removed marker`; `demo destroy refuses foreign notes shares visits and tags before dependent cleanup`.
- Ledger: no ED/DRB row added.

The attached-marker leak reported alongside this issue is a Phoenix regression,
not an inherited Rails bug. Demo removal now detaches every attachment of the
deleted records through the shared storage-first native purge worker. Blob and
variant rows survive physical deletion failure; shared objects and the other
record's attachment remain intact. Unsupported place/visit-note content still
returns an error with rollback before any records disappear.

- Test files: `app-phoenix/test/dawarich/demo_data_destroyer_test.exs`.

- CHANGELOG-ready: Keep demo removal from changing another account's records, even when existing data contains cross-account references.

<a id="frb-051--nightly-reverse-cleanup-acknowledges-a-failed-cache-deletion"></a>

### FRB-032 — Nightly reverse cleanup acknowledges a failed cache deletion

Rails' Redis cache store suppresses a transient `UNLINK` error and returns false.
The user-cache invalidator previously ignored that result, allowing the reverse
command poller to complete `stats.caches_invalidated` while cached countries or
cities remained stale. A successful later Redis operation did not recover the
lost retry.

The shared Rails invalidator now uses a Redis cache store with a raising error
handler, preserving the configured client, pool and namespace. The Phoenix
nightly producer retains its existing durable after-commit reverse command.
The Rails poller backs off that command on Redis or pool failure and completes
it only after cleanup succeeds. Already absent keys remain successful, so
partial cleanup and replay are idempotent. Ordinary application cache reads
and writes keep their default error handler.

- Rails: `app/services/cache/invalidate_user_caches.rb:23`; `app/services/stats/commands.rb:38`; `app/services/rails_commands/poller.rb:98`.
- Phoenix: `app-phoenix/lib/dawarich/geocoding/nightly_sweep.ex:116`, `:121`; `app-phoenix/lib/dawarich/stats/cache_invalidation.ex:27`.
- Test: `R3 retains a failed UNLINK command despite recovered later operations, then retries absent keys idempotently` in `spec/services/rails_commands/stats_cache_retry_spec.rb`.
- Ledger: no ED/DRB row added because the shared adapter fix repairs the same cleanup contract for both consumers.

- Test files: `app-phoenix/test/dawarich/a12f3b_r06_test.exs`; `spec/services/rails_commands/stats_cache_retry_spec.rb`; `spec/services/stats/commands_spec.rb`.

- CHANGELOG-ready: Retry failed nightly cache cleanup instead of leaving countries and cities stale after a transient Redis timeout.

<a id="frb-052--null-island-cleanup-leaves-restored-demo-visit-counts-cached"></a>

### FRB-033 — Null-island cleanup leaves restored demo visit counts cached

Rails deletes an archive-restored demo visit near null island but its demo
callback exclusion leaves cached calendar counts unchanged. Phoenix publishes
all deleted visit timestamps in the cleanup transaction, including demos.

- Rails: `app/jobs/data_migrations/cleanup_null_island_job.rb:28`; `app/models/visit.rb:22`.
- Phoenix: `app-phoenix/lib/dawarich/release_operations/null_island.ex:141`.
- Tests: “null island deletion fences restored demo visit calendar counts after visible deletion in coexistence” and the corresponding “in standalone” in `app-phoenix/test/dawarich_web/visit_writes_regression_test.exs`.
- Evidence: fix4-fix-visits-writes.report.md; named demo-filter mutation, restored GREEN.
- Ledger: ED-FIX-VISITS-NULL-ISLAND. Integrated correction; final controller ID assigned by this consolidation. Rails cleanup remains unchanged; deployment acceptance pending.
- Same demo-callback root cause: demo status/date/area changes and import deletion also omit calendar invalidation. Rails `app/services/enhanced_import/destroy.rb:17,34,55`, `app/models/visit.rb:22`; Phoenix `app-phoenix/lib/dawarich/imports/destroy_effects.ex:55,64`, `app-phoenix/lib/dawarich/visits_api/effects.ex:36`, `app-phoenix/lib/dawarich/areas/api.ex:90`. Tests “demo API visit status and date writes invalidate calendar counts while preserving demo ownership” and the on/off import deletion regressions. Evidence: fix2-fix-visits-writes.report.md:160; fix3-fix-visits-writes.report.md:95. Ledger: ED-FIX-VISITS-CACHE and ED-FIX-VISITS-NULL-ISLAND; no DRB added.

- Test files: `app-phoenix/test/dawarich_web/visit_writes_regression_test.exs`.

- Demo/import tests: `app-phoenix/test/dawarich_web/visit_writes_regression_test.exs` and `app-phoenix/test/dawarich/imports/destroy_worker_test.exs`; null-island mode names are generated from coexistence/standalone labels.

- CHANGELOG-ready: Refresh calendar counts after demo visit edits or deletion, including import and null-island cleanup.

<a id="frb-053--stale-concurrent-suggestions-truncate-newer-committed-visits"></a>

### FRB-034 — Stale concurrent suggestions truncate newer committed visits

A delayed Rails computation can replace a newer 50-minute/six-point visit with
its older 30-minute/four-point result, or drop a seventh point from a same-range
visit. A settings change can also make an older empty computation erase a newer
50-minute/six-point visit. Phoenix fences the captured policy, areas and provider
configuration under the user-row persistence lock, skips obsolete batches, and
revalidates the machine window and full candidate evidence before replacement.
Final stitching is also fenced in one locked transaction with validation of its
live visit inputs, preventing obsolete stitched output after a settings change.

- Rails: `app/services/visits/detection/runner.rb:26,41`; `app/services/visits/detection/persister.rb:30,35`.
- Phoenix: `app-phoenix/lib/dawarich/visits/persister.ex:26`; `app-phoenix/lib/dawarich/visits/runner.ex:101`.
- Tests: “concurrent native suggestions preserve the longer committed stay: overlap” and “concurrent native suggestions preserve the longer committed stay: same_range” in `app-phoenix/test/dawarich/visits/concurrent_suggestions_test.exs`.
- Additional tests: “a precomputed suggestion cannot erase the newer result after detection settings change in coexistence” and its standalone counterpart in the same file; real settings writer, both lock configurations, complete-row/claim preservation and redelivery.
- Stitch tests: “a settings change before stitching cannot publish obsolete visits in coexistence” and its standalone counterpart in the same file.
- Evidence: fix4-fix-visits-writes.report.md and fix5-fix-visits-writes.report.md; deterministic query barriers, failing locked-refresh/policy-fence mutations, restored GREEN.
- Ledger: ED-FIX-VISITS-CONCURRENT. Integrated correction; final controller ID assigned by this consolidation. Confirmed/declined/tombstone anchors remain protected; Rails detection remains unchanged; deployment acceptance pending.

- Test file: `app-phoenix/test/dawarich/visits/concurrent_suggestions_test.exs`; case names are generated for overlap/same_range and coexistence/standalone.

- CHANGELOG-ready: Preserve newer visit duration and point associations when suggestions execute concurrently or detection settings change during a run.

### FRB-035 — ZIP parents settle before their children finish

Rails removes a successful ZIP parent while member imports remain pending. Phoenix keeps the parent and accepted event nonterminal until every accepted child is terminal.

- Rails: `app/services/imports/zip_extractor.rb:45,157`.
- Phoenix: `app-phoenix/lib/dawarich/imports/zip_fanout.ex:183`; `app-phoenix/lib/dawarich/imports/zip_children.ex:57`.
- Tests: “ZIP parent waits for all five terminal children in on” and its off counterpart.
- Ledger: ED-FIX-ACCEPTED-IMPORT-DISPOSITION; no DRB added.

- Evidence: fix2-fix-standalone-zip.report.md:26.

- Test file: `app-phoenix/test/dawarich/imports/standalone_zip_test.exs`.

- CHANGELOG-ready: Wait for ZIP member imports to finish before settling or removing their parent.

### FRB-036 — A partial ZIP failure strands already accepted members

Rails can save earlier ZIP members with processing suppressed, then omit their enqueue when a later member fails validation. Phoenix durably queues every accepted child after a partial build error and waits before failing the parent.

- Rails: `app/services/imports/zip_extractor.rb:130,138,146`.
- Phoenix: `app-phoenix/lib/dawarich/imports/zip_fanout.ex:75`; `app-phoenix/lib/dawarich/imports/zip_children.ex:17`.
- Tests: “partial ZIP build retains an executor for accepted children before parent failure in on” and its off counterpart.
- Ledger: ED-FIX-ACCEPTED-IMPORT-DISPOSITION; no DRB added. Rails partial-build ordering is source-backed; interruption probes execute natively.

- Evidence: fix2-fix-standalone-zip.report.md:26.

- Test file: `app-phoenix/test/dawarich/imports/partial_zip_disposition_test.exs`.

- CHANGELOG-ready: Keep accepted ZIP members processing when a later archive member fails validation.

### FRB-037 — Empty successful import retries repeat no-points notifications

Rails inserts a no-points notice before recording completion, so an interrupted successful attempt can notify again on retry. Phoenix commits the notice, completed status and terminal attachment receipt together.

- Rails: `app/services/imports/create.rb:38,52,72,153`.
- Phoenix: `app-phoenix/lib/dawarich/imports/postprocessing.ex:10,160,185`; `app-phoenix/lib/dawarich/imports/normal_lifecycle.ex:112`; `app-phoenix/lib/dawarich/imports/gpx_lifecycle.ex:80`.
- Tests: “empty empty.gpx notification exactly once across interrupted success in on” and off; the corresponding empty.kml cases.
- Test file: `app-phoenix/test/dawarich/imports/interrupted_empty_success_test.exs`.
- Ledger: ED-FIX-ACCEPTED-IMPORT-DISPOSITION; no DRB added. Rails interruption ordering is source-backed; four real-worker interruption/retry probes execute natively.

- Evidence: fix3-fix-standalone-zip.report.md:58.

- CHANGELOG-ready: Emit one no-points notice per successful empty import across interrupted processing and retry.

### FRB-038 — Track tile epoch write failure is ignored

Rails track after-commit callbacks ignore false epoch-write results and rescue exceptions, leaving stale tile validators without retry. Phoenix commits database visibility generations with track changes and acknowledges epoch delivery only after successful Redis writes. The generation also protects readers if an asynchronous intent is discarded.

- Rails: `app/models/track.rb:299,310`; `app/services/tile_epoch.rb:29,53-55`.
- Phoenix: `app-phoenix/lib/dawarich/tracks/native_changes.ex:8,76-83`; `app-phoenix/lib/dawarich/after_commit.ex:16,28`; `app-phoenix/lib/dawarich/tiles/http.ex:131,134`.
- Tests: “review: failed epoch invalidation retains durable retry debt”; “P6 discarded track intent cannot validate the predelete tile”.
- Ledger: DRB-028; no new ED/DRB row. FRB-015 covers the related restore producer. Evidence also includes fix2-fix-after-commit-effects.report.md:65. The Rails refusing-cache probe uses actual source classes without boot or a real Redis request.

- Evidence: fix2-fix-rxtracks.report.md:27.

- Test files: `app-phoenix/test/dawarich/after_commit_review_test.exs`; `app-phoenix/test/dawarich/tracks/native_effects_regression_test.exs`.

- Test files: `app-phoenix/test/dawarich/tracks/native_effects_regression_test.exs`; `app-phoenix/test/dawarich/after_commit_review_test.exs`.

- CHANGELOG-ready: Keep track tiles current and retry invalidation after failed cache writes.

### FRB-039 — Empty-month reset evicts before commit

Rails empty-month reset evicts inside its transaction, allowing precommit readers to repopulate old values or a rollback to invalidate valid cache. Phoenix commits an eviction intent with the write and retries after commit. Rails `app/services/stats/calculate_month.rb:140`; Phoenix `app-phoenix/lib/dawarich/stats/cache_invalidation.ex:5`. Tests `F1 anomaly stats retains cache and cancels intent on rollback` and `F1 reader repopulation is repaired by committed invalidation intent`. ED/DRB row added: no (systemic controller assignment).

- Evidence: fix2-fix-after-commit-effects.report.md:65.
- Ledger: no new ED/DRB row; systemic controller assignment.

- Test files: `app-phoenix/test/dawarich/after_commit_regression_test.exs`.

- CHANGELOG-ready: Keep statistics caches valid on rollback and refresh them after a committed empty-month reset.

### FRB-040 — Digest cache eviction is lost during an outage

Rails calls delete-matched without a persisted eviction intent or retry boundary, so derived digests can remain cached after their source changes. Phoenix checks matched batch results and retains a durable retryable intent. Rails `app/services/cache/invalidate_user_caches.rb:45`, `app/services/stats/calculate_month.rb:56`; Phoenix `app-phoenix/lib/dawarich/stats/cache_invalidation.ex:45`, `app-phoenix/lib/dawarich/points/dependent_caches.ex:25`. Tests `F3 digest batch eviction errors remain retryable`, `cache outage retains a durable retryable intent and replay is idempotent`. ED/DRB row added: no.

- Evidence: fix2-fix-after-commit-effects.report.md:65.
- Ledger: no new ED/DRB row; systemic controller assignment.

- Test files: `app-phoenix/test/dawarich/after_commit_regression_test.exs`; `app-phoenix/test/dawarich/after_commit_test.exs`.

- CHANGELOG-ready: Retry failed digest cache eviction after source data changes.

### FRB-041 — A failed statistics calculation is acknowledged

Rails rescues calculation/job failure, so stale statistics can remain without a durable retry. Phoenix anomaly/general workers return the true failure to Oban. Rails `app/services/stats/calculate_month.rb:24`, `app/jobs/stats/calculating_job.rb:21`; Phoenix `app-phoenix/lib/dawarich/points/anomaly_stats_worker.ex:8`, `app-phoenix/lib/dawarich/stats/calculate_month_worker.ex:21`. Tests `F2 anomaly stats propagates calculation failure for retry`, `general stats worker returns a failed calculation to Oban`. ED/DRB row added: no.

- Evidence: fix2-fix-after-commit-effects.report.md:65.
- Ledger: no new ED/DRB row; systemic controller assignment.

- Test files: `app-phoenix/test/dawarich/after_commit_regression_test.exs`; `app-phoenix/test/dawarich/after_commit_test.exs`.

- CHANGELOG-ready: Retry failed statistics calculations instead of leaving stale results.

### FRB-042 — Anomaly flags commit without their derived rebuilds

Rails updates flags separately from cache and job follow-ups; failure after flags can leave derived tracks/stats/achievements stale, and overlap can enqueue duplicate rebuilds. Phoenix serializes the user and records effects atomically. Rails `app/services/points/anomaly_filter.rb:222`, `:234`, `:249`; Phoenix `app-phoenix/lib/dawarich/points/anomaly_arrival_worker.ex:37`. Tests `F5 anomaly arrival rolls back flags when durable publication fails`, `F5 concurrent anomaly arrivals publish each follow-up once`. ED/DRB row added: no.

Rails archive restore rescues filtering errors after separate flag updates and dependent enqueues; replay skips flagged points and may never rebuild their derived data. Phoenix's common filter now commits all flags and intents atomically for archive restore as well as arrival. Rails `app/services/users/import_data.rb:177`, `app/services/points/anomaly_filter.rb:222`, `:249`; Phoenix `app-phoenix/lib/dawarich/points/anomaly_filter.ex:11`. Test `P7 restored-import anomaly flags must commit with all downstream intents`. ED/DRB row added: no.

- Evidence: fix2-fix-after-commit-effects.report.md:65.
- Ledger: no new ED/DRB row; systemic controller assignment.

- Test files: `app-phoenix/test/dawarich/after_commit_regression_test.exs`; `app-phoenix/test/dawarich/after_commit_review_test.exs`.

- CHANGELOG-ready: Commit anomaly flags and their track, statistics and achievement rebuilds together, including restored points.

### FRB-043 — Point deletion commits without counters or rebuilds

Rails commits deletion before counter/cache/job work; failure can remove points while counters or derived data remain stale. Phoenix rolls back deletion, counters and all intents together. Rails `app/services/points/destroyer.rb:12` and `:18`; Phoenix `app-phoenix/lib/dawarich/points/api_writes.ex:197`. Test `F6 failed API follow-up rolls back deletion and counters`; retained HTTP counter-failure regression now asserts the point survives. ED/DRB row added: no.

- Evidence: fix2-fix-after-commit-effects.report.md:65.
- Ledger: no new ED/DRB row; systemic controller assignment.

- Test files: `app-phoenix/test/dawarich/after_commit_regression_test.exs`.

- CHANGELOG-ready: Keep point deletion, counters and derived-data rebuild work consistent when a follow-up fails.

### FRB-044 — A failed live point update is permanently suppressed

Rails claims the broadcast before delivery, so replay suppresses an unsuccessful broadcast. Phoenix commits the replay completion marker and full PG batch together only on success. Rails `app/services/points/arrival_commands.rb:47`; Phoenix `app-phoenix/lib/dawarich/points/live_broadcast_worker.ex:41`. Test `F8 failed native live publication rolls back claim and whole batch`. ED/DRB row added: no.

- Evidence: fix2-fix-after-commit-effects.report.md:65.
- Ledger: no new ED/DRB row; systemic controller assignment.

- Test files: `app-phoenix/test/dawarich/after_commit_regression_test.exs`.

- CHANGELOG-ready: Retry failed live point broadcasts without treating an unsuccessful publication as delivered.

### FRB-045 — Demo import loses cache eviction after an outage

Rails catches postcommit cache failures without durable recovery. Phoenix records eviction with the import transaction. Rails `app/services/demo_data/importer.rb:48`; Phoenix `app-phoenix/lib/dawarich/demo_data/importer.ex:95`. Test `demo cache eviction is recorded before the enclosing write commits`. ED/DRB row added: no.

- Evidence: fix2-fix-after-commit-effects.report.md:65.
- Ledger: no new ED/DRB row; systemic controller assignment.

- Test files: `app-phoenix/test/dawarich/after_commit_test.exs`.

- CHANGELOG-ready: Retry cache refreshes after demo data is imported.

### FRB-046 — Demo removal loses its rebuild or cache eviction

Rails catches postcommit follow-up failure, so removed demo data can remain reflected in caches/stats. Phoenix records eviction and calculation intents with destruction. Rails `app/services/demo_data/destroyer.rb:29`; Phoenix `app-phoenix/lib/dawarich/demo_data/destroyer.ex:79`. Test `demo DELETE preserves real data and publishes native recalculations`. ED/DRB row added: no.

- Evidence: fix2-fix-after-commit-effects.report.md:65.
- Ledger: no new ED/DRB row; systemic controller assignment.

- Test files: `app-phoenix/test/dawarich_web/a12f3b_n09_test.exs`.

- CHANGELOG-ready: Retain statistics rebuilds and cache refreshes after demo data is removed.

### FRB-047 — Accepted subscription changes lose rate-plan eviction

Rails evicts after the accepted subscription update without durable recovery; a claimed callback may not reapply eviction. Phoenix queues eviction with the subscription row and retries consumption. Rails `app/controllers/api/v1/subscriptions_controller.rb:75`; Phoenix `app-phoenix/lib/dawarich/subscriptions/callback.ex:118`. Tests `subscription rollback preserves Redis plan cache and cancels eviction intent`, `cache outage retains a durable retryable intent and replay is idempotent`, retained `H4 Subscription promotion and downgrade invalidate the real native and Rails rate plan caches`. ED/DRB row added: no.

- Evidence: fix2-fix-after-commit-effects.report.md:65.
- Ledger: no new ED/DRB row; systemic controller assignment.

- Test files: `app-phoenix/test/dawarich/after_commit_account_cache_test.exs`; `app-phoenix/test/dawarich/after_commit_test.exs`; `app-phoenix/test/dawarich_web/a12f2_h_closure_test.exs`.

- CHANGELOG-ready: Refresh rate-limit plans reliably after a subscription changes.

### FRB-048 — A paid family subscription loses its family follow-up

Rails uses postcommit enqueue callbacks; failure after the subscription commit can leave an accepted family plan without family creation/member synchronization. Phoenix persists those family intents inside the subscription transaction; failure rolls back and permits replay. Rails `app/models/user.rb:59`, `:480`, `:490`; Phoenix `app-phoenix/lib/dawarich/subscriptions/callback.ex:130`. Test `P1 family follow-up must roll back with subscription or remain replayable`. ED/DRB row added: no.

- Evidence: fix2-fix-after-commit-effects.report.md:65.
- Ledger: no new ED/DRB row; systemic controller assignment.

- Test files: `app-phoenix/test/dawarich/after_commit_review_test.exs`.

- CHANGELOG-ready: Keep accepted family subscriptions linked to durable family creation and member synchronization.

### FRB-049 — Non-admin users can queue test email

Rails permits an authenticated self-hosted non-admin to queue test mail. Phoenix requires admin admission before native or pinned Rails routing; the worker refuses a user demoted after enqueue. This is explicitly authorized policy hardening.

- Rails: `app/controllers/settings/general_controller.rb:8,9,74`.
- Phoenix: `app-phoenix/lib/dawarich_web/endpoint.ex:40`; `app-phoenix/lib/dawarich_web/test_email_gate.ex:23,51`; `app-phoenix/lib/dawarich/mail/test_email.ex:21`; `app-phoenix/lib/dawarich/mail/test_email_worker.ex:13`.
- Tests: “test email producer and worker refuse non admins including demotion after enqueue”; “non admin test email POST is refused locally without Rails handoff or enqueue”; “non admin test email never reaches Rails even with the route pinned to Rails”.
- Ledger: ED-MAIL-TEST-ADMIN; no DRB added.

- Evidence: fix3-a12f3b-mail.report.md:47.

- Test files: `app-phoenix/test/dawarich/mail/review_findings_test.exs`; `app-phoenix/test/dawarich_web/residual_mail_ownership_test.exs`; `app-phoenix/test/dawarich_web/test_email_test.exs`.

- CHANGELOG-ready: Require an administrator to send test email, including jobs queued before demotion.

### FRB-050 — Successful test-email redelivery sends another message

Rails rebuilds and delivers test mail on job redelivery without an application receipt. Phoenix retains a successful receipt for the accepted identity while separate requests remain distinct. Remote SMTP acceptance followed by a local receipt failure remains ambiguous; this is not a universal exactly-once delivery guarantee.

- Rails: `app/controllers/settings/general_controller.rb:74`; `app/mailers/users_mailer.rb:54,57`.
- Phoenix: `app-phoenix/lib/dawarich/mail/test_email_worker.ex:13,38`; `app-phoenix/lib/dawarich/mail/delivery.ex:42,53`.
- Test: “successful test email redelivery sends once while separate accepted jobs remain distinct”.
- Ledger: ED-MAIL-TEST-REDELIVERY; DRB-013 digest-mail sent-marker ordering remains preserved.

- Evidence: fix3-a12f3b-mail.report.md:47.

- Test files: `app-phoenix/test/dawarich/mail/review_findings_test.exs`.

- CHANGELOG-ready: Suppress duplicate successful test emails when the same accepted job is redelivered.

### FRB-051 — NULL user settings crash default readers and settings writes

NULL settings crash Rails map HTML in the integration-enabled helpers. Phoenix renders the default map instead. Rails: `app/models/user.rb:233` and `:237`; Phoenix: `app-phoenix/lib/dawarich/map_page.ex:23`, `app-phoenix/lib/dawarich/user_settings.ex:90`. Test: `NULL settings preserve Rails bodies for public HTML PNG map stats timeline settings and API`. ED/DRB row: none added (controller root-fix assignment, no assigned plan row).

Rails NULL settings crash photo integration checks before an unconfigured response can be returned. Phoenix answers native 401 JSON (`Immich integration not configured`) for SQL NULL and JSON null. Rails: `app/models/user.rb:233` and `:237`; Phoenix: `app-phoenix/lib/dawarich_web/api/photos_controller.ex:75`, `app-phoenix/lib/dawarich/user_settings.ex:90`. Test: `NULL and JSON null settings use the default unconfigured photo response`. ED/DRB row: none added.

NULL settings crash Rails family-sharing and lapse-notice `dig` calls. Phoenix defaults family sharing to disabled, returns no shared member coordinates, and reads an absent notice marker as nil. Rails: `app/models/concerns/user_family.rb:48`, `:101`, `:111`, `:115`, `:124`, `:128`, `:132`; `app/services/families/lapse_notice.rb:10`. Phoenix: `app-phoenix/lib/dawarich/families/sharing.ex:7`, `:19`, `app-phoenix/lib/dawarich/families/lapse_notices.ex:10`, `app-phoenix/lib/dawarich/mail/family_lapse_worker.ex:151`. Tests: historical `golden replay_member_settings_null`, `an expiry equal to now has expired, one microsecond later has not`, and `shared user accessor fills absent Rails keys and preserves explicit values`. ED/DRB row: none added.

NULL settings crash Rails general/API/onboarding/integration settings updates when they index or merge the raw container. Phoenix uses an empty supplied map before those mutations and does not persist the full default map. Rails: `app/controllers/settings/general_controller.rb:97`, `:103`, `:110`; `app/controllers/settings/onboardings_controller.rb:8`; `app/services/users/settings_updater.rb:17`, `:18`, `:71`, `:85`; `app/services/settings/update.rb:55`. Phoenix: `app-phoenix/lib/dawarich/settings/general.ex:15`, `app-phoenix/lib/dawarich/settings/onboarding.ex:13`, `app-phoenix/lib/dawarich/settings/api.ex:139`, `app-phoenix/lib/dawarich/settings/integrations.ex:12`, `:21`. Test: `shared user accessor fills absent Rails keys and preserves explicit values` verifies supplied NULL/map/malformed-container behavior; existing full-suite write tests verify raw persistence. Direct NULL write HTTP characterization was outside the requested seven read endpoints. ED/DRB row: none added.

Rails direct locale and recalculation-marker model readers raise on NULL settings. Phoenix's locale and operation readers use shared defaults/absent values. Rails: `app/models/user.rb:148`, `:193`; Phoenix: `app-phoenix/lib/dawarich_web/locale.ex:94`, `app-phoenix/lib/dawarich/release_operations/anomalies_user.ex:38`, `app-phoenix/lib/dawarich/user_settings.ex:94`. Tests: `shared user accessor fills absent Rails keys and preserves explicit values`, `NULL settings preserve Rails bodies for public HTML PNG map stats timeline settings and API`, and `the parameter, then the user's own choice, then the Rails session, then English`. ED/DRB row: none added.

SQL NULL and JSON null, absent keys and malformed containers share the settings-normalization root cause. All five reported surfaces are covered here once. Achievement HTML/PNG already handles NULL in Rails and is excluded. Invalid non-string sharing expiry remains preserved as DRB-018.

- Evidence: impl-fix-null-settings.report.md:217.

- Test files: `app-phoenix/test/dawarich/families/sharing_test.exs`; `app-phoenix/test/dawarich_web/api/locations_photos_endpoint_test.exs`; `app-phoenix/test/dawarich_web/locale_test.exs`; `app-phoenix/test/dawarich_web/null_settings_test.exs`.

- CHANGELOG-ready: Use default settings instead of crashing map, photo, family-sharing, locale and settings flows when the settings container is NULL.

### FRB-052 — A failed settings or area response leaves changes committed

**Failed-response writes survive in Rails:** mobile PATCH and area POST/PATCH commit before rendering, so a render exception tells the client the request failed while settings or the area remain written (confirmed by render-oracle.log). Phoenix now encloses mobile/area writes, relabel outbox, JSON encoding and response headers in one transaction and rolls back on rendering/service failure. Rails: app/controllers/api/v1/settings/mobile_controller.rb:30 (commit ends at 38; render 45), app/controllers/api/v1/areas_controller.rb:19 (render 20; update 27–28). Phoenix: app-phoenix/lib/dawarich_web/api/write_response.ex:10, mobile_settings_controller.ex:20, areas_controller.ex:23. Test: `response rendering failures roll back mobile and area writes and outbox effects`. ED/DRB row added: **no**; this exact durability correction is explicitly mandated by the controller brief. Shared controller-owned difference/deferred-bug registers remain untouched.

- Digest DELETE extension: Rails destroys the digest before preparing its empty response (`app/controllers/api/v1/digests_controller.rb:42-43`). Phoenix prepares the 204 body and headers inside `Api.WriteResponse`, preserving an empty body and absent content-type; response-framing failures roll back deletion even on an idle database connection. Phoenix: `app-phoenix/lib/dawarich_web/api/digest_writes_controller.ex:24`; `app-phoenix/lib/dawarich_web/api/write_response.ex:14`; `app-phoenix/lib/dawarich_web/api/respond.ex:82`. Test: “digest remains durable after failed response preparation on an idle connection” in `app-phoenix/test/dawarich_web/standalone_digest_response_test.exs`. Evidence: fix2-fix-sa-api-gaps.report.md (F3). Mode: standalone API; retained Rails remains unchanged. No additional ED/DRB row.
- Standalone demo/digest/area extension: Rails commits demo import/removal, digest calculation enqueue or area deletion before response rendering (`app/controllers/api/v1/demo_data_controller.rb:11,15,24,28`; `app/controllers/api/v1/digests_controller.rb:35,36`; `app/controllers/api/v1/areas_controller.rb:35,37`). Phoenix stages each write and durable follow-up with response preparation (`app-phoenix/lib/dawarich_web/api/demo_data_controller.ex:15`; `app-phoenix/lib/dawarich_web/api/digest_writes_controller.ex:10`; `app-phoenix/lib/dawarich_web/api/areas_controller.ex:14`). Test “standalone API response failures roll back domain writes and after commit jobs” in `app-phoenix/test/dawarich_web/standalone_api_gaps_test.exs`; evidence `impl-fix-sa-api-gaps.report.md`. No ED/DRB row added; these surfaces share the existing response-atomicity defect.

- Evidence: impl-fix-settings-api-parity.report.md:91.

- Test files: `app-phoenix/test/dawarich_web/settings_api_parity_test.exs`.

- CHANGELOG-ready: Roll back mobile settings, demo changes, digest generation/deletion, area changes and follow-up work when response preparation fails.

### FRB-053 — Public month and digest pages crash for a deleted owner

**Deleted-owner public month/digest crash.** In Rails, an otherwise enabled capability can crash while its owner is soft-deleted: stats dereferences the nil association during bounds/rendering (`app/controllers/shared/stats_controller.rb:20`, `app/models/stat.rb:119`); digest dereferences nil settings (`app/controllers/shared/digests_controller.rb:21–22`). Phoenix now refuses that capability with the existing root redirect and unavailable-share alert (`app-phoenix/lib/dawarich/stats/sharing.ex:46`, `app-phoenix/lib/dawarich/digests/sharing.ex:100`). Test: `public month and digest refuse a deleted or absent owner without crashing`. ED row added: **ED-FIX-PUBLIC-SHARE-OWNER**; no DRB row needed. Locked/NULL-settings and stored-expiry changes preserve working Rails behavior and are not Rails bug fixes.

- Evidence: impl-fix-public-share-parity.report.md:91.

- Test files: `app-phoenix/test/dawarich_web/public_share_owner_test.exs`.

- CHANGELOG-ready: Show an unavailable-share response when a public month or digest owner has been deleted.

### FRB-054 — Retired API keys retain stale rate-limit classification

Retired API keys can retain their previous rate-limit plan classification for the two-minute cache TTL in Rails: `config/initializers/rack_attack.rb:53` caches the lookup, `app/controllers/settings_controller.rb:27` rotates the key, and `app/models/user.rb:58` only attaches cache invalidation to plan changes (`:498` deletes without a generation check). Phoenix now prevents a lookup already in flight at rotation from repopulating the deleted old-key cache entry using atomic pending-token replacement in `app-phoenix/lib/dawarich/ttl_cache.ex:16` and post-commit invalidation in `app-phoenix/lib/dawarich/auth/api_keys.ex:42`. Test: `rotation invalidation wins over an in-flight retired key plan lookup`. ED/DRB row added: no; the explicit Phoenix immediate-invalidation requirement already applies, and the controller owns the aggregate Rails-bug registry. This is stale rate-limit classification, not an authentication bypass. The Rails source is unchanged. The deterministic delayed-fill reproduction and mutation exercise Phoenix; no claim is made of a new Rails concurrency reproduction.

- Evidence: impl-fix-savepoint-mode.report.md:71.

- Test files: `app-phoenix/test/dawarich_web/standalone_api_key_flow_test.exs`.

- CHANGELOG-ready: Prevent an in-flight lookup from restoring a retired API key’s cached rate-limit plan.

### FRB-055 — Forged forwarding headers override an untrusted direct peer

Rails accepts a forged X-Forwarded-For from a directly connected untrusted
  public peer as request identity, enabling false Trackable attribution and
  fresh IP-based rate-limit buckets. Phoenix now uses the socket address for
  untrusted peers and considers identity headers only behind trusted peers.
  Rails source: installed ActionPack 8.1.3.1
  `lib/action_dispatch/middleware/remote_ip.rb:129–169` (especially :169),
  repository configuration `config/application.rb:15` (default RemoteIp),
  rate-budget use `config/initializers/rack_attack.rb:243–248`.
  Phoenix source: `app-phoenix/lib/dawarich_web/rails_remote_ip.ex:19–21`.
  Test: `forged forwarding headers from an untrusted peer cannot change sign in identity`.
  ED/DRB row added: no; proposed expected-diff documented in
  docs/phoenix/proxy-admission.md for the matrix owner. DRB-036 is not closed,
  because its trusted-peer pass-through envelope is still preserved.

- Evidence: impl-fix-proxy-admission.report.md:179.

- Test files: `app-phoenix/test/dawarich/auth/auth_handler_test.exs`.

- CHANGELOG-ready: Use the socket identity for untrusted direct clients so forged forwarding headers cannot reset IP limits or sign-in attribution.

### FRB-056 — Dominant transportation mode changes on an exact tie

Dominant mode changes between Driving/Walking on an exact tie depending on scan plan. Phoenix orders segment input by ID via the existing loader. Rails `app/services/tracks/segment_editor.rb:56`, `app/models/track.rb:255,261–276`; Phoenix `app-phoenix/lib/dawarich/tracks/segment_editor.ex:140`, `transportation/segments.ex:263`. Test: `exact dominant mode ties keep ID order under sequential and index scans`. Added DRB-033 and ED-FIX-TIE-ORDER.

- Evidence: impl-fix-segment-tie-order.report.md:91.

- Test files: `app-phoenix/test/dawarich/tracks/segment_editor_test.exs`.

- CHANGELOG-ready: Choose a stable dominant transportation mode when segment distances or durations tie.

### FRB-057 — Tied visit rankings change top-five membership

Top-five visit membership/order changes on equal count and duration. Phoenix appends a C-collated name key before LIMIT in all corresponding queries. Rails `app/controllers/insights_controller.rb:176–179`, `app/controllers/api/v1/insights_controller.rb:94–97`; Phoenix `app-phoenix/lib/dawarich/insights/details.ex:123`, `stats/insights.ex:17`, `stats/api_closure.ex:225`. Test: `top visited exact ties use name order before applying the limit`; existing strict refusal remains. Added DRB-034 and ED-FIX-TIE-ORDER.

- Evidence: impl-fix-segment-tie-order.report.md:91.

- Test files: `app-phoenix/test/dawarich/tie_order_test.exs`.

- CHANGELOG-ready: Keep tied top-visited-place rankings and their top-five cutoff stable.

### FRB-058 — Tied country rankings depend on aggregation order

Digest equal country-minute rankings can depend on grouped-row order. Phoenix appends C-collated country after existing minimum-time/date keys. Rails `app/services/users/digests/calculate_year.rb:164,191`; Phoenix `app-phoenix/lib/dawarich/digests/location_time.ex:16`. Test: `country count and duration ties use country order`. Added DRB-034 and ED-FIX-TIE-ORDER.

Same-day country-count ties can choose whichever group is encountered first; equal-day country rankings inherit that enumeration. Phoenix fixes within-date country order, keeping first-visit chronology and strict refusal behavior. Rails `app/services/residency/day_counter.rb:110,133`; Phoenix `app-phoenix/lib/dawarich/residency.ex:13`. Test: `country count and duration ties use country order`; the usual sorted aggregation already happened to satisfy the daily assertion in the RED run, so this final key is preventive ordering rather than a separately reproduced daily wrong winner. Added DRB-034 and ED-FIX-TIE-ORDER.

- Evidence: impl-fix-segment-tie-order.report.md:91.

- Test files: `app-phoenix/test/dawarich/tie_order_test.exs`.

- CHANGELOG-ready: Keep tied digest and residency country rankings stable.

### FRB-059 — Tied location points change representative coordinates

Location search equal-timestamp/accuracy points can choose different representative coordinates. Phoenix orders timestamp+ID before stable sorting/minimum-accuracy selection. Rails `app/services/location_search/spatial_matcher.rb:49`, `result_aggregator.rb:14,60`; Phoenix `app-phoenix/lib/dawarich/locations.ex:27`, `locations/closure.ex:104`. Test: `location equal timestamps and accuracy keep point ID order`. Added DRB-035 and ED-FIX-TIE-ORDER.

- Evidence: impl-fix-segment-tie-order.report.md:91.

- Test files: `app-phoenix/test/dawarich/tie_order_test.exs`.

- CHANGELOG-ready: Choose consistent location-search coordinates when point timestamps and accuracy tie.

### FRB-060 — Tied photo-scan points change nearest coordinates

Immich scan equal-timestamp rows can choose different nearest coordinates. Phoenix appends ID and preserves last-before/first-after rules. Rails `app/services/immich/enrich_scan.rb:68,81,108`; Phoenix `app-phoenix/lib/dawarich/photos/enrichment.ex:73,199`. Test: `photo scan equal timestamps keep point ID order across query plans`. Added DRB-035 and ED-FIX-TIE-ORDER.



- Evidence: impl-fix-segment-tie-order.report.md:91.

- Test files: `app-phoenix/test/dawarich_web/api/locations_photos_endpoint_test.exs`.

- CHANGELOG-ready: Choose consistent photo-enrichment coordinates when GPS timestamps tie.

### FRB-061 — RFC Forwarded headers bypass an ingress-written client identity

Rails symptom: an XFF-writing ingress that passes client-supplied RFC Forwarded allows fresh shared-unlock/OAuth challenge rate-limit buckets and misattributes sign-in tracking. Phoenix now ignores Forwarded/X-Real-IP for all client identity and shares XFF/Client-IP selection across limiters/auth tracking. Rails sources: `config/initializers/rack_attack.rb:243-248,323-325`; installed `actionpack-8.1.3.1/lib/action_dispatch/middleware/remote_ip.rb:137` inherits `rack-3.2.7/lib/rack/request.rb:358-365`. Phoenix: `app-phoenix/lib/dawarich_web/rails_remote_ip.ex:19-37`, `rate_limit/request.ex:93`. Named tests: both tests in the TDD table, especially the real Endpoint rotating-header regression. ED/DRB row added: **no**, no assigned plan/ledger edit authorization. Repository auth documentation records the explicit security deviation. Rails itself remains unchanged; this is a defect fixed in the port.

- Test: “rotating Forwarded XFF prefixes and X-Real-IP cannot evade unlock or OAuth challenge limits in either mode”.
- Boundary: trusted-ingress XFF/Client-IP pass-through remains preserved (DRB-036); this entry does not tighten that separate policy.

- Evidence: fix2-fix-trial-welcome.report.md:84.

- Test files: `app-phoenix/test/dawarich_web/trial_welcome_endpoint_test.exs`.

- CHANGELOG-ready: Keep untrusted Forwarded and X-Real-IP headers from changing IP limits or sign-in attribution.

### FRB-062 — Malformed forwarding headers bypass IP-only limits

Rails symptom: malformed XFF can make Rack::Request#ip nil, skipping IP-only limits or charging shared unlocks to an empty IP discriminator. Routing all Phoenix limits through the shared ActionDispatch-style selector now discards malformed/masked entries and falls back to the actual peer instead of nil. Rails sources: `config/initializers/rack_attack.rb:140,161,325`; installed `rack-3.2.7/lib/rack/request.rb:419-441` (ip/forwarded selection). Phoenix: `app-phoenix/lib/dawarich_web/rails_remote_ip.ex:25-37`, `rate_limit/request.ex:93`. Test: named client-identity matrix plus existing historical rate-limit corpus replay's malformed-XFF envelopes. ED/DRB row added: **no**, no assigned ledger edit authorization. Rails itself remains unchanged.



- Test: “client identity uses only XFF and Client-IP with Rails proxy filtering spoof checks and configured proxy replacement”.
- Boundary: trusted-ingress XFF/Client-IP pass-through remains preserved (DRB-036); this entry does not tighten that separate policy.

- Evidence: fix2-fix-trial-welcome.report.md:84.

- Test files: `app-phoenix/test/dawarich_web/rails_remote_ip_test.exs`.

- CHANGELOG-ready: Fall back to the socket identity for malformed forwarding headers instead of skipping IP-only limits.

### FRB-063 — Visit cache invalidation failure is swallowed

Rails source: `app/models/visit.rb:22`, `:149`, `:162` (after_commit deletion
  rescues failure); demo equivalent `app/services/demo_data/importer.rb:48` and
  `app/services/demo_data/destroyer.rb:34`. Phoenix now publishes transactionally
  and retries cache exceptions/exits until success: `app-phoenix/lib/dawarich/visits/calendar.ex:8`,
  `app-phoenix/lib/dawarich/points/visit_months_worker.ex:7`, `:15`, `app-phoenix/lib/dawarich/demo_data/derivatives.ex:115`,
  `app-phoenix/lib/dawarich/demo_data/destroyer.ex:127`, `app-phoenix/lib/dawarich/user_data/restore/visits.ex:51` (all Phoenix paths
  below `app-phoenix/lib/dawarich/`). Tests: “month invalidation survives more than
  three failures with backoff and recovers automatically”, endpoint outage and
  named demo/restore insertion/deletion tests above. ED/DRB: existing scoped
  ED-FIX-VISITS-CACHE extended; shared controller-owned register reconciliation
  remains pending.

- Evidence: fix2-fix-visits-writes.report.md:160.

- Test file: `app-phoenix/test/dawarich_web/visit_writes_regression_test.exs`.

- CHANGELOG-ready: Retry calendar cache invalidation after a successful visit write instead of leaving old counts until expiry.

### FRB-064 — An in-flight visit cache fill resurrects stale aggregates

Rails source: `app/services/timeline/month_summary.rb:58`
  (formerly unguarded fetch at line 57), `app/models/visit.rb:158`. Phoenix-owned
  writes now commit a generation with SQL; coexisting Rails readers reject old
  fills: `app-phoenix/lib/dawarich/visits/cache_generation.ex:4`, `app-phoenix/lib/dawarich/visits/calendar.ex:11`,
  `app-phoenix/lib/dawarich/rails_cache.ex:6`; Rails reader `month_summary.rb:58`, generation reader
  `visit_cache_generation.rb:5`. Tests: “an old month snapshot filled after
  invalidation cannot resurrect stale day or aggregate counts”, “rebuilds when a
  generation commits during the cache fill” and the immediate-commit named test.
  ED/DRB: ED-FIX-VISITS-CACHE extended; shared register pending. This correction
  fences Phoenix-owned writes; it does not claim generation publication by all
  retained Rails-origin writers.

- Evidence: fix2-fix-visits-writes.report.md:160.

- Test files: `app-phoenix/test/dawarich_web/visit_writes_regression_test.exs`; `spec/services/timeline/month_summary_spec.rb`.

- CHANGELOG-ready: Prevent old in-flight calendar cache fills from overwriting counts after a committed visit change.

### FRB-065 — Bulk visit status updates omit cache invalidation

Rails source: `app/services/visits/bulk_update.rb:47`.
  Phoenix publishes actual RETURNING stamps: `app-phoenix/lib/dawarich/visits_api/bulk_update.ex:62`.
  Test: “API bulk status writes publish durable invalidation during cache outage”,
  plus interleaved count/orphan tests. ED/DRB: ED-FIX-VISITS-CACHE extended;
  controller shared register pending.

- Evidence: fix2-fix-visits-writes.report.md:160.

- Test files: `app-phoenix/test/dawarich/imports/destroy_worker_test.exs`; `app-phoenix/test/dawarich_web/api/family_writes_golden_test.exs`; `app-phoenix/test/dawarich_web/api/places_golden_test.exs`; `app-phoenix/test/dawarich_web/map_writes_parity_test.exs`; `app-phoenix/test/dawarich_web/visit_writes_regression_test.exs`.

- CHANGELOG-ready: Refresh calendar counts after bulk visit confirmation or decline, including during cache outages.

### FRB-066 — Area deletion removes another user's linked records

Rails destroys visits and notes by attachment alone, then nullifies those visits' points. Its queued orphan-place cleanup also ignores declined/soft-deleted primary references and deletes suggestion links without checking the visit owner. A database-valid cross-owner graph can therefore lose another account's records or references during the area deletion or its scheduled cleanup. This characterizes stored graph corruption; it does not assert that public creation endpoints permit it.

- Rails: `app/controllers/api/v1/areas_controller.rb:35`; `app/models/area.rb:9`; `app/models/visit.rb:11-12`; `app/models/concerns/notable.rb:7`; `app/services/places/delete_if_orphan.rb:19,25-27`; batch `app/jobs/places/orphan_cleanup_job.rb:44-46,62-64`.
- Phoenix: `app-phoenix/lib/dawarich/areas/api.ex:111`; `app-phoenix/lib/dawarich/areas/cleanup_scope.ex:4`; `app-phoenix/lib/dawarich/places/orphans.ex:30,40,58,91`; `app-phoenix/lib/dawarich/places/orphan_cleanup_worker.ex:66`.
- Behavior: lock the owned area/visits, reject foreign immediate dependents before modifying the graph, and constrain every dependent mutation to the area owner. Refusal returns 422 with `{"error":"Area has foreign dependents"}` and preserves all rows, references and jobs. Shared individual and batch orphan cleanup retains a place referenced by any user's visit, regardless of status/deleted_at, or by any suggestion link. Cleanup deletes only owned unreferenced places; it never detaches visits or deletes suggestion links. Eligibility is rechecked after the owned place lock.
- Modes: standalone API and every native producer of the shared cleanup workers, including imports, visit writes, CLI cleanup and residual jobs. Coexistence effects retained by Rails still have the source defect.
- Evidence: fix2-fix-sa-api-gaps.report.md (immediate F2); fix3-fix-sa-api-gaps.report.md (queued F2 follow-up). Rolled-back Rails oracles reproduce both immediate deletion and queued cleanup losses.
- Tests: “owned area deletion refuses every foreign dependent before changing the graph” in `app-phoenix/test/dawarich_web/standalone_api_review_test.exs`; three “queued area cleanup preserves foreign shared place attachments” cases in `standalone_area_cleanup_test.exs`; “batch cleanup retains every visit status and foreign suggestion link” in `app-phoenix/test/dawarich/places/orphan_cleanup_worker_test.exs`; “deletes only unreferenced owned suggested orphans and preserves hidden references” in `orphans_test.exs`.
- Ledger: FRB-066 extended; ED-FIX-ORPHAN-REFERENCES added; no additional DRB row.
- CHANGELOG-ready: Preserve other accounts' records and all visit references through area deletion and scheduled orphan-place cleanup.


### FRB-067 — Account deletion changes another account's dependent records

Rails removes suggestion links and clears visits by the deleted user's place IDs without checking the visit owner. Its trip, tag and family cleanup can also remove foreign notes, shares and associations or clear another trip's reservation day in a database-valid cross-owner graph. The probes characterize existing stored graphs; they do not claim public creation endpoints accept every such graph.

- Rails: `app/services/users/destroy.rb:57,63,67,70,83,96`; `app/models/trip.rb:19`; `app/models/concerns/notable.rb:7`; `app/models/planned_day.rb:7`.
- Phoenix: `app-phoenix/lib/dawarich/users/destroy_effects.ex:124,132,163,169,179,194,211,223`; `app-phoenix/lib/dawarich/users/destroy_scope.ex:8,13,15,18,20,22`; shared `app-phoenix/lib/dawarich/places/orphans.ex:16`.
- Behavior: constrain dependent cleanup to the deleted account. Reject foreign notes, trip shares, reservation day links, tag targets and family dependents before purge/cache/webhook intents. Account place cleanup calls the shared locked orphan batch with all source/note types eligible, retaining its complete reference checks. A remaining referenced place cancels and rolls back the entire worker transaction, including rows, receipts and effect intents. It never rewrites another user's visit or removes their suggestion link.
- Modes: native worker; standalone bindings activate it. Retained Rails-owned cleanup remains unchanged. Cloud lifecycle refusal remains in every mode pending L1.
- Tests: “deleting a family member preserves another user's shared-place visit”, “account deletion refuses foreign dependent associations before cleanup” and “account cleanup preserves another user's reservation day” in `app-phoenix/test/dawarich/users/standalone_deletion_test.exs`; each has RED, GREEN, named mutation failure and restored GREEN evidence.
- Evidence: `fix2-fix-sa-account-deletion.report.md`; local Rails transactional oracles reproduce every destructive projection without retaining their synthetic rows. Integrated as `fc3f1fd87`.
- Ledger: ED-FIX-ACCOUNT-DEPENDENTS added; shared ED-FIX-ORPHAN-REFERENCES retained; no new DRB row.
- Limits: admission still schedules and marks the account deleted as before. Refused worker cleanup retains that account and all dependencies, emits no committed effects and records no processed receipt. Resolve foreign references explicitly before redelivering the worker; no reference reassignment or automatic retry escalation occurs.
- CHANGELOG-ready: Preserve other accounts' records and references when account deletion encounters shared places or foreign dependent associations.

## Deferred Rails defects and retained policies

The canonical [DRB register](deferred-rails-bugs.md) gives every row an explicit `preserved` or `fixed-in-port` status. `fixed-in-port` describes the native boundary; retained Rails consumers can remain defective. DRB-019 → FRB-018; DRB-023 → FRB-001; DRB-025 → FRB-002 (storage-first import/media cleanup); DRB-028 → FRB-015/038; DRB-029 → FRB-004; DRB-030–032 → FRB-011/012/014; DRB-033–035 → FRB-056–060; DRB-FIX-SWEEP6-RETRY → FRB-070; DRB-038/039 → FRB-068/069. DRB-018 is partly fixed by FRB-051 for settings containers while malformed non-string expiry remains preserved. All other DRBs remain preserved, including optional mobile nonce policy, signed bearer downloads, digest sent-marker ordering and trusted-ingress pass-through. FRB-075–077 concern calculation/publication state, not successful SMTP delivery or closure of DRB-013; broader rollback limitations remain deferred.

## Older ED candidates requiring provenance

These contrasts are present in the pinned ED register. They are kept visible here so earlier fixes are not silently lost, but their current fix provenance/activation is **unverified**. They have no confirmed FRB ID or release line until those fields and current behavior are checked. ED-382 point-deletion atomicity now has report-backed evidence in FRB-043; it is not counted twice. Named tests below identify existing evidence where available; they do not fill an unknown fix commit.

| ID / evidence | Reported symptom and native difference | Rails file:line | Phoenix fix commit / test | Deployment modes and limits |
| --- | --- | --- | --- | --- |
| ED-237 (former candidate 019) | A checksum-invalid disk upload can remove an existing object; native staging preserves it. | `Active Storage 8.1.3.1 lib/active_storage/service/disk_service.rb:21-26,207-212` | **unverified** commit; **unverified** exact test name | native disk uploads; Cloud/self-hosted matrix unverified. |
| ED-253 (former candidate 020) | Corrupt cross-account import dependents can be deleted; native deletion refuses them. | `app/services/imports/destroy.rb (line unverified)` | **unverified** commit; “foreign-user child linkage is refused before deleting or changing status” (`app-phoenix/test/dawarich/imports/destroy_worker_test.exs`); precise defect coverage unverified | native GPX deletion; some Rails forwarders also guard it. |
| ED-362 (former candidate 021) | A yearly digest failure leaves duplicate cleanup committed; native calculation rolls both writes back. | `unverified` | **unverified** commit; “failure rolls back digest writes and reports the original exception” (`app-phoenix/test/dawarich/digests/calculation_test.exs`); precise defect coverage unverified | native calculation; historical ED says inert until caller switches. |
| ED-382 (former candidate 022) | Point deletion commits before counters/follow-ups; native changes and intent are atomic. | `app/controllers/points_controller.rb (precise deletion line unverified)` | **unverified** commit; “points redirects counters and intent projection match Rails” (`app-phoenix/test/dawarich_web/map_writes_parity_test.exs`); precise defect coverage unverified | native map point deletion; activation proof unverified. |
| ED-274 (former candidate 023) | Family location-request creation partially commits before an email enqueue failure; native writes are atomic. | `app/services/families/create_location_request.rb (line unverified)` | **unverified** commit; “a failure after the first write rolls every table back and hands the request to Rails” (`app-phoenix/test/dawarich_web/api/family_writes_golden_test.exs`); precise defect coverage unverified | native family API; current legacy action reconciliation unverified. |
| ED-086 (former candidate 024) | An invitation-mail worker can run before its invitation commits and send nothing; native intent commits with invitation. | `unverified` | **unverified** commit; **unverified** exact test name | native invitation command ownership only. |
| ED-484 (former candidate 025) | Orphan cleanup can detach a newly committed active visit; native locked eligibility rechecks keep it. | `unverified` | **unverified** commit; “new active reference or FK conflict keeps the place and references intact” (`app-phoenix/test/dawarich/places/orphans_test.exs`); precise defect coverage unverified | native single-place and sweep owners; historical ED says disabled ownership. |
| ED-480 (former candidate 026) | Expired range state or repeat generation loses/repeats work; native durable ranges retain selected windows and receipts. | `unverified` | **unverified** commit; **unverified** exact test name | native range/generation owners; historical ED says disabled ownership. |
| ED-433 (former candidate 027) | Repeated successful recalculation jobs can repeat notices; native terminal effects settle per retained event. | `unverified` | **unverified** commit; **unverified** exact test name | accepted native recalculation; marker retention bounds deduplication. |
| ED-490 (former candidate 028) | Eviction of consumed trial-welcome claims permits replay; revised callers use durable claims. | `unverified` | **unverified** commit; “two real PG welcome contenders permit exactly one claim” (`app-phoenix/test/dawarich/trial/welcome_claim_test.exs`); precise defect coverage unverified | revised Rails/native authority; first switch permits one residual replay and needs Eugene activation review. |
| ED-491 (former candidate 029) | Losing registration cache resets admin policy to environment default; initialized native policy uses durable state. | `unverified` | **unverified** commit; “native registration reads copied false and stored nil without Redis” (`app-phoenix/test/dawarich/auth/registration_setting_test.exs`); precise defect coverage unverified | initialized native readers/writers after copy; source continuity and activation review required. |
| ED-405 (former candidate 030) | A delayed realtime setup survives disconnect/early toggle and can duplicate subscriptions; shared controller cancels it. | `unverified` | **unverified** commit; **unverified** exact test name | shared Rails/Phoenix browser controller; historical Rails baseline defect may already be repaired. |
| ED-185 (former candidate 031) | Raw geocoding responses are printed to stdout; native provider diagnostics omit response bodies. | `Freika geocoder fork (exact file/line unverified)` | **unverified** commit; **unverified** exact test name | native geocoding; current error-reporting policy/activation unverified. |
| ED-008 (former candidate 032) | A failed migration leaves an already enqueued job; native version ledger records intents atomically. | `data-migration/job enqueue call sites (exact files/lines unverified)` | **unverified** commit; **unverified** exact test name | native release migrator; nontransactional/version details need current proof. |
| ED-006 (former candidate 042) | Session lock-timeout changes can reach another client through transaction pooling; native migration refuses nonzero timeout. | `db/migrate/20260816120000* and 20260818201239* (exact filenames/lines unverified)` | **unverified** commit; **unverified** exact test name | native migrator; current pinned-connection reconciliation unverified. |
| ED-542 (former candidate 043) | Readable activity bytes with wrong checksum/size or empty content can be imported; native reader rejects them. | `Active Storage download and activity backfill caller (exact file/line unverified)` | **unverified** commit; **unverified** exact test name | native activity backfill; ED explicitly requires Eugene acceptance before ownership/lifecycle activation. |
| ED-135 (former candidate 044) | A long velocity string can be truncated by the Ruby float parser, changing its value; native parser reads the whole string. | `app/services/transportation_modes/feature_extractor.rb:37; Ruby strtod implementation (exact line unverified)` | **unverified** commit; **unverified** exact test name | native feature extraction; correction-versus-parser-difference ruling unverified. |

## Legacy section links

The following anchors preserve links to the earlier package supplements and grouped sections. Their evidence is consolidated into the final entries above.

<a id="report-backed-corrections-and-accepted-release-differences"></a>
<a id="older-ed-corrections-needing-release-reconciliation"></a>
<a id="proposed-rails-map-matching-branch-comparisons"></a>
<a id="provider-transport-corrections-merged-after-consolidation"></a>
<a id="import-storage-corrections-merged-after-consolidation-supplements-frb-003-to-frb-007-no-new-ids"></a>
<a id="import-and-storage-review-corrections--2026-10-07"></a>
<a id="import-deletion-authorization-follow-up--2026-10-07"></a>
<a id="native-import-deletion-revocation-across-cleanup-owners--2026-10-07"></a>
<a id="accepted-zip-children-and-terminal-parent-ordering"></a>
<a id="empty-successful-import-retries-repeat-no-points-notifications"></a>

## L1 package handoffs (2026-10-07)

The earlier integration snapshot above remains historical. Package F publishes B/D's demonstrated fixes from the integrated L1 preparation candidate; this does not enable public native Cloud lifecycle or certify remote delivery exactly once.

### FRB-068 — Signup callback failure leaves an orphan account

Rails can commit a new account and then fail its after_commit callback enqueue, leaving no durable creation intent. Native registration and provider account creation publish state and callback intents in the account transaction; publication failure rolls back the account.

- Rails: `app/models/user.rb:56`; `app/controllers/users/registrations_controller.rb:28`.
- Phoenix: `app-phoenix/lib/dawarich/auth/registration.ex:109`; `app-phoenix/lib/dawarich/auth/providers/accounts.ex:177`.
- Evidence: `impl-l1-b.report.md`, real Rails creation oracle; `app-phoenix/test/dawarich/auth/cloud_registration_test.exs`, “L1 registration callback failure cannot leave an account without durable creation intent”.
- Ledger: ED-553; DRB-038. Retained Rails behavior is unchanged. Local atomic publication is distinct from remote HTTP atomicity.
- CHANGELOG-ready: Roll back failed Cloud signups when durable account creation callbacks cannot be published.

### FRB-069 — Partnero error reporting exposes customer/provider details

Rails interpolates the raw rejection body and customer user ID into exception reporting. Native delivery retains retries and 2xx/409 acceptance while reporting only numeric status or sanitized transport class.

- Rails: `app/jobs/partnero/customer_signup_job.rb:42,44`.
- Phoenix: `app-phoenix/lib/dawarich/partnero/customer_signup.ex:87,88`; `app-phoenix/lib/dawarich/partnero/customer_signup_worker.ex:24`.
- Evidence: `impl-l1-d.report.md`; `app-phoenix/test/dawarich/partnero/cloud_signup_test.exs`, “L1 Partnero accepts 409 retries rejection and suppresses accepted-send replay”. The test checks log sanitation, retryable failures, customer-key replay and 409 acceptance.
- Ledger: ED-554; DRB-039. Retained Rails behavior is unchanged; live Partnero receiver acceptance remains external.
- CHANGELOG-ready: Keep Partnero customer data, response bodies and credentials out of signup failure diagnostics.

## Final merged delta (2026-10-07)

### FRB-070 — Queued reclassification retries start duplicate runs

Double-clicks or retries before a Rails worker starts enqueue duplicate full-user reclassifications, restarting progress and fan-out. Phoenix claims a durable per-user fence in the same transaction as root enqueue and releases it after fan-out completion.

- Rails: `app/controllers/tracks/recalculations_controller.rb:25`.
- Phoenix: `app-phoenix/lib/dawarich/tracks/web_recalculation.ex:18`; `app-phoenix/lib/dawarich/transportation/recalculation_fence.ex:4`; `app-phoenix/lib/dawarich/transportation/after_commit.ex:34`.
- Test: “review web queued retry produces exactly one event” in `app-phoenix/test/dawarich_web/standalone_recalculation_test.exs:222`.
- Evidence: `fix2-fix-sweep6.report.md`; integrated `59b7849e2`.
- Ledger: ED-FIX-SWEEP6-RETRY; DRB-FIX-SWEEP6-RETRY. Retained Rails producer remains unchanged.
- CHANGELOG-ready: Suppress duplicate queued full-user reclassifications before the worker starts.

### FRB-071 — An old OTP challenge survives a different account login

Rails can show another account's protected/2FA page while an earlier account's OTP challenge remains active, including through a remember credential. Phoenix clears all four OTP keys on full authentication and refuses active challenges before either credential strategy admits a protected page.

- Rails: `app/controllers/users/sessions_controller.rb:33`; `app/controllers/settings/two_factor_controller.rb:4`; Devise 5.0.4 `lib/devise/controllers/sign_in_out.rb:99`.
- Phoenix: `app-phoenix/lib/dawarich/auth/session_cookie.ex:19`; `app-phoenix/lib/dawarich_web/rails_auth.ex:63`.
- Tests: “F1 full login of actor B clears actor A's active OTP challenge” and “F1 active pending challenge refuses Warden and remember credentials at shared pages” in `app-phoenix/test/dawarich_web/standalone_auth_findings_test.exs:50,112`.
- Evidence: `fix2-fix-sa-auth-pages.report.md`; integrated `0fe8f1273`.
- Ledger: ED-FIX-SA-PENDING; no DRB added. Standalone admission correction; Rails remains unchanged.
- CHANGELOG-ready: Clear stale two-factor challenges on full login and refuse protected pages while a challenge is active.

### FRB-072 — Redirect-back accepts same-host non-HTTP schemes

Rails achievement sharing can return a supplied same-host `javascript://`, `data://`, `vbscript://` or `file://` URL in Location. Phoenix accepts only case-insensitive HTTP(S) absolute URLs or single-slash scheme-less relative paths after trimming, otherwise using the action fallback. This evidence establishes redirect admission, not browser execution.

- Rails: `app/controllers/achievements_controller.rb:45`; ActionPack 8.1.3.1 `lib/action_controller/metal/redirecting.rb:304`.
- Phoenix: `app-phoenix/lib/dawarich_web/rails_redirect.ex:14`.
- Test: “F1 signed standalone sharing rejects same-host non-HTTP schemes with the achievement fallback” in `app-phoenix/test/dawarich_web/achievement_sharing_test.exs:26`; helper scheme cases in `app-phoenix/test/dawarich_web/rails_redirect_test.exs`.
- Evidence: `fix4-fix-sa-trek.report.md`; integrated `afb162eaf`.
- Ledger: ED-FIX-SA-TREK-REFERER-SCHEME; no DRB added. Separate valid-userinfo/protocol-relative restrictions are accepted differences, not additional demonstrated Rails defects. Rails remains unchanged.
- CHANGELOG-ready: Reject non-HTTP redirect-back targets and use the action's safe fallback.

### FRB-073 — Stats redelivery repeats an accepted month calculation

Replaying a successful source stats event can repeat calculation and replace the accepted result after points change. Native calculation claims a durable scoped receipt atomically with the result; failed calculations remain retryable.

- Rails: `app/jobs/stats/calculating_job.rb:19`; `app/services/stats/commands.rb:25` (source dispatch seams cited by the implementation report).
- Phoenix: `app-phoenix/lib/dawarich/stats/calculate_month_worker.ex:49,53`.
- Test: “stable monthly stats event does not execute again on redelivery” in `app-phoenix/test/dawarich/fix_rxstats_test.exs:26`.
- Evidence: `impl-fix-rxstats.report.md`; integrated `31b4bbe9e`.
- Ledger: no ED/DRB row added; shared period-state contract in [stats-native-effects](stats-native-effects.md). Stable accepted event identity is distinct from a fresh recalculation request.
- CHANGELOG-ready: Keep an accepted monthly statistics calculation from running again on redelivery.

### FRB-074 — Ownership flips admit one stable event into both runtimes

Coexistence replay after a job ownership change can publish the same stable event to Rails and Phoenix. Native schedulers persist one destination-independent admission receipt atomically with the chosen Oban/outbox/reverse delivery; fresh events still use current ownership.

- Rails: `app/services/stats/commands.rb:49`; `app/services/users/digests/commands.rb:38`; `app/services/job_commands.rb:206` (source dispatch seams).
- Phoenix: `app-phoenix/lib/dawarich/stats/schedule.ex:24`; `app-phoenix/lib/dawarich/digests/schedule.ex:41`; `app-phoenix/lib/dawarich/stats/stats_full_recalculation_effects.ex:13`.
- Tests: “stable stats schedule stays in one runtime after ownership flip”, monthly/yearly/full counterparts in `app-phoenix/test/dawarich/fix_rxstats_test.exs:86`.
- Evidence: `impl-fix-rxstats.report.md`; integrated `31b4bbe9e`.
- Ledger: no ED/DRB row added; [stats-native-effects](stats-native-effects.md). This suppresses replay, not a pending-work transfer or remote exactly-once delivery guarantee.
- CHANGELOG-ready: Admit each stable statistics or digest event once across Rails/Phoenix ownership changes.

### FRB-075 — Digest publication retry repeats successful generation

Rails publication failure can rerun successful digest generation and its monthly calculations (twelve for a yearly digest). Phoenix and the updated coexistence Rails bridge checkpoint generated output independently, retry publication only and retain the source failure notification.

- Rails: `app/jobs/users/digests/monthly/calculating_job.rb:19,20`; `app/jobs/users/digests/yearly/calculating_job.rb:19,20` (pre-fix boundary); shared fix `app/services/users/digests/execution.rb:35`.
- Phoenix: `app-phoenix/lib/dawarich/digests/generation.ex:14,75,84`.
- Tests: “monthly generation does not recalculate after terminal rollback” and yearly counterpart in `app-phoenix/test/dawarich/fix_rxstats_test.exs:139`; RX12 monthly/yearly publication rollback and RX18 cross-runtime continuation in `app-phoenix/test/dawarich/fix4_rxstats_test.exs:59,135`; “RX16 month Rails publication failure preserves generation for retry” and year counterpart in `spec/jobs/users/digests/period_execution_spec.rb:38`.
- Evidence: `impl-fix-rxstats.report.md`; `fix4-fix-rxstats.report.md`; integrated `31b4bbe9e`.
- Ledger: no ED/DRB row added; [stats-native-effects](stats-native-effects.md). DRB-013's enqueue-before-sent-marker behavior remains preserved; this checkpoint is not an SMTP delivery receipt.
- CHANGELOG-ready: Reuse generated monthly and yearly digests when mail publication needs a retry.

### FRB-076 — Separate job IDs repeat one completed digest period

Distinct accepted jobs for the same user/period can repeat calculations and admit duplicate mail work. Native and coexistence Rails consumers share one period-state record, preserving generated/published state across job IDs and runtime changes.

- Rails: `app/jobs/users/digests/monthly/calculating_job.rb:7`; `app/jobs/users/digests/yearly/calculating_job.rb:7` (source flow); shared fix `app/services/users/digests/execution.rb:17`.
- Phoenix: `app-phoenix/lib/dawarich/digests/execution.ex:7`; `app-phoenix/lib/dawarich/digests/generation.ex:14`.
- Tests: “RX10 monthly native resumes published from the single period record” and yearly counterpart in `app-phoenix/test/dawarich/fix4_rxstats_test.exs:18`; “RX15 month Rails resumes published from the single period record” and year counterpart in `spec/jobs/users/digests/period_execution_spec.rb:25`; real mixed-runtime collision in `spec/jobs/users/digests/period_boundaries_spec.rb`.
- Evidence: `fix4-fix-rxstats.report.md`; integrated `31b4bbe9e`.
- Ledger: no ED/DRB row added; [stats-native-effects](stats-native-effects.md). Rails without the additive period table retains its source flow; rollback is drain-first. DRB-013 remains preserved.
- CHANGELOG-ready: Reuse one digest calculation and publication state per account and period across accepted job IDs.

### FRB-077 — Rails bridge marks rolled-back digest publication complete

The port's coexistence Rails helper could swallow a publication-savepoint rollback, mark the period published and consume its receipt, permanently skipping missing mail on retry. It now requires a successful transaction return and raises a retryable IOError before advancing state; generated output remains reusable. This is an introduced bridge regression, not a Rails 1.15.3 defect or an observed production incident.

- Rails fix: `app/services/users/digests/execution.rb:40,49`.
- Phoenix: `app-phoenix/lib/dawarich/digests/generation.ex:84,106` already returns publication rollback as error; unchanged in this round.
- Tests: “RX43 month rollback at the existing publication savepoint preserves generated and remains retryable” and year counterpart in `spec/jobs/users/digests/publication_rollback_spec.rb:7`.
- Evidence: `fix6-fix-rxstats.report.md`; `rereview5-fix-rxstats.report.md`; integrated `31b4bbe9e`.
- Ledger: no ED/DRB row added. Broader outer-transaction retry signalling and synthetic calculator-return behavior remain controller-deferred; see [rollback limits](deferred-rails-bugs.md#digest-publication-and-rollback-limits). DRB-013 is unchanged.
- CHANGELOG-ready: Keep failed Rails/Phoenix coexistence digest publication retryable after a publication-savepoint rollback.

### FRB-078 — Failed deletion confirmation consumes the rate slot

Rails confirmation-mail enqueue failure rate-limits the account for an hour although no email was accepted. Phoenix releases its acquired slot on enqueue/token failure, allowing one successful retry.

- Rails: `app/services/users/request_account_destroy.rb:29,37`.
- Phoenix: `app-phoenix/lib/dawarich/auth/account_destroy.ex:156`.
- Test: “standalone confirmation mail failure releases its rate slot for one retry” in `app-phoenix/test/dawarich_web/standalone_account_deletion_test.exs:349`.
- Evidence: `impl-fix-sa-account-deletion.report.md`; integrated `fc3f1fd87`.
- Ledger: no ED/DRB row added. Standalone account-deletion admission; retained Rails remains unchanged.
- CHANGELOG-ready: Allow account deletion confirmation to be retried when its email could not be queued.

### FRB-079 — Account deletion drops failed statistics cache cleanup

Rails swallows Redis cleanup errors after account deletion, leaving stale statistics without retry. Native deletion commits durable AfterCommit cache intents with its SQL effects and retains failed eviction for idempotent retry.

- Rails: `app/services/users/destroy.rb:168,171`.
- Phoenix: `app-phoenix/lib/dawarich/users/destroy_effects.ex:40,45`.
- Test: “deletion commits purge and after-commit intents once and storage failure keeps its ledger” in `app-phoenix/test/dawarich/users/standalone_deletion_test.exs:300`.
- Evidence: `impl-fix-sa-account-deletion.report.md`; integrated `fc3f1fd87`.
- Ledger: no ED/DRB row added. Storage-first purge is the separate existing FRB-002, not counted here. Retained Rails remains unchanged.
- CHANGELOG-ready: Retry statistics cache cleanup after account deletion when Redis is unavailable.

### FRB-080 — Stale area lookups both proceed with deletion

Rails looks up an area before destroying it, allowing stale contenders to proceed with the same deletion. Standalone Phoenix locks the actor-scoped area inside the write transaction before inspecting its graph; a later lookup returns 404 after the winner commits.

- Rails: `app/controllers/api/v1/areas_controller.rb:43,35`.
- Phoenix: `app-phoenix/lib/dawarich/areas/api.ex:62,68,154`.
- Test: “standalone area deletion scopes records removes dependents and queues each effect once” in `app-phoenix/test/dawarich_web/standalone_api_gaps_test.exs:142` verifies repeated deletion and effect counts. The report adds no separate concurrent-race characterization; do not infer one.
- Evidence: `impl-fix-sa-api-gaps.report.md`; integrated `4370930c9`.
- Ledger: no ED/DRB row added. Distinct from FRB-052 response rollback and FRB-066 foreign-dependent protection; retained Rails remains unchanged.
- CHANGELOG-ready: Serialize standalone area deletion and avoid repeating cleanup for an already deleted area.

### FRB-081 — Plaintext Manager configuration exposes signed account data

Rails Manager callbacks accept plaintext transport for signed account/customer data. Phoenix refuses insecure origins during Cloud configuration/preflight and before transport, retaining TLS verification. The loopback test override is explicit and compiled out of production.

- Rails: `app/jobs/users/creation_webhook_job.rb:23,29`; `app/jobs/users/destruction_webhook_job.rb:25,31`.
- Phoenix: `app-phoenix/lib/dawarich/cloud/configuration.ex:33`; `app-phoenix/lib/dawarich/cloud/provider_http.ex:44`.
- Tests: “L1 hardening rejects plaintext Manager before any transport” and “L1 hardening loopback override is explicit and compiled out of production” in `app-phoenix/test/dawarich/cloud/hardening_test.exs:17,45`.
- Evidence: `impl-fix-l1-hardening.report.md`; integrated `fcf994223`.
- Ledger: ED-FIX-L1-HTTPS; no DRB added. Retained Rails remains unchanged; public native Cloud lifecycle is still refused pending external L1 handoff.
- CHANGELOG-ready: Require verified HTTPS for Manager account callbacks.

### FRB-082 — Missing Manager configuration silently loses callbacks

Blank/missing Manager or JWT settings let Rails skip callbacks or sign with an empty key. Phoenix refuses invalid Cloud boot/readiness/signup and delivery configuration, retaining creation/deletion callback work without delivery receipts for repair and retry.

- Rails: `app/jobs/users/creation_webhook_job.rb:7,21`; `app/jobs/users/destruction_webhook_job.rb:15,23`; `app/services/subscription/encode_jwt_token.rb:10`.
- Phoenix: `app-phoenix/lib/dawarich/cloud/configuration.ex:16`; `app-phoenix/lib/dawarich/users/webhook_commands.ex:32`; `app-phoenix/lib/dawarich/users/creation_webhook_worker.ex:23`; `app-phoenix/lib/dawarich/users/destruction_webhook_worker.ex:23`; `app-phoenix/config/runtime.exs:44`; `app-phoenix/lib/dawarich/readiness.ex:22`.
- Tests: “L1 hardening Cloud runtime boot and health refuse invalid config with safe operator messages”, “L1 hardening provisioning readiness and signup refuse missing Cloud config” and “L1 hardening Manager config failures retain both callback receipts for repair” in `app-phoenix/test/dawarich/cloud/hardening_test.exs:98,161,191`.
- Evidence: `impl-fix-l1-hardening.report.md`; integrated `fcf994223`.
- Ledger: ED-FIX-L1-CONFIG; no DRB added. Configuration validation is not external L1 acceptance, public Cloud lifecycle activation or remote exactly-once delivery. Retained Rails remains unchanged.
- CHANGELOG-ready: Refuse incomplete Cloud callback configuration and retain undelivered work for repair.

### FRB-083 — Missing Partnero credentials discard attributed signup work

Rails silently skips an attributed Partnero signup when credentials are missing. Phoenix keeps Partnero optional at boot but refuses attributed delivery without credentials, retaining retryable work without a delivery receipt.

- Rails: `app/jobs/partnero/customer_signup_job.rb:29`.
- Phoenix: `app-phoenix/lib/dawarich/partnero/customer_signup.ex:34`.
- Test: “L1 hardening missing Partnero credentials retain attributed work without making Partnero mandatory” in `app-phoenix/test/dawarich/cloud/hardening_test.exs:227`.
- Evidence: `impl-fix-l1-hardening.report.md`; integrated `fcf994223`.
- Ledger: ED-FIX-L1-PARTNERO; no DRB added. Distinct from FRB-069 diagnostic privacy; retained Rails remains unchanged.
- CHANGELOG-ready: Retain attributed Partnero signup work for retry when integration credentials are missing.

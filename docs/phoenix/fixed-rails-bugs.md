# Rails bugs fixed in the Phoenix port

This ledger records intentional security and replay corrections under controller ruling 17. Repository code is authoritative; the corresponding AFFiNE index is **Dawarich — Phoenix imports HTTP and producer closure** (`OICwyQJkkxfUDp6macMX9`). Decision history: **Dawarich — ADR-20261007-import-upload-authority — Bind uploads and publication to server authority** (`AZZxsnuu4dzBRMf4Bi7_X`). Other packages' changelogs remain controller reconciliation work.

## Import and storage review corrections — 2026-10-07

| Finding | Rails-visible symptom and source evidence | Phoenix correction | Regression |
| --- | --- | --- | --- |
| F1: upload ownership | `app/controllers/imports_controller.rb:158` resolves a global signed blob and attaches it to `current_user` at line 164. Active Storage direct upload creation records no creator. A second authenticated user possessing an unattached signed reference can claim its bytes. | Native direct uploads create a server-owned `phoenix.upload_receipts` row in the blob transaction. Signed-reference import and user-data intake require the creating actor; import attachment rechecks ownership under the blob lock. CSRF-protected guest uploads retain the Rails wire protocol with ownerless receipts, which authenticated intake cannot claim. Historical uploads without a receipt are refused. Server-generated backup exports can be reimported only by their owning user, using the persisted Export attachment. Client metadata cannot establish ownership. | `another user cannot claim an upload created in the victim session` |
| F2: delayed capability revocation | `app/models/import.rb:197` calls `purge_later`; `app/services/imports/prepared_download_purge_commands.rb:33` schedules cleanup. Blob redirects can continue resolving before delayed purge completes. | Every native-initiated deletion revokes unshared application capabilities in its transaction, independent of physical cleanup ownership. Oban cleanup jobs retain service/key after removing blob rows; Sidekiq cleanup retains marked blob rows and immutable authorization receipts for the existing Rails handler. Prepared caches and other owned derived attachments join the complete locked snapshot. Source-initiated Rails destruction retains the DRB-029 delayed behavior. Already issued external S3 URLs remain subject to object deletion and expiry. | `deleting an import revokes its prepared blob capability immediately` |
| F3: legacy extraction replay | `app/jobs/enhanced_import/extract_job.rb:43` defaults `expected` to nil; its ordinary legacy path runs without a completed-event receipt. Replay can repeat extraction/card/track effects. The typed Phoenix-to-Rails path already checks accepted identity (`app/services/imports/extraction_commands.rb:41`) and is not the dropped-fence defect. | Native GPX jobs retain actor/source/blob/event/request timestamp. Import leases and executing-attempt checks fence each place write and state/effect transaction. Terminal effects and the processed event commit together, making replay inert. | `the same completed extraction event does not execute its effects twice through dispatch` |
| F3: stale legacy removal | `app/jobs/enhanced_import/destroy_job.rb:7` defaults `expected` to nil; `app/services/enhanced_import/destroy.rb:15` operates on current extracted data. An old ordinary legacy removal can remove newer extraction data. Accepted typed Rails removal already uses the request fence. | The retained native GPX removal worker checks the same request identity before each bounded deletion and reset; completed removal replay preserves newer data. Reduced legacy payloads cannot execute against an import carrying a typed manual request. | `a retried old removal cannot delete a newer extraction through dispatch` |
| F4: purged disk object resurrection | Active Storage 8.1.3.1 `app/controllers/active_storage/disk_controller.rb:24` validates token/headers and calls disk upload without a blob-row lookup; `lib/active_storage/service/disk_service.rb:21` writes the key. A still-valid token can recreate a purged object. This is source evidence, not a claimed Rails HTTP replay experiment. | Native disk PUT stages and verifies bytes, then locks a live, unattached blob with a server upload receipt and matching service/size/checksum/type before publication. Purge and publication serialize on that row; revoked or attached receipts return 404. Purge removes the upload receipt. | `a successful purge cannot be undone with the old upload capability`; `purge between upload staging and publication prevents object resurrection` |

F5 fixes a Phoenix admission bypass rather than an inherited current Rails defect. Rails GPX uses `app/services/enhanced_import/adapters/base_adapter.rb:25` and `app/services/imports/file_loader.rb:36` to download through the attachment's stored service. Active Storage 8.1.3.1 `DiskService#path_for` at line 114 already refuses traversal. Enhanced Phoenix SourceFile now uses the shared Reader, retaining observed-size/checksum errors, fixed temporary destinations, bounded archive extraction and deadline cancellation. Regressions: `manual GPX extraction refuses a key outside the storage root` and `manual GPX extraction refuses a mismatched stored service`.

The initial F1–F5 correction added no shared ED/DRB row; the deletion follow-up adds DRB-029. This ledger is the ruling-17 handoff. Allocation names, ports and paths are deliberately absent.

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

## Import deletion authorization follow-up — 2026-10-07

Distinct original and prepared blobs are a valid native destruction layout. The
worker authenticates the intact attachment snapshot before entering destruction;
its removal transaction authorizes every blob before any revocation. Immediate
cleanup can no longer remove the original proof needed for the prepared blob.
Ambiguous original identities fail admission with unchanged points, status and
attachments. Shared attachments retain the existing protection. Cleanup jobs keep
service/key targets and retry physical failures after capability revocation.

This corrects a Phoenix ordering regression, not a Rails behavior change. The
real-worker matrix covers both modes, both stored cleanup owners, prepared-only
and distinct layouts, terminal replay, and durable native cleanup retry.
Source-initiated Rails delayed capability revocation is characterized separately
in DRB-029. Physical cleanup ownership does not exempt a native deletion.
Original Rails code remains unchanged.
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

## Native import deletion revocation across cleanup owners — 2026-10-07

The round-3 controller brief corrects DRB-029 for every native removal in both
modes. Previously, native destruction with Sidekiq cleanup kept prepared links
usable (302/200); native ZIP removal could also omit the prepared cleanup target.
The deletion transaction now marks unshared Sidekiq-bound blobs unavailable to
native redirects, disk downloads and uploads, removes upload receipts, and keeps
exact stored service/key rows plus actor/source purge receipts for Rails cleanup.
Native cleanup retains immutable service/key jobs. Shared objects are excluded.
External storage URLs still depend on physical deletion and expiry.

ZIP completion captures the complete parent attachment set and authorizes all
entries before detaching any of them. Its duplicate original cleanup publication
is authorized from that same intact snapshot, preserving the Rails enqueue
footprint without the Phoenix `Unowned purge attachment` regression. ZIP child
imports own their member files and survive parent removal; ordinary retained
Import attachment names are admitted by import/actor identity rather than name.

Regressions: `native destruction revokes issued links before either cleanup owner
runs` and `native ZIP removal authorizes every owned attachment before revoking`,
each parameterized across coexistence/standalone and both cleanup pins. The
latter also covers original-only and distinct prepared/derived layouts, point
removal, terminal phase, immutable cleanup targets and worker replay. Every
parameterized name has its own mutation run. Existing shared/foreign ownership
and download tests remain required neighbors. The ZIP crash is Phoenix-specific;
the delayed native-link fix is a documented divergence from original Rails.
DRB-029 is updated; no additional ED/DRB ID is introduced. Rails code is unchanged.

# Keep imported data when removing an import's source file

- Status: Implemented locally for review; not released
- Date: 2026-10-28
- Issue: [#3531](https://github.com/Freika/dawarich/issues/3531)
- Base: `dev` at `13ec7af9e00b4e5a027584f19f58e7a4b73d779d`
- AFFiNE counterpart: [Dawarich — ADR-20261028-import-source-file-removal](https://affine.dwri.xyz/workspace/c309ded7-e11e-4e72-ba6f-aec8a31a740b/ePaAmZ_sIHxPhIyiGJyfe)

## Context

An Import owns points and references extracted visits, places and tracks. Destroying the Import deletes points and invokes extracted-data cleanup. Its uploaded `file` must therefore be removable independently. `prepared_download` can reference the same Active Storage blob as `file`, a separate unwrapped copy, or a blob still attached to another record.

Source readers include the main importer, enhanced extraction, download preparation, device-tag and activity backfill, and account backup export. Checking status only in the UI cannot prevent a reader starting while removal is underway.

## Decision and user behavior

The import detail page offers **Delete source file**, with a confirmation that explains both retention and lost capabilities. It immediately detaches `file` and `prepared_download` together in one transaction, keeps the Import and all data, and schedules unique blobs through `ActiveStorage::PurgeJob` after commit. Active Storage's attachment foreign keys protect blobs still referenced elsewhere. Shared blobs may therefore continue occupying storage until their last attachment is removed. Storage failures use the existing job retry mechanism.

`DELETE /imports/:id/source_file` is an authenticated, owner-only HTML action, authorized by `ImportPolicy#delete_source_file?`. A repeated request succeeds without enqueuing another purge. Busy or unsupported requests redirect with an explanation and leave attachments intact. This does not add an API v1 endpoint.

Removal is available for **completed and failed imports**, excluding `user_data_archive`, `immich_api` and `photoprism_api`, while neither enhanced extraction nor download preparation is queued or running. Even stale pending/running extraction blocks removal: a stale timestamp is not proof that its reader has stopped. Account restore archives use a separate job without a reliable completed-state handoff, so they remain unsupported by this action. API-generated Immich/PhotoPrism imports are excluded because their integration producers can replace an attachment on an existing record outside the normal upload lifecycle. Created, processing and deleting imports are also blocked.

After removal, download links and extraction/re-extraction controls disappear. A direct download request redirects with an explanation; queued processing, extraction and download preparation jobs skip an absent source. Existing extraction counts and the separate removal of extracted data remain available. Map/points views, editing the import metadata and deleting the whole import remain available. Both whole-import delete confirmations explicitly warn about points and extracted-data deletion and point users to source-only removal.

File-dependent backfills cannot recover source-only metadata after deletion. Already imported point metadata, tracker IDs, motion hints, derived tracks, places, visits and statistics remain intact. Account backups keep the import record with empty file metadata; restoring that backup does not recreate the deleted source.

## Concurrency and queue state

`Import#with_source_file_lock` uses the same per-import PostgreSQL session advisory lock for removal and every source read listed above. Readers reload their source under the lock. The main import lock begins **before** downloading/classifying the file and covers its processing and completion callbacks. The extraction claim takes this lock, reloads attachment availability, and retains its compare-and-swap status check. Jobs recheck availability after acquiring it. Removal, download requests and extraction claims use nonblocking acquisition so requests can report a busy source promptly.

Migration `20261028143000_add_download_preparation_pending_to_imports.rb` adds a boolean, default false. The download request claims it before enqueueing preparation, under the source lock; this closes the gap before a worker starts. The job clears it on success and ordinary failure. The existing one-minute download-request cache still deduplicates enqueueing and lets the polling page requeue a lost preparation job after expiry. The pending flag does not expire by time alone: elapsed time cannot prove that a worker stopped. If a worker is killed, revisit Download and let preparation finish before removing the source. The flag is excluded from account backup serialization and ignored on restore because a queue claim does not transfer between instances.

Detaching both attachments precedes deduplicated purge scheduling. Scheduling uses `ActiveRecord.after_all_transactions_commit`, so a rollback restores the attachments and does not delete storage. Session locks avoid a database write transaction around streaming large files. Standard deployments must migrate and restart web/worker processes together so readers use the same locking protocol.

## Alternatives and consequences

- Destroying the Import or calling its destruction service would remove points, violating the requested retention contract.
- Automatic source deletion would remove recovery/extraction capabilities without an explicit owner choice.
- UI-only disabling, status-only checks, or independent download/import locks leave start/read races.
- Purging the first attachment before detaching the second can leave a shared source/download blob behind. Purging storage synchronously can delay the request and cannot safely participate in a database rollback.
- Supporting account restore archives and generated photo imports would require separate lifecycle changes; this implementation intentionally keeps that outside #3531.

## Verification

Regression tests use synthetic uploads in an isolated PostGIS database, private Redis and worktree-local storage. They cover stable point IDs and extracted entity IDs, same/separate/shared blobs, background purge, rollback, repeat/stale requests, owner authorization, unavailable states, a running reader before status changes, backfill, missing-source actions, queue preparation state and seven supported locales.

Browser verification uses private localhost port 13531 with synthetic history at desktop and 390×844 mobile widths. Evidence and final command/results are recorded in `docs/import-source-file-verification.md`. No real user files, production data, SSH, push, PR publication or deployment are part of this change.

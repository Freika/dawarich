# Export and restore redelivery

Decision status: accepted by the scoped controller brief, 2026-10-07.

The controller-authorized post-hoc E corrections preserve Rails archive formats, bearer links, committed restore rows and existing ownership hand-back. No Rails production code or schema changes.

## Restore recovery

A source-8 native restore saves its original summary and attachment upload manifest in the existing `phoenix.import_runs.attachment_snapshot`, in the same fenced transaction as restored records and the success notification. The snapshot binds the input attachment and accepted event. Redelivery stages the saved uploads against the newly extracted archive and original storage keys, then completes anomaly filtering, point recount and the processed receipt. It does not recreate restored entities or the success notification. Uploads are idempotent writes to the same keys; this is exactly-once database finalization, not a promise of one physical write. Separate accepted import events keep their own summaries.

Named regression: `restore redelivery resumes committed attachments with exactly one success`. It changes a real executing Oban job to retryable after the first stored attachment, then redelivers attempt two. Both runtime modes preserve three points, one success notification, unchanged blob identities, all attachment bytes/checksums and one processed event.

## Export generations and purge

Attachment replacement renames the previous `file` attachment to `retired_file_<attachment id>`. Both backup and points exports retain every generation as an attachment until export deletion, so the existing deletion collector and Rails/native purge payloads include all generated blobs. Download/backup serialization continues selecting the current attachment named `file`.

Native purge keeps rows and durable object keys/services while marking eligible blobs with the reserved `phoenix_purge_pending` metadata. Native blob lookup and disk download reject pending purges; live signed URLs retain their existing bearer semantics. The direct-upload producer strips the reserved marker. Purge locks candidate blobs in ID order, rechecks the reachable variant graph, protects externally referenced nodes and their descendants, removes physical objects first, and only then removes rows. Storage failure rolls back row deletion while retaining the Oban target for retry; already removed objects are harmless on retry. Historical key-only purge arguments continue working. Rails-owned coexistence still receives `exports.purge` with every generation; its consumer remains unchanged.

Named regression: `backup and export redelivery purge every generation storage before rows`. Both runtime modes interrupt backup notification finalization, redeliver, retain two generations, delete, fail storage deletion, retry and repeat purge. It also checks points attachment replacement, shared blobs and a variant reference added after enqueue with a protected descendant. The existing signed-download deletion regression checks immediate native revocation and retry.

This worktree predates the shared `Storage.NativePurge` implementation described by the native-media-purge ADR. The minimal shared seam here uses the same reserved marker in `Storage.Blobs` and the disk endpoint. Integration should reconcile these lookup changes and the exports worker with that collector, preserving the named tests and legacy arguments.

## Durable tile invalidation

Restore uses `RailsEffects.tile_epoch` for accepted point writes in both modes. That existing API queues a native TileEpochWorker under native ownership/standalone, or a durable Rails command under Rails ownership. Duplicate suppression no longer loses the intent when the cache client is unavailable. The native worker raises on cache error and Oban retries it.

Named regression: `restore cache outage retains durable invalidation through duplicate replay`. It stops only the test-owned cache client, inserts a synthetic point, replays the duplicate, checks the durable intent and worker failure, restarts the client, executes the intent and checks the changed year token. It covers native and Rails ownership in coexistence plus standalone.

## Source differences and policy

- ED-FIX-EXPORTS-TILE: the brief explicitly repairs Rails' best-effort restore invalidation weakness; DRB-028 records the Rails defect and native correction.
- ED-FIX-EXPORTS-PURGE: native purge retains blob/variant rows until physical deletion succeeds. Rails ActiveStorage `blob.rb:335–338` deletes the row before the file, so a storage failure can strand its original serialized purge target. The retained Rails consumer is unchanged (shared register DRB-025).
- Restore and export generation recovery are native accepted-event protocol corrections; ordinary Rails transaction boundaries and archive behavior remain characterized by existing tests.
- DRB-027 preserves signed export bearer links and is marked **needs Eugene policy decision**. Guest/foreign-user access to a live valid signed URL is intentionally unchanged.

The implementation report contains RED/GREEN/mutation evidence and the full seed-404 gate. Runtime allocations belong only in that report, never in code or this document.

## Alternatives and consequences

Replaying the whole restore loses pending attachments because existing entities are skipped, and repeats the success notification. Rolling back already committed restored rows changes the characterized Rails boundary. A new recovery table is unnecessary: the existing event-bound import-run snapshot can hold the manifest and original summary. Uploads may repeat, but target the same storage keys.

Replacing an export attachment and forgetting its previous blob leaves an untracked signed target. Retaining named historical attachments makes the existing deletion collector complete without a migration. Completing an already accepted archive could avoid extra generations, but requires a durable notification summary for the earlier archive; retention instead preserves current regeneration and exact summary behavior. Historical blobs are removed when the export is deleted, and references continue to protect shared objects.

Immediate blob-row deletion revokes links but loses database targets before storage succeeds. The reserved lifecycle marker separates native access revocation from physical cleanup while the existing Oban payload keeps retry targets. Background blob locks span storage I/O; deletion cannot roll back, so retries must accept already missing objects. Existing Rails-owned purge consumption remains the source-compatible hand-back.

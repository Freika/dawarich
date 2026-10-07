# Native import side effects

Implements A12f-3b plan D R08–R11 under the standalone priority ruling. The implementation uses existing import leases, actor/source snapshots, executing-job checks, ownership rows, processed-command receipts, and native workers. It adds no reverse-row poller and no public route or command registry entries.

With `DAWARICH_RAILS=off`, import producers and import lease checks select native execution without rewriting stored ownership pins. The shared `import:<id>` lease still refuses foreign work. Coexistence reads the stored owner. The small `UserData.ImportCommands` ownership substitution also covers archive uploads and normal-parser archive discovery; the archive worker retains its existing import lease.

Uploads keep native GPX/normal/archive routing. Download preparation keeps captured source identity and throttling. Standalone detached-blob purge removes authorized attachments and unshared blob/variant rows in the transaction that queues a native storage-delete job. Blob-ID capabilities stop resolving immediately. The job retains keys and service names for retries, including when configuration or storage is unavailable. Shared objects remain. Externally issued S3 capabilities remain governed by physical object deletion and expiry. Coexistence retains its existing authorized purge command/worker path.

Postprocessing schedules existing native month-stat, achievement, visit-suggestion, extraction, track-range, and point-counter workers. Child identities remain stable across replay. Achievement checks coalesce pending native jobs and retain the earliest invalidation timestamp, with the source's one-minute delay. Visit suggestions retain calendar stepping, captured zone, settings, and plan restrictions. Native completion progress uses the existing imports PubSub stream; the Rails progress renderer remains in coexistence.

Manual removal with extracted children uses a native worker carrying actor, source, blob, and extraction-event identity. It checks the executing attempt and current import before every bounded deletion transaction. It reuses `DestroyExtraction` for visits, tracks, orphan places, source-segment reset, reclassification callbacks, and extraction reset. Raw points and the import survive. Removal exceptions settle the matching request to failed with the Rails error prefix before re-raising. Both the same failed request and an immediate replacement request can retry; obsolete attempts and replaced request identities still refuse. Unsupported standalone manual extraction formats return a native error; unsupported completion extraction records a failed extraction state. Unsupported legacy parser handbacks return a native retryable error while retaining their original input and event lineage.

Native deletion callbacks schedule actor-scoped place cleanup and track reclassification. Deletion stores affected months before removing points, then schedules affected/current/stat-record months and achievement invalidation. Status and completion notify the existing native imports stream under the destruction fence. A removed import can finish native terminal effects using the original actor/event/job proof. Coexistence source-owned callbacks and handbacks remain.

## Integration handoff

HOT owns final registry, routing, and reverse-kind readiness. Existing roots already have registry entries; the new purge and extraction-removal jobs are direct native children. Do not remove retained source kinds or accepted-work handlers as part of this package.

Shared-file edits are confined to import callback/publication behavior in `imports/destroy_effects.ex`. The point tile-epoch and visit-month publication bodies remain sibling-owned. `imports/destroy_extraction.ex` exposes only a local extraction-fence seam; full import deletion keeps its existing fence. The one-line `user_data/import_commands.ex` ownership seam must be reconciled with that module's sibling owner.

Point/tile effects, track broadcasts, visit-month invalidation, enhanced-import-card publication, and untracked-track scheduling belong to their existing owners. This package does not claim global reverse-queue closure, release acceptance, source removal, deployment, or shutdown readiness. Retained broad accepted extraction envelopes continue through their existing workers and refusal contracts.

## Verification

The task files `a12f3b_r08_test.exs` through `a12f3b_r11_test.exs` cover the real producers, local storage, native jobs, subscribers, replay, source-owned coexistence, foreign leases, obsolete attempts, retained tracks, and earliest achievement invalidation. Each named selector has missing-behavior RED, GREEN, its publication mutation failure, and restored GREEN evidence in the controller implementation report. Retained Rails characterization and the seed-404 suite remain the package gates.

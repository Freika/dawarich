# Native media effects

With `DAWARICH_RAILS=off`, poster creation, progress and deletion, route-video
attachment cleanup and live-share revocation complete without a Rails reverse
consumer. A retained Rails ownership pin does not send these new media effects
to an absent Rails process. Existing foreign poster-generation leases remain
fenced; this does not take over another runtime's active lease.

Poster creation uses the existing `posters.create` outbox command and native
`Posters.CreateWorker`. Pending creation replay is deduplicated by poster ID;
finished or failed posters are not scheduled again. Progress uses the existing
native progress worker and current poster-card rendering. Live-share revocation
already broadcasts the native revoked payload and keeps its existing behavior.

Native poster deletion and native route-video rejection, deletion and
retention detachments reuse `Exports.PurgeWorker` as the existing storage purge
consumer. The producer transaction removes unreferenced blob and variant rows
and stores object keys and service names in the Oban job. Blob redirects and
previously issued native local disk URLs become inaccessible immediately in
standalone mode. Physical object deletion retries using the retained keys even
though the blob rows are gone. Shared attachments protect their blobs. Already
issued S3 service URLs depend on physical object deletion or URL expiry.

Route-video cleanup checks the exact detached file identity and its current
owner before revocation. Its native selection uses the existing
`cron:route_videos_purge_job` ownership key, or standalone mode. Unidentified MP4
direct uploads are accepted under the existing size/content-type rules and
schedule `RouteVideos.AnalysisWorker` directly on the `route_videos` queue.
Analysis rechecks the owned attachment before reading and before updating blob
metadata, uses native storage identification and ffprobe metadata, and skips
missing or already analyzed blobs. Replay cannot restore a deleted blob.

During coexistence, Rails-owned poster creation/purge and route-video cleanup
retain their original reverse payloads. Rails-owned uploads needing storage
identification still follow the existing request fallback. Historical native
poster purge children retain their original protocol for already accepted jobs.
The blob-ID consumer also handles captured source poster continuations in
standalone mode. It locks and rechecks the blob's poster/attachment references,
deletes the stored object before removing rows, and commits variant child jobs
with the row removal. A storage error or missing service configuration leaves
the blob and variant references available for retry. Parent completion cannot
hide pending variant jobs from drain observation. This repairs the Rails
Active Storage destroy-before-delete orphaning defect (ED-A12F3B-E13-F1).
No reverse-row poller or queue disposition is introduced: historical reverse rows
still require the retained Rails consumer or explicit controller disposition.

No route or shared registry change is required for these direct native children;
the existing `posters`, `exports` and `route_videos` queues must run. Final route
mounting and ownership rollout remain with the HOT package. Verify the focused
contracts in `test/dawarich/a12f3b_r15_test.exs`, the poster producer test in
`test/dawarich_web/a12f3b_p03_test.exs`, and live revocation in
`test/dawarich_web/a12f3b_s07_test.exs` under `app-phoenix`.

Shared knowledge counterpart: AFFiNE document `YYVRDtILLJV323IdtCc8K`,
“Dawarich — Native media effects and standalone storage revocation”.

Storage-failure regression: `test/dawarich/a12f3b_e13_purge_retry_test.exs`
(`F1`). Poster and route-video durable-key consumers are covered by
`test/dawarich/a12f3b_r15_test.exs`; export deletion by
`test/dawarich_web/exports_delete_test.exs`.

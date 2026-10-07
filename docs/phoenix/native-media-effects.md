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

Native poster deletion, standalone export deletion and native route-video
rejection, failed-save cleanup, deletion and retention reuse
`Exports.PurgeWorker`. The producer retains blob/variant rows, stores durable
object keys/services and root blob IDs in Oban, and marks eligible blobs with
`phoenix_purge_pending` metadata. Native redirects, proxies, representations,
local disk downloads and upload tokens refuse marked blobs in standalone and
native-owned coexistence. Route-video attachment admission refuses them too;
direct-upload metadata cannot set the reserved marker. Repeated producers do
not duplicate pending purges. Already issued S3 URLs depend on physical deletion
or expiry; the marker is enforced by Phoenix, not the retained Rails server.

The background worker locks and rechecks current references, deletes every
eligible parent/variant storage object first, then removes their attachment,
variant and blob rows in the same transaction. A storage error or missing service
configuration retains all rows and durable retry targets. An already deleted
object is safe on retry after another object or the database fails. Shared
attachments protect their blobs, including shared variant children. Eligibility
is computed over the whole reachable variant graph: links from every eligible
parent in the same purge are removed together, so those links do not protect a
shared child. External references exclude their target and propagate protection
to its descendants until the eligible set is stable. The worker rechecks this
graph under blob locks before deleting any object. Accepted keys/services retain
every eligible descendant for retry and serialized replay. Historical
key/service-only jobs remain supported for objects whose rows were already
removed by the former producer. No schema migration is needed.

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
Rails-owned coexistence cleanup keeps the original `ActiveStorage::PurgeJob`.
Its storage failure destroys the retry blob and a serialized retry silently
returns with media still stored. The original Rails `blob.purge_later` job
reproduces this without a Phoenix hand-back: preserved under ruling 13 and
recorded as DRB-025. Native cleanup does not inherit it.
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

Shared ordering regression: `test/dawarich/a12f3b_e13_shared_purge_test.exs`
(`F2`) executes real parent/variant failures, repeated Oban retries, recovery
and serialized replay across all eleven shared producer/mode combinations.
Original Rails characterization:
`spec/services/active_storage/purge_retry_characterization_spec.rb` (`F3`),
covering the original job and all three hand-back handlers. F2 is recorded as
ED-A12F3B-E13-F2 in the expected-difference and fixed Rails bug registers;
Rails-owned coexistence remains deferred, not repaired.

Decision: [retain storage rows until deletion succeeds](native-media-purge-adr.md).

Shared-variant regression: `test/dawarich/a12f3b_e13_shared_variant_test.exs`
(`F4-standalone` and `F4-coexistence`) deletes a poster whose `image` and
`print_pdf` roots share one child, with a further descendant. Actual parent
storage failure, still-broken retry, recovery and serialized replay remove every
unreferenced object and row. A separate shared-child storage failure retains all
rows and drain debt until recovery. External-parent and post-enqueue attachment
references preserve both child and descendant. This repairs a Phoenix graph
collection defect; Rails-owned DRB-025 behavior remains as recorded.


## Media ownership repair — 2026-10-07

Route-video adoption refuses a signed blob attached to another owner's route
video, poster, import or export. Unknown attachment owners are refused. Blob
loading includes the owner predicate in coexistence and standalone; the attach
transaction first locks the blob and then repeats admission with a fresh query
snapshot. Committed purge revocation cannot be undone by an earlier admission.
Unattached uploads and same-owner reuse stay supported. Download bearer links
remain unchanged under the controller ruling; DRB-027 includes poster/video links.

Video analysis claims the accepted event and locks the owned blob before storage
reads or ffprobe. Concurrent same-event replay and different events for the same
blob run the expensive effect once after successful completion. Storage/probe
failures roll back the claim and permit retry. The background transaction holds
the blob lock across analysis; no schema migration or runtime lease expiry is
needed. This does not promise exactly-once across a process crash after ffprobe
but before the database commits; that unfinished attempt must retry.

Accepted Rails Posters::CreateJob now forwards to Oban with its original job ID
when the command owner changes. Source-owned generation holds the shared native
poster lease and retains the ownership row lock through generation; live lease
contention raises so delivery can retry. Native generation's existing ownership
and lease checks are unchanged.

Regressions: `app-phoenix/test/dawarich/media_ownership_test.exs` (eight named
coexistence/standalone cases) and `spec/jobs/posters/media_ownership_spec.rb`
(four named source cases), each with RED/GREEN and individual mutation evidence.
Rails fixes are FRB-047/048/049; intentional differences are ED-FIX-MEDIA-OWNERSHIP.
Controller evidence: `impl-fix-media-ownership.report.md`.

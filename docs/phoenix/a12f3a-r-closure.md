# Route videos and native studio closure

Package R builds on RX-MEDIA and the O01/O02 domain split. Source captures
`test/fixtures/a8vv/videos/a12f3a-r01.json` through `a12f3a-r09.json` were present
at the assigned base; this package does not rewrite shared generators.

## Native storage handoff

R05 isolates the existing route-video attachment snapshot admission in
`RouteVideos.AttachmentEffects`. `AttachmentJob.enqueue!/2` retains the
coexistence ownership decision: native mode or Oban ownership invokes the
existing `Exports.PurgeWorker`; explicit Rails ownership retains the existing
`route_videos.attachment_job` command. No new worker or registry entry is added.
The snapshot checks attachment ID, record type/name/ID, blob ID and actor.
Replacement attachments and shared references prevent revocation; repeated
native purge requests create only one durable object-deletion job.

R05 evidence: initial missing-module RED; GREEN 1 test; M-R05 omitted the
attachment ID snapshot check and failed the retained-blob assertion (`[[0]]`
versus `[[1]]`); restored GREEN 1 test. The merged RX purge-worker test also
passes (1 test). Rails characterization batch: 44 examples, 0 failures.

Full suite, transport closure, studio binding, locale coverage and release
browser proof remain pending. G44 belongs to the controller release lane.

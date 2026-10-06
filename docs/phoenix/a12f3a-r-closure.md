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

R02 uses `cleanup_failed_save!/3` for rescue cleanup: attached blobs are retained,
unattached uploads use the same fenced attachment-job dispatch. Named test
covers MIME/size refusal and shared failure cleanup. Initial missing-function
RED; GREEN 1 selected test; M-R02 purged an attached blob and failed the
retained-blob assertion; restored GREEN 1 selected test. Full fault-envelope
coverage remains subject to the source-backed request table.

R01 native endpoint saves signed MP4s in all three deployment mode settings,
including unidentified uploads (native AnalysisWorker), exact size ceiling,
default name, unknown-key filtering and Unicode truncation. The source
`Recipe.read/1` replay contract remains available under coexistence; standalone
mode coerces native scalar/container recipe values before truncation. The
route-video domain gate no longer vetoes Cloud. Initial RED was a native 500
for explicit Cloud; GREEN 27 endpoint table cases plus scalar coercion;
M-R01 retained `unknown` and failed persisted recipe equality; restored GREEN.
Container coercion is source-code-backed but has no additional recorded source
envelope; ordered multi-key nested hashes remain an edge parity handoff.

R03 reconciled with merged retention: initial aggregate was already GREEN.
Cap zero/one, age boundary, gallery prepend/replacement order and durable
recipe/status compare to the existing captures. M-R03 expired newest instead
of oldest and failed exact stream equality; restored GREEN. No completed
retention adapter was rewritten. Equal-created-at ordering remains whatever
the source relation specifies; no new tie policy is claimed.

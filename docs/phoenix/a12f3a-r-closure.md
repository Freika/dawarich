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

Final suite evidence is recorded below. Exhaustive transport edges and release
browser proof remain controller handoffs. G44 belongs to the release lane.

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

R04 returns native 404 for missing/foreign deletes in standalone mode. Actor
scope, dependent detach, Turbo removal and HTML 303/flash are preserved.
Initial RED was missing-record replay; GREEN; M-R04 omitted actor scope and
failed the foreign-record assertion (`{:ok, id}` versus `{:error, :not_found}`);
restored GREEN. Snapshot and shared-reference races use R05's storage fence.

## Native studio and minimal wiring

R08/R09/R06 port all source controller actions to focused native modules under
`priv/static/js/hooks/`. Controls retain their original functional attributes.
The hook reuses the existing StudioState, date range, provider, MapLibre preview,
HUD, VideoRenderer, MP4 encoder/codec negotiation and DirectUpload modules.
No server renderer is introduced. Launch/close, format/theme/camera/track/fog/HUD,
units/watermark, range restore/navigation, progress/cancel, result playback,
recipe provenance and signed save are retained. Operation versions fence late
results; teardown removes listeners, aborts render/upload and revokes URLs.

Additional minimum seams for O06/O07: `app.js` registers VideoStudio;
`map_shell.js` mounts/disposes its portalled instance instead of starting the
source controller; `endpoint.ex` serves the native hooks directory. The studio
component uses `phx-hook="VideoStudio"`. O owns final hook/asset route reconciliation.
Two additional focused modules, `video_studio_dates.js` and
`video_studio_preview.js`, keep each production file below 300 lines.

Client evidence: R08 initial missing-controls-module RED; integrated native
mount/destroy and controls GREEN; M-R08 leaked a change listener and failed
listener count 1 versus 0; restored GREEN. R09 initial missing-render-module
RED; rendering/progress/cancel GREEN; M-R09 retained the object URL and failed
revoke list `[]` versus `["blob:0"]`; restored GREEN. R06 initial abort-signal
assertion RED; signed save/provenance/progress cleanup GREEN; M-R06 saved end_at
as start_at and failed the distinct timestamps; restored GREEN. The three named
client tests and existing settings/date/codec/map lifecycle tests pass: 60 tests.
This is Node evidence, not browser or real WebCodecs export acceptance.

R07 locale cards reconciled with the merged component: initial behavioral
aggregate GREEN after correcting template text extraction in the test. English
cards compare to captures; all seven source locales exercise deletion links,
confirmation, playback/preload, expired recipe controls and success/error
messages. M-R07 kept playable media on an expired card and failed the no-video
assertion; restored GREEN. No already-completed component was rewritten.

## Remaining integration and edge proof

Domain workers retain current claimability and coexistence ownership decisions;
sibling rows 19–22 own registry/sink/cron/payload readiness. Native storage
uses existing blob revocation and object deletion, preserving shared references.
Source callbacks and unknown source payload disposition stay with their owners.
Handled native save/retention failures use the configured Sentry interface;
shared privacy/transport acceptance remains its owner's gate.

Outstanding edge envelope proof: exhaustive guest/expired-session/CSRF and
unsupported-format matrices; ordered nested/container recipe coercion; tied
created-at ordering; full locale Rails HTML captures and real codec-unavailable
browser workflows. Standalone rejects unsupported admitted envelopes natively,
per tonight ruling 15. Existing coexistent replay behavior is retained outside
this proven native scope. HEAD/media capabilities belong to the storage owner.
O08 must repeat affected source generators twice at the reconciled integration
head; package R does not claim new generator counts or byte stability. G44
browser/export acceptance and seed 202 remain controller gates.

The named client tables also cover unavailable-codec UI, render completion
following destruction, and an aborted direct-upload callback arriving late.
These deterministic probes pass without machine load or timing sleeps.
Forced native compilation with warnings as errors and format check pass.

A native child-hook-before-map mount probe initially failed because the existing
studio retained the earlier application. `mountVideoStudio/2` now refreshes
that application when the map/trip portal supplies it. The controller identifier
is retained as source-compatible metadata; the portal explicitly bypasses
source Stimulus startup for this studio. Source page regressions pass:
27 map/trip tests, 0 failures. The complete client regression batch still passes
60 tests, 0 failures. No full suite had started while this fix was made.

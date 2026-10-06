# Imports HTTP and producer closure

Standalone priority cut, 2026-10-06. This extends the existing A12f-2 import intake and A7 producer implementations. Full package I envelope closure remains open.

The upload form accepts the existing direct-upload signed references and queues GPX or normal processing according to the locked command owner. Empty uploads return the source 422 redirect and alert cookie. Rejected batches leave no imports, attachments or commands. Format detection failures return a native 422; their exact Rails exception messages remain open.

Import PUT and POST `_method=put` now reach the update action. Blank or duplicate names retain Rails 1.15.3 behavior: validation prevents persistence while the controller redirects with its success notice. Invalid sources render the existing 422 edit form.

Manual GPX extraction and removal publish `enhanced_import.extract_gpx` and `enhanced_import.destroy_gpx` directly when those command owners are Oban. The payloads use the existing worker decoders: `{import_id, lock_attempt: 1}` and `{import_id}`. The outbox UUID matches the extraction event stored on the import; aggregate identity is the actor, scheduling is immediate, and the transaction locks owner, import and user. Source-owned requests retain their accepted reverse handoff. Duplicate active extraction requests publish no second command and redirect with the source authorization alert. Native removal with extracted visits or tracks returns a terminal 422 until package F's broader removal worker is ready.

Minimal O wiring: `import_routes.ex` adds PUT alongside PATCH with the same pipeline and ownership metadata. No shared transport parser, CSRF guard, Registry entry, global fallback or claimable flag changes.

## Verification

`a12f3a_i_closure_test.exs` contains the aggregate I02, I03, I04 and I09 tests. Each initially failed on missing behavior, passed after implementation, failed its production mutation and passed after restoration. The tests disconnect the Rails upstream and inspect persisted imports, attachments and outbox/reverse-command rows.

TeslaMate completion uses the existing native anomaly filter inside its worker transaction and publishes `tracks.generate_realtime` with an event-based dedupe key when that downstream owner is Oban. Track backfill uses `BackfillCommands.put/4`, preserving its range accumulation, captured zone and delayed scheduling. Stats retain `Stats.Schedule.calculate/6` and its independent owner. Source-owned realtime retains the original reverse effects. Shared tile/anomaly-dependent effect sinks still belong to sibling rows19–22.

The existing imports page generator now records `a12f3a-i02.json`, `a12f3a-i03.json` and `a12f3a-i04.json`. The writer ran twice with an empty whole-fixture byte diff; previous fixtures were unchanged. This package captured these independently because O04's additions were not present at its base. No newly named Rails example was added; the existing generator example was extended.

The existing normal import producer generator also records I07–I12 source captures independently. I01, I05–I08 and I10–I12 reuse existing implementations and characterization tests. They are not represented as newly RED-tested tasks. Evidence and final gate counts belong in the controller-assigned execution report.

## Remaining scope and handoff

- I01: complete malformed legacy rows, foreign/missing authorization ordering, unsupported page envelopes and HEAD characterization.
- I02: raw multipart, descriptor shapes, exact checksum/storage failure messages, quotas and all transport/environment combinations.
- I03: full query/format/Turbo tails and coercion envelopes.
- I04: package F's source/blob/attempt fencing and non-GPX extraction/removal interface; redirect-back envelopes and removal of extracted visits/tracks.
- I05–I06: remaining download error envelopes, native delayed purge and terminal event integration.
- I07–I08, I10–I12: existing native producer tests pass against current-head Rails captures. Their remaining envelope/mutation reconciliation and downstream effect sink closure still need package completion evidence. I09 realtime/backfill production is now native; shared tile/anomaly-dependent effects remain sibling-owned.
- F and sibling rows19–22 own worker/effect/schedule readiness. Keep job entries inert. The producer changes do not prove source-drain completion or authorize release deployment.

The shared AFFiNE counterpart is the Dawarich Phoenix imports HTTP and producer closure document. The master source of implementation conventions remains the controller's A12f-3a plan D and Ruby-free release plan.

# A12f-3a W closure

This cut implements the native point/tag/segment/area/recalculation journeys prioritized by ruling15. It preserves current Rails1.15.3 behavior, including unwindowed actor-scoped bulk deletion; the plan's proposed deletion cutoff does not match `Points::Destroyer`.

## Domain results

- W01: tied point timestamps/import creation times read natively; import filtering, pagination, time zones and plan window remain intact. Actor-scoped invalid imports return404; integer-prefix import IDs preserve source coercion.
- W02: focused PointAddress action serves direct documents and Turbo frames, preserves address escaping/locale and geodata-only formatting, and terminates missing/foreign/invalid IDs with404. O must reconcile its route and malformed-path dispatch constraints.
- W03/W04: scalar point IDs return source500 without DML. Arrays/duplicates/foreign/old-plan points retain source semantics. Under native phase ownership, deletion atomically persists counters, tile-epoch intent, native month statistics, track recalculation and debounced achievement commands. Pre-commit rendering failures roll back all effects; explicit source ownership retains coexistence.
- W05–W07: missing/foreign tag reads and writes terminate with404. Missing/blank tag groups return400 and scalar groups500. Existing source validation, Unicode rules, redirects, timestamps and dependent tagging deletion remain; places survive deletion.
- W08/W09: segment PUT and overrides use the native editor. Actor/track/segment joins enforce404 for missing/foreign/wrong-track writes. Existing mode/source/confidence/reset/geometry and failure behavior remain. SegmentEditEffects exposes the existing tracks_changed publication for the shared native sink owner.
- W10/W11: top-level area POST/PATCH/PUT and overrides preserve source validation in all seven supported locales and HTTP200 Turbo flashes, no-op timestamps, actor scope and relabel dedupe. Create/geometry changes publish relabel; rename/no-op do not. Unknown response formats are terminal406 after the source-ordered write. The existing RelabelWorker retains historical visit attribution.
- W13/W12: typed no-retry parent fan-out orders actor-owned tracks in batches100 with10-second staggering. Parent replay and child progress are idempotent. Native status starts before children are visible, completes empty/finished work, and reports fan-out errors with source TTLs. The request preserves running/started flashes and HTML redirects.

## Producer and integration contracts

| Caller | Command/effect | Native contract | Accepted-work fence |
|---|---|---|---|
| WebDestroyEffects | stats.calculate_month | version1 `{user_id,year,month,notify_on_failure:true}`; source actor-local month | existing ownership locks and transaction |
| WebDestroyEffects | tracks.recalculate | version1 `{track_id}`; unique affected tracks | same transaction |
| WebDestroyEffects | achievements.check | version1 `{user_id,notify:true,oldest_timestamp}`; due60s; pending actor dedupe/minimum timestamp | same transaction |
| WebDestroyEffects | points.tile_epoch | existing RailsEffects.tile_epoch intent, actor/timestamps | same transaction; sibling owns sink |
| SegmentEditEffects | tracks_changed | existing Tracks.Effects.write! signature, source bounds and track identity | existing transaction; sibling owns sink |
| Areas.WebWrite | areas.relabel_visits | version1 `{area_id}`, aggregate/dedupe area ID; existing worker | ownership lock and transaction |
| Tracks.WebRecalculation | transportation.user_reclassify | version1 `{user_id}`, tracks queue, UserReclassifyWorker/max_attempts1 | ownership lock, actor row lock, transactional outbox |
| UserReclassify | transportation.reclassify_track | unchanged version1 `{track_id,report_progress,user_id}`, due slice-index*10s; parent event/locale/zone metadata | parent Processed.claim!, actor row lock, child owner lock and transaction |

Point follow-ups carry locale/time_zone/request-event metadata. RecalculationStatus provides `data/1`, `in_progress?/1`, `start/3`, `increment/3`, `complete/2`, `fail/3`, `native?/1`, `clear/1`. Its JSON status is native; a missing native status reads the existing legacy cache. Native child completion uses atomic event dedupe; legacy accepted work retains its existing transport_progress intent. The settings/status API consumer must adopt this seam. Registry owner registers `command:transportation.user_reclassify` with claimable:false until producer/readiness integration. No shared Registry, session/parser, Strangler, sink or ownership flag was changed.

Minimal routing changes in page_routes/map_frame_routes make the main journeys reachable. O06/O07 owns the serialized final reconciliation, including malformed IDs, HEAD and transport envelopes. Extra worker seam: ReclassifyTrackWorker selects native progress for native status while preserving legacy progress otherwise. M07 consumes existing point/track/area effects after sibling sinks are reconciled.

## Evidence

O03–05 captures were absent at the assigned base, so needed source cases were captured locally in the exact `test/fixtures/map_writes/a12f3a-w01.json` through `w13.json` paths. The generator remains scratch-only and does not edit O's shared generators. Final source writes are byte-identical. Source request/job batch:73 examples,0 failures; supplemental captures:2 examples,0 failures each write. Swagger was copied/restored for every RSpec batch; no production Ruby changed.

The package has12 source-backed aggregate tests. Every new named task test recorded missing-behavior RED, GREEN, its named mutation failure and restored GREEN. W09 reconciles the already-implemented reset against its existing test rather than inventing RED; omitting reset tracks_changed fails it. Additional invalid import/point ID/blank tag group/fan-out error cases recorded their own failing and restored mutation probes. Allocation settings are environment-driven.

The execution report contains exact command/log/count evidence and final gate outcomes. The first full404 gate exposed obsolete hand-back assertions and missing local Swagger assets; dependencies were installed and tests now retain source state/metadata assertions while expecting native responses.

## Open envelopes and release boundary

This priority cut does not close the entire historical ED or declare Ruby-free release acceptance. W01 legacy settings, named-date parser and pre-epoch import defaults; W06/W08 richer container/repeated parameter and source format errors; W10 additional numerical coercion tails; W04 debouncing beyond pending-outbox dedupe remain unclosed. Existing shared transport owner/O must reconcile auth/CSRF/Cloud/HEAD and malformed-path dispatch. W08 foreign/missing segment index admission remains the existing M frame hand-back and needs callee reconciliation. Native status consumer, registry claimability and cache/live effect sinks remain the named sibling handoffs; explicit source-owner paths are pre-commit coexistence.

Release Playwright/image/native-stand acceptance and seed202 belong the controller's integration/release lanes. Local passing tests do not establish those gates.

Final local gates: full seed404 passed8648 tests/0 failures (partitions2638,2903,3107;11 existing exclusions,3 existing skips). Forced Mix compile1426 files with warnings-as-errors and format check pass. New locale mutation forces English validation messages, fails the German source assertion, and restored W10 passes. All13 final source captures are byte-identical across the final two writes. Tied point IDs are captured as an explicitly normalized set because Rails does not specify a tie-breaker; non-tied ordering goldens remain unchanged. The capture resets its remembered locale before the English recalculation projection. No changed production Ruby or Swagger/schema drift.

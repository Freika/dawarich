# A12f-3a package M closure

Source baseline: Rails 1.15.3; implementation base c3197844f. This delivers ruling 15's tonight main-path slice; exhaustive edge and integrated release acceptance remain below.

## M01 — map shell selection

Both `/map` and `/map/v2` render natively, including explicit date selection, timeline panel, studio hosts and HEAD. Text dates captured from Rails include slash-separated dates and day/month-name/year. Tests run in self-hosted, explicit Cloud and unset-default modes with no Rails upstream.

The tagged M01 aggregate initially failed on the selected start date; implementation passed. Ignoring `date` in `MapWindow.bound/4` failed that assertion; restoring passed. Existing map parity, import range, settings, locale and LiveView tests are retained.

O03 source captures were not at this base. Package M extends the existing source generators and records task captures itself. Capture normalization and source clock remain the existing generator convention. Source recording, gate counts and mutation assertions are recorded in the execution report.

## Ownership and handoff

M owns presentation and frame reads. No native jobs or reverse effects are produced. Map/track refresh uses the existing A12a channel contracts. W owns point/segment/area effects; V owns visit effects/cache invalidation; R owns video hooks. Global transport and final route wiring remain A12f-2/O-owned.

## M02 — legacy redirects

`/map/v1` and `/maps/v2` return 301 natively, including guests, signed-in users, Cloud and HEAD. The former canonicalizes parsed query parameters; the latter drops them. Captured `.json` suffixes redirect to the same destination. Bodies are empty, matching Rails.

The M02 aggregate initially reached the absent Rails upstream. Native implementation passed all 96 request combinations. Dropping the legacy query failed the exact Location assertion; restoring passed. Minimal wiring is in `page_routes.ex` with `rails_key: "map"` and a guarded `map_redirect` pipeline; O should retain these declarations in its serialized O06 pass.

## M03 — timeline feed

Missing/blank timestamps and malformed scalar timestamps use the current instant, matching Rails SafeTimestampParser. Locale/client markers no longer force a Rails handback for scalar frame queries. Structured timestamp envelopes have captured source 500 outcomes and terminate natively before frame data reads.

Two source capture passes preserve same-time visits in the observed descending-ID encounter order. Rails orders only by start time; this is a characterized ambiguity, not an upstream bug fix. The native secondary order matches this capture. Reversing that order fails the complete normalized frame assertion; restoring passes. Source and native assertions also retain DST, ranges, plan windows and existing rich-feed fixtures.

## M04 — calendar frame

Calendar frames accept the source single-digit month form and preserve complete source grid cells. Month bounds remain local to the user; the source capture includes a next-month visit that must not count, even in an adjacent grid cell. Existing HTML/Turbo/HEAD, DST and Lite-window fixtures remain regression evidence.

The initial aggregate failed admission for `2026-9`. Native month normalization passed. Extending the visit query into the next local month failed frame parity; restoring passed. Malformed scalar and structured months return a terminal native error instead of replay. Visit/calendar invalidation belongs V09/shared effect owners; this reader recomputes natively and creates no cache jobs.

## M05 — track-info frame

The current base already has owner/missing/foreign track isolation and source parity. The aggregate is reconciled as initially GREEN, not an invented RED. M03's shared frame admission also covers locale markers. The lookup now lives in `Timeline.DayAssociations.track/3`, with the existing `DayRows.track/3` interface delegated unchanged.

Removing the `user_id` predicate fails the foreign-track `:not_found` assertion; restoring passes. The source track payload, DOM IDs, units and localized frame body are compared. No provider calls or job effects are added. Non-numeric path IDs and JSON/format routing remain A12f-2/O transport handoffs.

## M06 — residency frame and ties

The native frame preserves the source country encounter order on tied day counts and tied per-day point counts. `Residency.term/3` takes `:source` for this captured frame contract; the existing API/default strict coexistence behavior is unchanged. The focused `ResidencyFrame.data/3` call-site change is a minimal callee seam.

Year strings use Ruby integer coercion. Structured years and out-of-int32 time bounds fail natively. The source 2038 `ActiveRecord::RangeError` remains a 500; it is not corrected during the port (ruling 13). Cloud Lite rejects before year parsing with source 303, location and alert; guest authentication remains first. The aggregate originally failed on the tied-country replay. Reversing tied country encounter order fails complete frame parity; restoring passes.

Existing tied-country handback tests now assert native output and no upstream request. The old corpus census remains scoped to its original cases; the package aggregate owns the new task captures. Source generators were recorded twice, with identical task bytes and old fixtures restored.

## M07 — presentation and realtime lifecycle

Existing `MapShell` remains the native LiveView hook and hosts retained client assets. The aggregate evaluates the production shell, realtime controller and channel adapter with deterministic timers and boundary-only adapters. It covers destroyed-before-setup, late controller registration, duplicate mount, points/track edit refresh, track refresh coalescing, family subscription, studios and one unsubscribe per subscription.

This behavior is already present at the base and reconciles as initially GREEN. Removing controller unload during shell destruction produces four late subscriptions (expected zero); restoring passes. Existing channel contract checks pass 6/6. No redundant production rewrite or additional socket is introduced.

Producer-to-browser visit/area/segment/video completion requires W/V/R/A12a handoffs and G44, outside this isolated presentation cut. Native Turbo frame rendering and native channel consumption are proven separately; this is not a claim that those integrated release journeys were run.

## Remaining shared transport / release cases

A12f-2/O retain global raw-query rejection, JSON/format routing and path constraints, expired-session envelopes and key rollback integration. Package M does not edit shared Strangler/Slices/session parsers or claim final Ruby-source deletion. Source malformed settings, broader Date.parse forms, unusual date/time envelopes and all-locale browser parity remain the next edge parity pass under ruling 15. Known 2038 range failure and unspecified same-time encounter ordering are handed to the controller's deferred Rails bug register.

Seed 202 belongs to the integration head under ruling 14. G44 browser proof and integrated producer-to-refresh proof remain controller release checks.

## Package verification

Forced compile with warnings as errors passed for 1,417 files; format checks passed. The targeted Rails request suite passed 41 examples, and seven existing source generator examples passed after final formatting. Both changed Ruby generators passed RuboCop. Named task mutations and twice-write capture comparisons are recorded in the execution report.

The first full seed-404 run exposed old endpoint ownership assertions and an unguarded redirect router declaration. Native response assertions now verify no upstream request, and the dedicated redirect pipeline owns host, SSL and rate-limit checks. The affected endpoint/rate-limit/package batch passed 57 tests.

The second full run passed the map partition but exposed an existing metrics test's 100 ms asynchronous first-connection handshake. The test now holds the real pool connection synchronously and waits for an actual queued client before sampling, with the original deadline and saturation/duration assertions retained. Both metrics tests passed with a single Erlang scheduler. This minimal test-only gate fix changes no production metrics code.

The final required three-partition seed-404 gate passed: 8,642 tests, zero failures (2,642 / 2,893 / 3,107 per partition). Existing suite exclusions and skips remain unchanged. Gitleaks found no leaks; git diff checks found no whitespace or swagger/schema drift. Final committed-head scan and cleanup evidence are in the execution report.

AFFiNE counterpart: Dawarich — Phoenix A12f-3a map shell and frames implementation (`MLaNM8OY0qcTmNHoSGaYa`). Planning index: `cdFa14Gdde-iWiERUNqIo`; package M plan: `ZIKYW9aTewW7RQU6pjL2K`.

## Post-hoc map/frame corrections — 2026-10-07

The five package M post-hoc findings are covered by named tests in `app-phoenix/test/dawarich_web/map_frames_regression_test.exs`, dispatched through the real Endpoint.

- Timeline scalar timestamps use the existing Rails `Time.zone.parse` compatibility parser (`Imports.ImportTime`), including slash, month-name, dotted, compact and RFC forms, civil-day rollover, source clamping and invalid-input fallback. Structured timestamps retain the source 500.
- Calendar months use the existing `MapApi.RailsDate` parser on the source's appended `-01`, rather than an ISO-only grammar. Slash/name/ISO-week forms and the surprising `09/2026` interpretation remain source-compatible. A full date selects its source grid week while activity queries cover the entire local month.
- Map day selection uses the same Date parser, with the user's current local day as its default. Invalid short month prefixes and oversized numeric days fall back to the selected import range/current day. Rails-accepted full month names, compact/ordinal/week dates and `Octopus` remain accepted.
- Legacy redirects and ForceSSL destinations use the shared `RequestURL`/`RackScheme` URL handling. External HTTPS, forwarded host chains and explicit ports are preserved. The trial-welcome branch's separate `RailsRemoteIp` work owns trusted client-IP selection; this correction introduces no competing forwarded-header parser.
- Terminal frame errors use `RailsErrors.respond/3`, retaining the public Rails error page and UTF-8 content type. The source residency-2038 failure remains a 500.

Every named regression failed before implementation, passed after implementation, failed its production mutation, then passed after restoration. The focused map/parser batch passed 84 tests with zero failures; the expanded regression/setup batch passed 109 tests with zero failures. The final full seed-404 gate passed 9,417 tests with zero failures across three partitions. Forced compilation with warnings as errors and formatting passed. Release/browser and integrated producer checks retain the controller ownership described above; seed 202 remains an integration-head gate.

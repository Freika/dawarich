# A12f-3a package M closure

Source baseline: Rails 1.15.3; implementation base c3197844f. Main map journey first, per ruling 15.

## M01 — map shell selection

Both `/map` and `/map/v2` render natively, including explicit date selection, timeline panel, studio hosts and HEAD. Text dates captured from Rails include slash-separated dates and day/month-name/year. Tests run in self-hosted, explicit Cloud and unset-default modes with no Rails upstream.

The tagged M01 aggregate initially failed on the selected start date; implementation passed. Ignoring `date` in `MapWindow.bound/4` failed that assertion; restoring passed. Existing map parity, import range, settings, locale and LiveView tests are retained.

O03 source captures were not at this base. Package M extends the existing source generators and records task captures itself. Capture normalization and source clock remain the existing generator convention. Source recording, gate counts and mutation assertions are recorded in the execution report.

## Ownership and handoff

M owns presentation and frame reads. No native jobs or reverse effects are produced. Map/track refresh uses the existing A12a channel contracts. W owns point/segment/area effects; V owns visit effects/cache invalidation; R owns video hooks. Global transport and final route wiring remain A12f-2/O-owned.

## M02 — legacy redirects

`/map/v1` and `/maps/v2` return 301 natively, including guests, signed-in users, Cloud and HEAD. The former canonicalizes parsed query parameters; the latter drops them. Captured `.json` suffixes redirect to the same destination. Bodies are empty, matching Rails.

The M02 aggregate initially reached the absent Rails upstream. Native implementation passed all 96 request combinations. Dropping the legacy query failed the exact Location assertion; restoring passed. Minimal wiring is in `page_routes.ex` with `rails_key: "map"`; O should retain these declarations in its serialized O06 pass.

## M03 — timeline feed

Missing/blank timestamps and malformed scalar timestamps use the current instant, matching Rails SafeTimestampParser. Locale/client markers no longer force a Rails handback for scalar frame queries. Structured timestamp envelopes remain deferred to the shared transport/domain edge pass.

Two source capture passes preserve same-time visits in the observed descending-ID encounter order. Rails orders only by start time; this is a characterized ambiguity, not an upstream bug fix. The native secondary order matches this capture. Reversing that order fails the complete normalized frame assertion; restoring passes. Source and native assertions also retain DST, ranges, plan windows and existing rich-feed fixtures.

## M04 — calendar frame

Calendar frames accept the source single-digit month form and preserve complete source grid cells. Month bounds remain local to the user; the source capture includes a next-month visit that must not count, even in an adjacent grid cell. Existing HTML/Turbo/HEAD, DST and Lite-window fixtures remain regression evidence.

The initial aggregate failed admission for `2026-9`. Native month normalization passed. Extending the visit query into the next local month failed frame parity; restoring passed. Malformed scalar months return a terminal native error instead of replay. Visit/calendar invalidation belongs V09/shared effect owners; this reader recomputes natively and creates no cache jobs.

M05–M07 closure and final full-suite gates are pending. G44 browser proof and integrated producer-to-refresh proof remain controller release checks.

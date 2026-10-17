# Deterministic tie ordering

Controller scope: fix-segment-tie-order, 2026-10-07. Rails remains unchanged.
DRB-033/034/035 in [Deferred Rails bugs](deferred-rails-bugs.md) and
ED-FIX-TIE-ORDER in `app-phoenix/parity/expected_diffs.md` record the authorized
corrections. The shared AFFiNE deferred-bugs register is the cross-project index.

Rails `Tracks::SegmentEditor#recompute_dominant_mode!` loads
`track.track_segments.reload.to_a` without ordering. `Track#update_dominant_mode!`
has the same defect. `Track.pick_dominant_mode` builds insertion-ordered hashes
and keeps the first encountered mode when both total distance and duration tie;
its non-moving fallback also keeps the first duration tie. Neither the
association nor TrackSegment defines a default order.

Choose ascending segment ID, reusing the existing native
`Segments.load_segments_for_dominant_mode!` used by reset/reprocess. Rails'
usual heap/bitmap scan of normally allocated, monotonically inserted segment
IDs enumerates that creation order. A real Rails transaction probe confirms the
normal ascending-ID example chooses Walking under the default bitmap plan and
both forced scans. For the deliberately reversed-ID corpus, a sequential scan
chooses Driving and a mode-index scan chooses Walking. Ordering by ID makes both
choose Walking. This is an explicit deterministic policy for an unspecified
Rails result, rather than a claim that Rails itself already guarantees ID order.

The `override_tied` corpus keeps its Rails inputs and 1000 m / 595 s totals. Only
the expected track dominant mode (5 → 2) and the track-info label (Driving →
Walking) change to the authorized native expectation. Recapturing this case
from unchanged Rails can produce either result: retain the documented native
expectation until the Rails ordering fix ships.

## Native audit and changes

| Picker / caller | Input ordering and disposition |
| --- | --- |
| SegmentEditor dominant mode | Reuse the ordered Segments loader; covers moving and duration-only fallback ties. |
| Segments recompute; Reprocessor reset; release transportation | Already use the ascending-ID loader. No additional change. |
| Insights.Details top visits; Stats.Insights top visits; Stats.ApiClosure scoped visits | Append `name COLLATE "C"` after descending visit count and duration, before LIMIT. Existing Stats.Insights strict tie refusal stays intact. |
| Digests.LocationTime country minutes / Toponyms.ranked | Append `country_name COLLATE "C"` after the existing date/minimum-timestamp keys; equal totals retain this first-seen order. |
| Residency daily country and country-day rank | Append C-collated country after date. Primary point counts/day totals and first-visited date ordering remain. Strict mode continues refusing unresolved equal counts/day totals. |
| Locations accuracy representative; Locations.Closure | Order SQL rows by timestamp then ID before stable timestamp sorting. Equal timestamp/accuracy chooses the smallest ID. |
| Photos.Enrichment nearest point | Order by timestamp then ID. Its existing last-before selector chooses the largest ID at an exact timestamp; the first-after selector uses the smallest ID. |
| Visits.PlaceAttributor most-visited known place | Already reads `ORDER BY p.id` before rank `{manual, -visit_count, distance}`. |
| Visits.NamesSuggester | Its SQL caller already reads point geodata by ID; provider feature lists have source-defined order. |
| Digest country/city counts from stored stats | Queries.yearly orders unique user/month rows by month; history orders by ID. Ordered JSON arrays retain first-seen country/city order. |
| Insights biggest month; stats summary | Callers sort unique periods by month or year/month before selecting an equal-distance maximum. Scalar latest-date maxima and additive sums have no row-identity tie. |
| Transportation.Decoder, QR masks, CSV delimiter | Fixed algorithmic candidate lists, not unordered SQL. |
| BackfillInstanceSettings lowest-rate setting | Equal winning rates require identical provider/host/HTTPS/API-key signatures and coerce to the same output rate; row identity cannot change the published settings. |
| Live point broadcast; enhanced-import point groups | Ordered job/input payloads, not SQL tie enumeration. |

## Verification

New named regressions use transaction-local planner settings: sequential versus
index scans, bitmap/index-only scans disabled, and hash versus sorted aggregation
for ranking groups. The dominant regression also checks EXPLAIN for actual Seq
Scan and Index Scan nodes. All assertions use real repositories; the photo test
uses a bounded loopback provider and closes its sockets.

Each new test is observed RED before its fix, GREEN after, failing under its
named production mutation, then GREEN after restoration. Controller evidence
contains exact names/results, the Rails SQL/EXPLAIN probe, targeted regressions,
forced warnings-as-errors compile, formatting and the full seed-404 gate. No
runtime allocation is part of the source or fixtures.

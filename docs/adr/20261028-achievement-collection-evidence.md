# Versioned achievement evidence and shared H3 exploration

Status: accepted for this local implementation. Date: 2026-10-28. Production rollout is separate.
AFFiNE counterpart: `ILvDbKOEg4oNn6KXgTLeB`. Shared vocabulary: workspace `CONTEXT.md`.

## Context

The approved six-series design is in workspace `docs/plans/2026-10-28-achievement-series.md`,
indexed by AFFiNE document `Xb6wLAA41QcZPRS2Y6IqE`. Existing country/subdivision
awards have permanent earned-code semantics and one key per user. That model
cannot safely represent multiple selected places/cities or revocable evidence.
Workspace exploration ADRs 0001–0006 already require one all-history H3 ledger,
resolution 9, exact land intersections, shared flight eligibility and versioned
geodata. ADR-0003 originally deferred cities; this decision extends that model
to explicitly cataloged administrative cities without changing country semantics.

## Decision

Keep three fixed thematic sets in the existing registry. Add a separate typed
collectible per `(user, series, stable subject)` for Return, Seasons, City,
Park, Parks and geographic Milestone, with rule version, historical earned time,
calculation timestamp, source revision and references to supporting observations.
Concrete Ruby rules implement these series; there is no generic rules language.

New collectibles follow current evidence: a lost qualification reduces its level,
records a revocation and disables sharing when no level remains. Removing a
selection keeps its card/event journal but removes it from visible collections.
One first-earned event per card/level prevents repeat celebrations on re-earning.
The journal's `occurred_at` is historical event time; `created_at` is detection time.
Old country awards retain their permanent semantics.

Statement-level PostgreSQL transition triggers dirty per-user revisions for bulk
Point/Visit/Place/selection/privacy/track writes. Background jobs stream history
and publish under a per-user advisory lock and revision fence. Failed/stale work
keeps the previous complete result. A five-minute durable refresh sweep recovers
missed enqueue attempts; request claims expire after an hour. UI/queries enqueue
work instead of calculating history in requests. Initial and dataset backfills
are silent; more than five new cards produce one notification digest and the
existing unlock deck.

Extend the existing exploration implementation from the local
`country-exploration-ui` worktree with `kind`, local timezone and provenance on
territories. Countries, cities and parks live in immutable dataset versions;
country/world totals exclude overlapping city/park rows. City percentages and
mosaics use exact intersection of opened resolution-9 cells with administrative
land, including forests/outskirts, excluding water in the shared Natural Earth
5.1.2 mask. Small water bodies missing at 1:10m are a known approximation.
No LOD parents, circles, monthly statistics or interpolated points earn area.
Fog reads the same ledger; dates highlight first discoveries without reclosing
older cells. A city deep link pins its owned snapshot for a consistent map.

A local tzf2 coordinate lookup resolves Place IANA timezones independently of the
profile timezone. Ambiguous lookup blocks temporal qualification until the owner
chooses a valid IANA zone. Coordinate changes invalidate the cached lookup. A packaged timezone-data version change invalidates published collection state and silently rebuilds automatic lookups and geographic observations; explicit IANA overrides remain.
Overlapping valid visits coalesce; a Visit contributes one season by local start,
with seven local calendar days between selected visits. Return compares consecutive
coalesced visits, from previous end to next start, using calendar-year arithmetic.

Observed-time rules stream consecutive points per device. Both endpoints must
qualify in the same region and local timezone, gaps must be at most ten minutes,
and each pair contributes at most two minutes. Union intervals across devices,
split at local midnight, and never bridge excluded flight/anomalous/private points.
Parks require thirty minutes/day within the actual polygon; milestones require
ten minutes/day per required region. Geographic margins use great-circle distance
from both meridians, including the dateline, plus equatorial/polar latitude margins.
The polar game latitude is fixed at 66.56°, not an astronomical calculation.

## Privacy and publication

Every card starts private. Public Place cards reject effective privacy zones.
City sharing defaults to a generic city silhouette and achieved tier. An explicit
mosaic opt-in masks all cells touching effective zones and recalculates the public
area. Park and milestone public projections independently exclude private
observations, including their dates and levels; a fully hidden park is unavailable.

Shared HTML, embed and OG PNG require an enabled owner link, fresh source state,
current dataset and privacy fingerprint. Changes invalidate HTML and images
immediately; every response is `private, no-store`. Owner pages can retain their
last consistent private result during recalculation, with a visible status.
Raw traces are not embedded in card JSON, public markup or notification payloads.

## Alternatives and consequences

Reusing permanent country codes would lose subject identity and revocation
history. Counting monthly cells or equal-size hexagons would disagree with fog,
water and actual area. Online geodata/timezone lookup per point would add privacy,
latency and availability dependencies. All are rejected.

The pilot includes Berlin, Hamburg, Dresden and Harz, Saxon Switzerland and Eifel
national parks, using fixed OSM relation identities. It is a regional selection,
not a complete country/world catalog. Runtime needs no geodata service. Expanding
the catalog requires reviewed identities, checksums, a new catalog and exploration
dataset version, and a full background replacement. OSM derived geometry is ODbL;
Natural Earth source data is public domain. Details and rebuild procedure are in
`lib/assets/achievement_collections/README.md` and `lib/assets/exploration/README.md`.

Full history recalculation favors consistency over incremental complexity. Large
accounts can take time; request latency remains bounded and a previous snapshot
remains usable. Source changes during computation cause a later retry instead of
publishing mixed evidence. Seven achievement locales cover all new labels/rules.

## Verification and references

`docs/achievement-collections.md` records installation, routes, maintenance and
verification. Unit/request coverage includes exact land/water clipping, shared
classifier/manual corrections, historical imports and deletion, timezone/calendar
edges, device overlap, local midnight, privacy/OG, revocation/re-earning, merging,
notification batching and snapshot ownership. JavaScript coverage includes fixed
H3 resolution, dateline edges and stale-response fencing. Browser checks use
synthetic fixtures only, including mobile, sharing, embed, OG and city map links.

Related: `docs/achievements-themed-sets.md`, workspace ADR-0001–0006 and the existing
`docs/adr/20261015-achievements-disputed-areas.md` policy. This decision introduces
no production data change or deployment.

# Achievement collections

Implementation: branch `feat/achievement-themed-sets`, based on `dev` at
`13ec7af9e`. This is local Rails work; deployment and catalog expansion are separate.
AFFiNE implementation counterpart: `Vuog9kWJKa3IjV6PrAY6W`.
Canonical design: workspace `docs/plans/2026-10-28-achievement-series.md`, AFFiNE
`Xb6wLAA41QcZPRS2Y6IqE`. Decision: `docs/adr/20261028-achievement-collection-evidence.md`.

## Delivered series

| Series | Subject and qualification | Levels |
| --- | --- | --- |
| Themes | Benelux BE/NL/LU; Baltics EE/LV/LT; Scandinavia DK/NO/SE. Existing country visit codes; subdivisions need not be complete. | Rare |
| City | User-pinned catalog city; exact opened H3-r9 land area / administrative land area. One valid ground point opens a cell. | 1/5/10/25%: Common/Rare/Epic/Legendary |
| Return | Selected Place; valid visits of at least 20 min; gap from previous visit end to new visit start. Overlaps merge. | 1/3/5 calendar years: Rare/Epic/Legendary |
| Seasons | Selected Place; four separate 20-min visits, each at least seven local days apart; local season of start. Years may differ. | Epic |
| Nature | Individual national park, actual polygon observations; at least 30 observed min in one local day. | Rare per park; 1/5/15 parks: Common/Rare/Epic |
| Milestones | North+South; East+West; all NE/NW/SE/SW; Arctic; Antarctic. At least 10 observed min per region in a local day, with 10 km boundary margins. | Rare/Rare/Epic/Epic/Legendary |

A valid temporal Visit is active, ended, at least twenty minutes in both saved
and actual duration, Confirmed or Suggested with confidence >=70. Declined and
deleted visits are excluded. The Place timezone is resolved offline by tzf2 and
stored with lookup/data version and coordinates. Ambiguity requires an explicit
IANA override; the profile timezone never changes seasons. Southern season names
reverse; tropical latitudes below 23.44° use neutral DJF/MAM/JJA/SON labels.

Observed time is the union of consecutive device intervals, maximum gap ten
minutes and maximum contribution two minutes/pair. Excluded observations break
continuity. Split at local midnight; require the target within one local day.
Moving inside a park is valid. Neither a flight line nor a border H3 cell proves
a park visit. Presence in different hemispheres does not prove a continuous crossing.

## Owner and public surfaces

`/achievements` retains existing country/continent collections and adds themes.
`/achievements/cards` contains six personal series, a series filter and 24-card
pagination, city pinning and search/pinning of owned Places. Place drawers expose
the same pin action. Details explain rules, evidence dates, per-region observed
minutes, next city level and first-earned/revocation history. Archived Places
retain their selected history; merges transfer card identity/events to the survivor.

Mutations: `/achievements/places`, `/achievements/cities`, and
`/achievements/cards/:id/toggle_sharing`. They require an authenticated owner and
achievements access. Explicit links use `/shared/achievement_cards/:uuid`,
`?embed=1` and `/shared/achievement_cards/:uuid/og.png`. Public output uses the
owner's locale, masks private observations and is always `private, no-store`.
Dirty state, missing selection, disabled link or hidden Place/park yields 404.
City mosaic sharing requires an additional explicit opt-in.

Map fog uses all retained history, independent of plan/date range. It uses exact
resolution-9 boundaries at every zoom and marks cells first opened in the selected
period. It shows a calculating/updating/error status while background work runs.
Old point-radius/point-threshold and zoom-parent fog controls are removed.
The authenticated fog endpoint remains `/api/v1/maps/hexagons/fog`; it now returns
`h3_indexes`, `new_h3_indexes`, and metadata including status, resolution,
snapshot_id and pinned. Optional `snapshot_id` only accepts owned completed
snapshots. City deep links validate a pinned city/card before attaching that
snapshot to `/map?exploration_city=...&exploration_snapshot=...`.

## Geographic milestone artwork

The five milestones use orthographic globes with continent coastlines and a
coordinate grid. North/south keeps an equatorial separator and two tints;
east/west keeps the prime meridian and different tints; the four quarters keep
both separators and four tints even after completion. Unqualified regions remain
dark. Arctic/Antarctic views tilt toward their pole and highlight the actual
66.56° cap while retaining the surrounding globe.

Display-only `GlobeArtwork` reads precomputed local SVG paths. The same detail
layers survive fallback HTML, client hydration, the expanded card, public embeds
and OG PNG. Public artwork reads only the already masked public evidence. The
build/provenance recipe is in `lib/assets/achievement_collections/README.md`.
No achievement thresholds, source history or privacy rules change with artwork.

The optional silhouette `details` contract carries safe vector fill/stroke layers
above the missing-region mask, with consistent coordinate/stroke normalization.
Client validation rejects raw SVG markup, external paint servers and non-finite
attributes. Verification for this artwork change: 26 targeted Ruby examples,
745 JavaScript tests, all five private/public/OG variants and a JavaScript-free
fallback check on synthetic fixtures.

## Geodata and local runtime

Pilot cities: Berlin (OSM62422), Hamburg (62782), Dresden (191645). Pilot parks:
Harz (90584), Saxon Switzerland (1595534), Eifel (2345991). This catalog is neither
worldwide nor exhaustive for Germany. Unsupported boundaries are not synthesized.
The park-count thresholds remain 1/5/15 as the regional catalog grows.

Bundled checksummed OSM geometry and public-domain Natural Earth 5.1.2 require
PostGIS and the existing H3 binding. `tzf2` supplies offline IANA lookup using its
packaged boundary data; the gem lock includes macOS and Linux x86_64/aarch64.
OG rendering uses the existing `rsvg-convert`. Normal supported Docker builds
already use glibc-based Ruby images. Catalog build/update instructions and ODbL
attribution are in `lib/assets/achievement_collections/README.md`.

Geography installation is lazy and runs in the achievements queue, coalesced by
a Redis claim. The first city/point calculation can take longer while the local
geographic dataset is prepared. Completed datasets are immutable. Bump both
catalog and geography versions for boundary changes; retain stable subject codes.
Country/world areas are a union of country land, never a sum of overlapping cities.
`manifest.json` pins internal subject codes independently of replaceable OSM
relation IDs; a source replacement must preserve the existing card identity.

## Database and workers

Migrate normally. New exploration migrations preserve the dates/identities of
the original local foundation; collection migrations add selections, city pins,
current state, collectible snapshots and the event journal. Statement-level SQL
triggers cover bulk writes as well as model callbacks. Both schema-dumper hooks
restore triggers after `db:schema:load`; a clean-schema smoke test verifies this.

`Achievements::CollectionCheckJob` runs concrete temporal/geographic rules and
uses `Exploration::Rebuild` when cities are selected. `Exploration::RebuildJob`
serves map fog. Their five-minute refresh jobs recover dirty/unbuilt state;
claims expire after one hour. Existing Sidekiq `achievements`/`low_priority` queues
are reused. Inspect state `revision`, `published_revision`, `failed_at`,
`requested_at`, and the published dataset/snapshot and timezone data version when diagnosing stale output.
Do not manually mark a stale revision published.

The per-user calculation lock and final source/dataset/privacy fences discard
stale results. Point/Visit removal revokes new awards; journal rows remain.
Deleting a user cascades the new tables. Re-earning never creates another first
award event. Initial, dataset and timezone-data backfills are quiet. More than five new cards
produce one digest notification, while the unlock deck still contains each card.
Existing country award permanence and disputed-area rules are unchanged.

## Verification

Use an isolated PostGIS/Redis environment with synthetic fixtures. Run the
achievement/exploration/map-fog/request suites, Places merge/orphan suites and
transportation classifier suites, plus `npm test` and RuboCop on changed Ruby.
The complete app RSpec suite has not been required/run for this local scope;
the collection implementation passed a 419-example aggregate and 742 JavaScript tests. The globe artwork follow-up passes 26 targeted Ruby examples and the full 745-test JavaScript suite. Browser checks cover seven
collection views at 1280/375/320 px, expanded cards, light/dark, anonymous embed/OG
and city-map snapshot links. A separate schema-load database confirms bulk
invalidation survives fresh installation. No real traces or accounts are used.

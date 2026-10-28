# Map period statistics

Issue [#3257](https://github.com/Freika/dawarich/issues/3257). Implemented locally against `dev` at `13ec7af9e`, 2026-10-28; not published or deployed.

The MapLibre map keeps a compact count and GPS distance at the bottom right, above attribution. It survives dismissal of the loading badge and works with no Trip or generated Track. Dates, import scope, point invalidation and saved route settings refresh it. Changing km/mi reformats the original meters without a second aggregate query. Errors replace previous totals with an unavailable state; an empty period displays zero.

## Scope and distance rules

`GET /api/v1/maps/statistics?start_at=...&end_at=...&import_id=...` requires the normal API credential. Both bounds are required and inclusive. ISO 8601 offsets and Unix seconds identify exact instants; offsetless wall times use the account timezone through `ApiController`. There is no whole-day expansion or interpolation at either boundary. Malformed/reversed/out-of-supported-range values return 400. Authentication and pending-payment admission remain inherited from `ApiController`.

The response is `{ "points": 4, "distance_meters": 1358.205... }`, without coordinates or individual samples. `Maps::RangeStatistics` uses `user.scoped_points`, `Point.not_anomaly` and the canonical `Maps::PrivacyZoneMasker.within_sql`. Thus only the account's available, non-anomalous samples count, with the Lite window, owned import filter and private zones applied. Family overlays, manually added flights, camera bounds, layer visibility and Places tag filters do not change these account-history totals. The block's tooltip explains the own-account scope. Distance remains available with the Points/Tracks layers off.

Distance uses PostGIS `ST_Distance(geography, geography)`, as in `Distanceable`'s relation path, over original samples ordered by timestamp and ID. Windows are partitioned by tracker. Edges crossing a recorded `track_id` boundary or a gap greater than `minutes_between_routes * 60` contribute zero. These rules prevent joining separate routes/devices and retain recorded stationary-stop boundaries. The distance threshold is deliberately not introduced: current map/track generation ignores it for parity (`Tracks::Segmentation`). Masked samples remain in the ordering but neither endpoint may contribute: hiding one cannot connect its previously nonadjacent neighbours. Edges wholly outside the requested period do not contribute. Null legacy tracker IDs form one legacy stream, matching track generation.

Before automatic track generation has assigned IDs, samples use tracker/time-gap boundaries; this endpoint does not run stationary-stop detection, create Tracks/Trips or reclassify recording noise in a request. A later track rebuild may change boundaries and hence the total. It does not sum whole Track distances, simplified tile geometries, daily Stats or incomplete paginated client data. It does not infer travel through missing observations. Stored Track distances use other calculation/rounding paths, so small differences from their rounded display are possible. These are explicit choices for an exact selected-sample aggregate rather than a daily/Trip rollup.

Client conversion follows `DISTANCE_UNITS` (`1000` meters/km, `1609.34` meters/mi), retaining unrounded meters between switches. English, German, Catalan, Spanish, French, Polish and Chinese strings include count plural forms and an unavailable state.

## Load and cache behavior

The aggregate runs as one narrow SQL query with a five-second statement timeout, returning 503 on timeout. It reads no raw payloads and materializes no Point collection in Ruby or JavaScript. Successful aggregates cache for five minutes, keyed by account, exact range, import, point/track monthly revisions, plan window, time-gap setting and privacy fingerprint. HTTP responses use `no-store`; authorization always runs before aggregation. A late source mutation changes the revision rather than leaving a stale aggregate. Very large uncached periods can hit the timeout; choose a shorter period to retry.

`RangeStatistics` aborts a superseded fetch and checks a generation counter before updating the DOM. Disconnect cancels pending work. Point invalidations coalesce for 300 ms and use the current selected range. Presentation is independent from tile completion, the loading counter and map-data failure. The status uses polite/atomic live announcements and an `aria-busy` state. The mobile Settings panel covers the map; closing it reveals the persistent totals again.

## Verification

Separate local PostgreSQL/Redis containers, separate test/browser databases and localhost port 13257 were used with synthetic data only. No SSH, production data, push, PR, merge or deployment.

- 59 focused RSpec examples passed: range/API contract, adjacent boundaries, multiple routes, stored Track boundaries, trackers/anomalies, account timezone, empty/single-point ranges, import ownership, a real privacy zone, actual Cloud Lite window, source-mutation cache invalidation, invalid ranges, authentication and timeout. Existing point-tile tests are included. Swagger generation also passed 273 dry-run examples (not 273 executed endpoint checks).
- Full `npm test`: 740 passed. New tests cover original-meter conversion, empty/error states, ignored delayed responses, disconnect and invalidation coalescing.
- RuboCop: all four new Ruby/spec files pass. Biome formatting and `git diff --check` pass.
- Visible Chrome: desktop 1440×900 and mobile 390×844; loader dismissal, two synthetic routes, km→mi→km, account-local partial-period form while the browser uses America/New_York, empty period, rapid SPA switches with one delayed real response and German copy all pass. No page errors. Browser screenshots below; additional screenshots/results are in `tmp/screenshots/3257/` in the review worktree.

![Desktop selected-period statistics](screenshots/map-range-statistics/desktop.png)

![Mobile selected-period statistics](screenshots/map-range-statistics/mobile.png)

Full unfiltered RSpec, physical devices, production-volume query benchmarks and production/native-runtime acceptance were not run. API schema is versioned in `swagger/v1/swagger.yaml` and its executable rswag specification.

AFFiNE counterpart: [Dawarich — Map period statistics (#3257)](https://affine.dwri.xyz/workspace/c309ded7-e11e-4e72-ba6f-aec8a31a740b/QlMHWNjnS67Tq9_v1L-o9). Project overview: `EMGlXGqAqhVs7__YSQVHN`.

# Map request parity: Rails 1.16.0 vs Phoenix (2026-10-19)

Plan: `superpowers/plans/2026-10-18-phoenix-rails-visual-map-parity-plan.md`, task B3.

## Method

- **Bench and pages.** The parity bench from B2: one database, Rails 1.16.0 and Phoenix with separate Redis instances. `/map` opens on the last three days of demo data (`start_at`/`end_at` computed from the database) at 1440×900.
- **Recording** (`scripts/parity/map-actions.mjs`). It records the data requests each app's browser makes: fetch, XHR and document requests, with static assets excluded.
- **Mapping.** `scripts/parity/endpoints.json` maps them onto shared keys, for example `/api/v1/tiles/points/z/x/y.mvt` ↔ `/native/map/data/tiles/points/z/x/y`.
- **Server statements.** The `pg_stat_statements` delta is taken for each scenario. It includes the other app's background work, so read it as a rough figure.
- **Events.** They are published byte for byte the same into both apps' cable Redis: db 2, `dawarich_production:<stream>:<user gid>`. Each message carries a unique `updated_at`, because Phoenix drops repeated identical payloads.
- **Verdict.** A scenario passes when, for every key, Phoenix makes no more requests than Rails, and no Phoenix request is unmapped. The recent-point read is allowed, since it is listed in the divergence register.

## Results (final run, image with `fix/map-mount-config`)

| Scenario | What happens | Rails requests | Phoenix requests | Rails DB statements | Phoenix DB statements | Result |
|---|---|---:|---:|---:|---:|---|
| load | open `/map` | 18 | 9 | 294 | 282 | ok |
| idle | 60 s, nothing happens | 0 | 0 | 792 | 790 | ok |
| trip_idle | 60 s on `/trips/:id` | 0 | 0 | 892 | 783 | ok |
| track_burst | 30 `tracks` messages in 10 s | 180 | 20 | 1 506 | 601 | ok |
| point_burst | 5 `points` messages, 1 per second | 42 | 15 | 465 | 372 | ok |
| hidden_burst | `track_burst` in a tab reporting `hidden` | 180 | 0 | 1 489 | 270 | ok |
| pan_zoom | drag 300×150 px, then zoom in | 16 | 14 | 236 | 380 | ok |

Per key:

- **load.**
  - Tiles: Rails 6 point + 6 track tiles, Phoenix 2 + 2 (its map area is smaller until C1).
  - Called once by both apps: style, data bounds, achievement unlocks.
  - Rails only: one `/api/v1/settings` and one recalculation-status call. Phoenix has these in the page.
  - Phoenix only: one recent-point read.
- **track_burst.** Rails refreshes the track tiles about every second, 15 times at 12 tiles. Phoenix also refreshes at most once a second, but at 4 tiles.
- **point_burst.** Rails: 40 point tiles and 2 track tiles. Phoenix: 10 point tiles plus 5 recent-point reads (registered divergence).
- **hidden_burst.** Phoenix makes no requests. Headless Chromium cannot hide a tab, so the Rails figure is what a visible tab does. A real hidden Rails tab would also pause MapLibre's render loop.

## Fixed during B3

- **Double style fetch** (`fix/map-mount-config`, `320e8919c`). The server pushes `map:config` right after the LiveView connects. If the map was still loading at that moment, `update()` aborted and restarted initialization, so every `/map` load fetched the style twice. An unchanged configuration now keeps the running mount. Before the fix the load scenario counted 2 style requests on Phoenix against 1 on Rails; after it, 1 against 1.

## Found, for C1

- **Map position when the date range has no data.** For "today" in this fixture, data bounds return 404 on both apps. Rails then opens a zoomed-in view, while Phoenix shows the whole world (centre 0,0, zoom 2), so panning loads no data tiles.
- **End of the date range.** Rails ignores a live point timestamped 12:00 on the range's last day, while Phoenix accepts it. Rails' `pointMatchesActiveDateRange` probably reads the end date as midnight; check this in C1 before deciding.
- **Server cost of pan/zoom.** Phoenix makes slightly fewer tile requests than Rails but runs more statements: 380 against 236. Each native tile request also runs its admission and session setup.

## Not covered yet

- **`/s/:id` and `/family` scenarios.** The fixture has no shared link and no family; they come with D6 and D3.
- **Date-range change.** The two apps' date controls differ until C1. Changing the range by URL gives a fresh load, which the load scenario covers.
- **Real backfill.** Measured on the rcmap stack in A5 (`map-flood-20261019.md`): 0 requests on Phoenix. Rails 1.16.0 reclassifies with `update_column`, which broadcasts nothing.

# Tile-only map operations

The authenticated main map has one rendering path: Point and Track vector tiles. It does not fall back to loading a user's complete history when a tile or metadata request fails. Trip and shared-Trip maps continue to use their bounded day-route requests.

## Runtime dependencies

- PostgreSQL with PostGIS serves Point and Track vector tiles, exact edit overlays, and Visited Countries metadata.
- Redis carries cache epochs and Action Cable edit events. A Redis or broadcast failure after a committed edit is reported, but does not turn the successful mutation into an HTTP error.
- `public/maps/countries-v1.pmtiles` is bundled with the release. Serving it must preserve HTTP byte-range requests (`206 Partial Content` and `Accept-Ranges: bytes`). No outbound map-boundary service is required.

After installation, a self-hosted instance can render and edit the main map with outbound network access disabled. The selected basemap style may still have its own external dependency; use a locally hosted style when validating a fully offline deployment.

## Metrics and logs

The Prometheus names below use Yabeda's `dawarich_map` group prefix:

| Signal | Labels | Meaning |
| --- | --- | --- |
| `dawarich_map_point_moves_total` | `outcome=success|conflict|timeout` | Point-position command outcomes |
| `dawarich_map_point_move_duration_seconds` | `outcome` | End-to-end synchronous edit duration |
| `dawarich_map_point_move_lock_wait_seconds` | `outcome` | Point/Track row-lock wait |
| `dawarich_map_point_move_track_points` | none | Track size recalculated by an edit |
| `dawarich_map_point_move_track_segments` | none | TrackSegment count recalculated by an edit |
| `dawarich_map_tile_requests_total` | `layer=points|tracks`, `outcome` | Vector-tile HTTP outcomes |
| `dawarich_map_tile_request_duration_seconds` | `layer`, `outcome` | Tile request duration |
| `dawarich_map_post_commit_failures_total` | `operation=publish|broadcast` | Cache-epoch/publisher or Action Cable failures after commit |

Useful structured log events are `point_move.conflict`, `point_move.timeout`, `point_move.post_commit_failed`, `point_move.metrics_failed`, `track.post_commit_failed`, and `map.tile_request`. They contain outcome/operation/type identifiers but no coordinates or user-identifying metric labels.

Recommended initial alerts:

- any sustained increase in tile requests whose `outcome` is not `success`;
- p95 successful point-move duration above one second, or any `timeout` outcome;
- conflicts materially above the application's normal multi-session edit rate;
- any increase in `post_commit_failures_total`.

## Failure handling

- Point or Track tile failure: the map keeps the current view and exposes Retry. Retrying refreshes the affected source with a new cache-buster; it never starts a paginated Point/Track download.
- Visited Countries metadata or PMTiles failure: the layer exposes Retry and leaves the rest of the map usable.
- Edit timeout or validation failure: Point, Track, TrackSegments, and revisions roll back together; the exact pre-drag overlay is restored.
- Revision conflict: the API returns the winning canonical Point and Track in the `409` response, and the editor reconciles without a second fetch.
- Post-commit cache/publication failure: the edit remains successful. Investigate the structured event and metric, restore Redis/Action Cable, then refresh the map; tile URLs also include database-derived revision material for moved Tracks.

## Release and rollback checklist

Before broad release:

1. Run the Point-move benchmark from `docs/point-move-performance.md`; representative Tracks must remain below the one-second p95 target and every supported size below the three-second hard budget.
2. Run the PMTiles verifier and confirm the archive is deterministic, no larger than 8 MiB, and answers a byte-range request with `206`.
3. Run the browser suite against a million-Point history. Confirm there are no `/api/v1/points` or `/api/v1/tracks` main-map history requests, including after range and import changes.
4. Exercise editing, conflicts, retries, reduced motion, Visited Countries, Trip, and shared-Trip on the Cloud canary and on one representative self-hosted installation.
5. Observe the metrics above during the soak and inspect logs for post-commit failures.

Rollback the release as a unit if these checks fail. Do not introduce or enable a runtime classic-renderer switch: that path can turn a tile incident into an unbounded database and browser load. The additive revision columns, composite edit endpoint, metadata endpoint, and bundled PMTiles asset are safe to leave in place while rolling back the UI release.

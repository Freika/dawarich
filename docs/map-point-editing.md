# Map point editing

The MapLibre editor uses `MapEditor` for the editable GeoJSON overlay and
`Points::Move` for the canonical server mutation. The point, its track path,
segments, and their revisions are committed together. The response returns
canonical geometry and revisions so the editor can replace its drag preview.

## Rendering invariants

- An edited track with segments is drawn by `editable-track-segments`. Only
  edges outside those segments remain in `editable-track-line`; the full base
  path is excluded so it cannot cover segment colors.
- When editing starts, the previously selected track overlay is cleared. The
  edited track is excluded from vector tiles, including while its full geometry
  is loading after a drag starts on a tile point. The editor overlay is the
  single visible copy of that track during the edit.
- Point edit history and undo/redo live in the map's bottom-right control area,
  clear of the left sidebar. Editable points use a grab cursor on hover.
- A merged vector-tile marker zooms toward its centroid until one point can
  be selected. Tile attributes from a merged cell may describe different
  members, so Delete is available only on singleton markers. If points remain
  merged at maximum zoom, the info panel shows their count without Delete.
  When a track crosses a point, the point selection takes priority because
  MapLibre dispatches the click to both layers.

## Saving and country updates

`Points::Move` locks the point and track, checks revisions, assigns the new
position and country, and recalculates the track in a transaction with a hard
time budget. It queries the history scope's visited countries before and after
the mutation only when the point's country fields change. Moves within the
same country return `visited_countries: nil` and avoid the full history scan.
If a visited-country list changes, the response includes the new list.

The map shows a generic failure toast for non-conflict API errors. When
investigating a failure, inspect the PATCH response to
`/api/v1/points/:id/position` and the `point_move.map` metrics. A 422 with
`recalculation_timeout` means the transaction exceeded its budget; a 409
`stale_edit` contains the latest canonical point and track state.

## Verification

Run the service and request specs with `bundle exec rspec
spec/services/points/move_spec.rb spec/requests/api/v1/points/positions_spec.rb`.
Run browser regressions against a seeded development server with
`npx playwright test e2e/map_point_editing.spec.js
e2e/map_point_selection.spec.js --project=chromium --workers=1`.
The browser tests exercise the rendered MapLibre layers, selected-track
cleanup, history placement, cursor, and a real mouse drag. Synthetic map
features keep the browser tests deterministic; Ruby specs cover the move API.

The shared AFFiNE knowledge-base counterpart for this workflow should be
linked here when the workspace search service is available.

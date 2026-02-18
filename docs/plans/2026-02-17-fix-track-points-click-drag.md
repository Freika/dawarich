# Fix Track Points Click/Drag Behavior Implementation Plan

Created: 2026-02-17
Status: VERIFIED
Approved: Yes
Iterations: 0
Worktree: No

> **Status Lifecycle:** PENDING → COMPLETE → VERIFIED
> **Iterations:** Tracks implement→verify cycles (incremented by verify phase)
>
> - PENDING: Initial state, awaiting implementation
> - COMPLETE: All tasks implemented
> - VERIFIED: All checks passed
>
> **Approval Gate:** Implementation CANNOT proceed until `Approved: Yes`
> **Worktree:** Set at plan creation (from dispatcher). `Yes` uses git worktree isolation; `No` works directly on current branch (default)

## Summary

**Goal:** Fix track points layer so clicking a point shows its info (timestamp, altitude, battery, speed) in the info panel — matching the default points layer behavior — and only dragging actually updates the point position.

**Architecture:** The fix involves three areas: (1) Add click-vs-drag distinction in `TrackPointsLayer` by tracking whether `mousemove` fires between `mousedown` and `mouseup`, with a `justDragged` flag to suppress click events after drags. (2) Register a click event handler on the `track-points` layer that shows point info via the existing `showInfo` panel. (3) Update event priority checks so that clicking a track point doesn't trigger track selection clearing or track info panel overwrite.

**Tech Stack:** JavaScript (Stimulus + MapLibre GL JS)

## Scope

### In Scope

- Add click-vs-drag distinction in `TrackPointsLayer` so clicking doesn't trigger position update
- Register a click handler for `track-points` layer that displays point info in the info panel
- Include all relevant point properties (altitude, battery, velocity, accuracy, country_name) in `TrackPointsLayer.pointsToGeoJSON`
- Add `track-points` priority check in `handleTrackClick` (prevent track info overwriting point info)
- Add `track-points` check in map-level click handler (prevent `clearTrackSelection` from destroying track points layer on point click)
- Ensure dragging still works correctly (position update + backend track recalc)

### Out of Scope

- Fixing the same click-vs-drag issue in the default `PointsLayer` (the default layer already has a separate `click` handler that shows info on click; the unnecessary PATCH call on click is a pre-existing bug to address separately)
- Fixing the `originalCoords` revert-on-error bug (pre-existing in both `PointsLayer` and `TrackPointsLayer` — `originalCoords` may be mutated by `onMouseMove` before `onMouseUp` reads it; to fix properly requires copying coords in `onMouseDown`)
- Route drawing changes
- Any backend changes (backend track recalculation already works via `Tracks::RecalculateJob`)
- Map v1 (Leaflet) changes

## Prerequisites

- None — all infrastructure already exists

## Context for Implementer

- **Patterns to follow:** The default `PointsLayer` at `app/javascript/maps_maplibre/layers/points_layer.js` and `handlePointClick` at `app/javascript/controllers/maps/maplibre/event_handlers.js:29-44` demonstrate the desired behavior
- **Conventions:** MapLibre event handlers are registered in `layer_manager.js:75-120` for standard layers; track points layer is dynamically imported in `event_handlers.js:770-801`
- **Key files:**
  - `app/javascript/maps_maplibre/layers/track_points_layer.js` — The track points layer with broken click/drag (261 lines)
  - `app/javascript/controllers/maps/maplibre/event_handlers.js` — Event handlers including `handlePointClick` and `_toggleTrackPoints` (1087 lines)
  - `app/javascript/controllers/maps/maplibre/layer_manager.js` — Layer setup including event handler registration and map-level click handler (lines 75-165)
  - `app/javascript/maps_maplibre/layers/points_layer.js` — Reference implementation of default points layer (265 lines)
  - `app/javascript/maps_maplibre/utils/geojson_transformers.js` — `pointsToGeoJSON` utility showing which properties to include
- **Gotchas:**
  - In MapLibre, `click` events fire AFTER `mousedown`+`mouseup` if mouse didn't move. But the current `onMouseDown` immediately sets `isDragging = true` and `onMouseUp` always calls `updatePointPosition`, so every click triggers a position update
  - **MapLibre click threshold:** MapLibre fires `click` even after small mouse movements (non-zero threshold). After a drag, use a `justDragged` flag to suppress the subsequent click event
  - **Event priority cascading:** When clicking a track point, three handlers fire: (1) `track-points` click handler, (2) `tracks` click handler (point sits on top of track line), (3) map-level click handler. Both (2) and (3) must check for `track-points` features to avoid overwriting/destroying the point info
  - The track points layer is dynamically imported and registered when the "Show Points" toggle is enabled — click handler registration must happen at load time, not during `setupLayerEventHandlers`
  - The `source._data` pattern is used to directly access and modify GeoJSON data (standard MapLibre pattern in this codebase)
  - **Bound handler references:** Click handler must be stored as a bound method reference (e.g., `this._handleTrackPointClick = this.handleTrackPointClick.bind(this)`) so the same reference can be used for both `map.on()` and `map.off()` during cleanup
- **Domain context:** When a user clicks a track, the info panel shows track details including a "Show Points" toggle. Enabling it loads the track's points as green circles. Currently, clicking any of these green points triggers a position update API call. The desired behavior is: click = show info, drag = update position.

## Progress Tracking

**MANDATORY: Update this checklist as tasks complete. Change `[ ]` to `[x]`.**

- [x] Task 1: Add click-vs-drag distinction to TrackPointsLayer
- [x] Task 2: Register track point click handler, add event priority guards, and include full properties in GeoJSON

**Total Tasks:** 2 | **Completed:** 2 | **Remaining:** 0

## Implementation Tasks

### Task 1: Add click-vs-drag distinction to TrackPointsLayer

**Objective:** Modify `TrackPointsLayer` to distinguish between click (no mouse movement) and drag (mouse moved) so that `onMouseUp` only triggers position update when the user actually dragged the point. Also add a `justDragged` flag to suppress MapLibre `click` events that fire after a drag.

**Dependencies:** None

**Files:**

- Modify: `app/javascript/maps_maplibre/layers/track_points_layer.js`

**Key Decisions / Notes:**

- Add `this.hasMoved = false` property, set to `false` in `onMouseDown`, set to `true` in `onMouseMove`
- In `onMouseUp`: only call `updatePointPosition` if `this.hasMoved` is true; otherwise clean up drag state silently
- Add `this.justDragged = false` property. Set to `true` in `onMouseUp` when `hasMoved` was true (actual drag). Reset to `false` after a short timeout (e.g., `setTimeout(() => { this.justDragged = false }, 0)`) to ensure the subsequent MapLibre `click` event can check it
- Keep cursor as `move` on mouseenter (indicates draggable), switch to `grabbing` only when actual mouse movement occurs in `onMouseMove`
- The `justDragged` flag will be checked by the click handler added in Task 2

**Definition of Done:**

- [ ] Clicking a track point (mousedown + mouseup without mousemove) does NOT trigger `updatePointPosition` API call
- [ ] Dragging a track point (mousedown + mousemove + mouseup) still triggers `updatePointPosition` and shows success toast
- [ ] `justDragged` flag is set to `true` after a real drag and resets asynchronously
- [ ] No console errors when clicking or dragging track points

**Verify:**

- Manual: Enable a track, toggle "Show Points", click a green point → no "Point updated" toast, no network request to PATCH `/api/v1/points/:id`
- Manual: Drag a green point → "Point updated. Track will be recalculated." toast appears, PATCH request sent

### Task 2: Register track point click handler, add event priority guards, and include full properties in GeoJSON

**Objective:** (a) Add a `handleTrackPointClick` method to `EventHandlers` that displays point info in the info panel — matching `handlePointClick`. (b) Register a MapLibre `click` handler on the `track-points` layer when the layer is loaded, with cleanup on toggle-off. (c) Update `TrackPointsLayer.pointsToGeoJSON` to include all relevant properties. (d) Add `track-points` priority check in `handleTrackClick` so it doesn't overwrite point info. (e) Add `track-points` check in the map-level click handler in `layer_manager.js` so `clearTrackSelection` doesn't destroy the track points layer when a track point is clicked.

**Dependencies:** Task 1 (click-vs-drag distinction must work first so clicks aren't also triggering position updates)

**Files:**

- Modify: `app/javascript/controllers/maps/maplibre/event_handlers.js` (add `handleTrackPointClick` method, register/cleanup handler in `_toggleTrackPoints`/`_clearTrackPointsLayer`, add priority check in `handleTrackClick`)
- Modify: `app/javascript/controllers/maps/maplibre/layer_manager.js` (add `track-points` check in map-level click handler at line 152-165)
- Modify: `app/javascript/maps_maplibre/layers/track_points_layer.js` (update `pointsToGeoJSON` to include all properties)

**Key Decisions / Notes:**

- **Click handler:** `handleTrackPointClick` reuses the same info display format as `handlePointClick` (timestamp, battery, altitude, speed) with title "Track Point". It checks `trackPointsLayer.justDragged` and returns early if true (suppresses click after drag).
- **Handler binding:** Create bound reference `this._handleTrackPointClick = this.handleTrackPointClick.bind(this)` in the EventHandlers constructor. Register with `this.map.on('click', 'track-points', this._handleTrackPointClick)` in `_toggleTrackPoints`. Clean up with `this.map.off('click', 'track-points', this._handleTrackPointClick)` in `_clearTrackPointsLayer`.
- **Priority in handleTrackClick:** Add after existing `points` and `routes-hit` checks (around line 469): check if `track-points` layer exists and has features at click point → return early if so. Pattern: `if (this.map.getLayer('track-points')) { const tpFeatures = this.map.queryRenderedFeatures(e.point, { layers: ['track-points'] }); if (tpFeatures.length > 0) return; }`
- **Map-level click guard:** In `layer_manager.js:152-165`, add a `track-points` layer check alongside the existing `tracks` check. If clicking a track point, do NOT call `clearTrackSelection()`. Pattern: also query `track-points` features and skip `clearTrackSelection` if any are found.
- **GeoJSON properties:** Update `pointsToGeoJSON` to include: `altitude`, `battery`, `velocity`, `accuracy`, `country_name` (matching `geojson_transformers.js:pointsToGeoJSON`)

**Definition of Done:**

- [ ] Clicking a track point shows info panel with "Track Point" title, showing timestamp, battery (if present), altitude (if present), speed (if present)
- [ ] Info panel content matches the format of default point clicks
- [ ] `pointsToGeoJSON` includes altitude, battery, velocity, accuracy, country_name properties
- [ ] Click handler is properly cleaned up when "Show Points" is toggled off (verified via `map.off`)
- [ ] No duplicate click handlers after toggling Show Points on/off multiple times
- [ ] `handleTrackClick` does NOT overwrite track point info when clicking a track point (priority check works)
- [ ] Map-level click handler does NOT call `clearTrackSelection` when clicking a track point (layer check works)
- [ ] After a drag, the `click` event does NOT show the info panel (justDragged guard works)

**Verify:**

- Manual: Enable a track, toggle "Show Points", click a green point → info panel shows "Track Point" with timestamp and available properties (NOT the track info panel)
- Manual: Toggle "Show Points" off and on again, click a point → still shows info correctly (no duplicate handlers)
- Manual: Drag a point → only "Point updated" toast, no info panel shown
- Manual: Click empty area of map while track points are shown → track points remain visible (not cleared by map-level handler)

## Testing Strategy

- **Manual verification:** Primary testing approach — the behavior is UI-interactive (click vs drag on map)
- **Regression:** Verify that regular points layer click behavior is unaffected, and that track point dragging still works end-to-end (point moves visually, API call succeeds, toast appears)
- **Event cascade testing:** Verify clicking a track point doesn't trigger track info panel or clear track selection

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| MapLibre `click` fires after small drag movements | Medium | Medium | `justDragged` flag set in `onMouseUp` when `hasMoved` was true, checked in click handler; reset asynchronously via `setTimeout(..., 0)` |
| `handleTrackClick` overwrites track point info | High | High | Add `track-points` layer priority check in `handleTrackClick` before processing (same pattern as existing `points` and `routes-hit` checks) |
| Map-level click handler clears track points layer | High | High | Add `track-points` feature query in map-level click handler; skip `clearTrackSelection` if track point features found at click point |
| Stale click handlers after toggle on/off | Medium | Low | Store bound handler reference on EventHandlers instance; call `map.off()` with same reference in `_clearTrackPointsLayer` |
| Missing properties in GeoJSON causes empty info fields | Low | Low | Use conditional rendering (same pattern as `handlePointClick`) — only show fields when value is truthy |

## Open Questions

- None — the approach is clear from the existing codebase patterns.

### Known Pre-existing Issues (Not Addressed)

- **Default PointsLayer click-vs-drag:** The default `PointsLayer` has the same bug where clicking triggers an unnecessary PATCH API call (no-op position update). The click handler shows info correctly because it's a separate MapLibre `click` event, but the drag machinery still fires unnecessarily. This should be addressed in a follow-up.
- **originalCoords revert-on-error:** Both `PointsLayer` and `TrackPointsLayer` read `originalCoords` from `this.draggedFeature.geometry.coordinates` in `onMouseUp`, but `onMouseMove` may have already mutated that array by reference. Error reversion may be a no-op. Fixing requires copying coordinates in `onMouseDown`.

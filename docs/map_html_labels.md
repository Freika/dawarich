# Map labels with emoji

Place, area, visit and family member names use `HtmlLabelManager` DOM markers,
including the standalone family map. MapLibre's SDF fontstack cannot render
native color emoji. Marker text uses `textContent`, so names remain plain text.

Each layer synchronizes labels when its GeoJSON changes, propagates visibility,
and clears markers during removal. `LayerManager.clearLayerReferences()` removes
these layers before rebuilding a style. The standalone family controller clears
labels before removing its map, and receives the member display name from
`UserFamily.latest_location_for_family`. Style restoration reloads enabled family
locations after rebuilding the map layers. The standalone family map reserves
a minimum height on mobile so its labels remain visible. Family hover popups and
MVT event subscriptions retain their existing behavior.

Visit status filters apply to label visibility. Timeline day highlighting and
entry hover use a feature opacity resolver and the Marker opacity API, so
MapLibre movement/occlusion updates do not reset highlighting. This also applies
after data refresh. Clearing labels resets their filter and opacity resolver,
so removed layers cannot leave stale DOM state behind.

DOM labels do not participate in MapLibre symbol collision detection or sort
keys. Dense labels can overlap; a large visit range also creates more DOM nodes.
The map-label styles use native emoji fonts and ignore pointer events.

Verification:

- `bundle exec rspec spec/regressions/issue_2365_spec.rb spec/requests/map/maplibre_spec.rb`
- `npm test`
- `npx --no-install biome check app/javascript`
- Playwright: check names with emoji, visit status filters and timeline opacity,
  family hover popups, style rebuilding and teardown on desktop and mobile.

References: issue #2365 and PR #2617. Shared AFFiNE synchronization is pending:
this implementation session permits network access only to localhost.

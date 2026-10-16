# Native map browser reconciliation after the Rails 1.16 sync

Native map chrome refreshes current account and Family admission on every event. It publishes `map:config` only when that configuration changes. Publishing unchanged configuration in response to `map:ready` creates a ready/config feedback loop: map reads are aborted, selected geometry disappears and search, rectangle selection, point dragging and timeline actions become unreliable. Family membership and entitlement changes must still publish their changed configuration.

Point selection keeps the Rails behavior through the native map hook. An aggregate marker zooms by two levels up to maximum zoom. At maximum zoom it shows the localized overlapping-points explanation and closes any previous point deletion target. An individual point displays coordinates and opens the scoped native address/delete drawer. Point hits take priority over a route underneath. Both tile aggregate counters (`count` and `point_count`) must identify a single point before dragging is admitted.

Opening editor geometry clears the selected timeline route first, preventing duplicate stale route edges. Editor points advertise the grab cursor; history, segment colors, uncovered edges and tile exclusions retain their existing native owners.

The app-owned browser specifications now resolve the hook through its owning LiveView. They retain their segment, geometry, mouse, history, selection and deletion-safety assertions. Native layer labels include their explanatory descriptions; Fog remains a named group. Timeline viewport checks select the map controls navigation. Mobile area tools await map readiness before interaction. Trip previews are admitted only after their cards enter the viewport, including when the trip filters place every card below the initial fold.

Verification witnesses:

- `app-phoenix/test/dawarich_web/native_map_config_stability_test.exs`
- Existing `sync1160_map_shell_test.exs` Family membership/admission coverage
- `spec/javascript/phoenix_m6_host_point_selection_test.mjs`
- `spec/javascript/phoenix_m6_host_editing_test.mjs`
- App-owned `e2e/map_point_editing.spec.js` and `e2e/map_point_selection.spec.js`
- Assigned external browser specs for map layers, search, rectangle selection, timeline, replay, conflicts, area dialogs and trip previews

Use the controller-assigned targeted runner and private environment. The controller E2 report records paired commits, failing-first and mutation logs, targeted results and the final standalone browser lane. Targeted checks do not establish full release acceptance; unrelated track failures remain separate.

Shared knowledge counterpart: AFFiNE, `Dawarich — Rails 1.16.0 native shell sync`.

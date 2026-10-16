# Rails 1.16.0 native shell sync

T5 ports trip filtering, auth/root navigation, map panels, Unicode map labels and notices. It uses native LiveViews, scoped contexts and named browser hooks; Rails HTML recordings are not refreshed.

Trip queries search names, decoded rich descriptions, notes and itinerary records without duplicating trips. Search escapes SQL wildcards, removes NUL and uses Rails' 100-codepoint limit. Periods overlap in the actor's timezone; country selection uses exact JSON membership. Sorts include deterministic id ties. Options come from all owned trips, and family pagination stays independent. The routed index is `DawarichWeb.TripsLive.NativeIndex`; `NativeTripsLive.Index` is an older component.

Root redirects guests to sign-in and authenticated users to the preferred native map. Locale and unconsumed flash survive that redirect. Auth forms omit self links and registration omits irrelevant recovery links. Rails sign-in still has a relevant unlock-email link. Direct sign-in locale navigation admits only one supported locale parameter.

Family controls have a separate panel and F shortcut, available with current membership and feature access. The existing family overlay already restores geometry after style changes. DOM labels extend the existing places renderer to visits, area centers and family names, keeping safe text, filtering, opacity, visibility and teardown. Nullable family addresses are consumed from the scoped family projection; that projection owns reverse-geocoding and privacy rules.

Points visibility controls effective anomaly visibility while retaining the anomaly preference. Browser preferences are scoped to the user namespace and survive document reloads. Fog modes stay grouped, visit filters and place tags remain native, and flights require AirTrail configuration. Scratch maps request `/maps/countries-v3.pmtiles`; the public-files boundary and existing Docker public/maps copy serve the archive.

Notice text permits pointer events to reach underlying map controls; links and dismiss actions remain interactive. Messages wrap within the viewport. Native CSS enforces the hidden attribute even when modal styles specify grid display.

The Rails build oracle refreshes the locale, asset, importmap and normalized-manifest byte pins. CSS checks retain deterministic repeated output and Docker class-source closure rather than a historical checksum that changes whenever native classes change.

The Rails sync merge already supplies all seven locale source deltas. Native i18n is rebuilt from those sources. No-fallback checks cover the new keys and real interpolation bindings. A real Rails oracle confirms Polish country-ribbon counts use the simple backend's one/other categories despite additional few/many source leaves; this port preserves that behavior.

## Verification and integration

Named witnesses are `sync1160_index_test.exs`, `sync1160_trips_live_test.exs`, `sync1160_auth_shell_test.exs`, `sync1160_map_shell_test.exs`, `sync1160_i18n_test.exs` and `test/client/sync1160_map_labels_test.mjs`. Standalone browser successors are in the E2E repository at `native/sync1160-shell.spec.js`. Controller evidence records the paired commits, private runner logs, source mutations and final gate.

T2 supplies `DawarichWeb.InsightsRoutes`, `DawarichWeb.InsightsRedirect` and `InsightsYearMap`. Its route/alias/shared-hook integration is wired together: route previews and their JSON alias bypass document conversion, stats index/year redirect to insights, and the month route stays native. Preview admission reads the configured self-hosted mode when no layout assign is present and retains the Cloud data window. Authenticated route previews accept JSON and the `.json` suffix through the same plug, outside document conversion. Legacy year redirects admit four digits and normalize them numerically; malformed suffixes refuse locally. Request tests and the compiled route ledger cover these boundaries. Navbar entries already consolidate on insights. T3 supplies the nullable family address projection; T1 supplies the version-three reference archive.

This is implementation documentation, not release or production-serving acceptance.

Flash parity readers use an explicit presentation-only comparator: classes within the flash may differ, while severity, role, escaped text, dismissal controls, stream targets and all surrounding markup stay checked. Retained JS/hook consumers use IDs or roles and do not select these fragments by their presentation classes. Native click-through and wrapping remain the shell contract.

The scoped Stats cache race checks remain on the native month route after index/year consolidation. Index/year interaction, totals, places, history, recalculation, entitlement, private-state and expiry checks now exercise insights; scoped year queries retain their data contracts. Q06/Q07 redirect rows are refreshed by the Rails parity recorder, with status, flash and jobs unchanged. Its focused NULL-settings capture also records the stats index redirect for SQL NULL, JSON null and empty settings; the native successor follows it to insights while retaining the public/API/PNG and unchanged-settings assertions. The new map hook has an explicit 2 KiB eager cap; its engine remains lazy.

The reader reconciliation adds the boundary registry witness without changing the historical census. The integration also reconciles T1's FRB-S1160-BOUNDARY-FOLLOWUPS and ED-S1160-BOUNDARY-FOLLOWUPS entries, and records the preserved empty-cities yearly-digest quirk as DRB-S1160-EMPTY-CITIES. Cloud provisioning readiness for heavy release jobs remains an owner decision; lifecycle admission is unchanged.

The first integrated fix gate completed all partitions with 11,038 tests and eight failures: seven stale stats route/status/recording callers and the pending Cloud provisioning readiness case. Exact route inventories and source-recorded NULL settings now cover those caller successors. Their targeted packet passes; final all-partition acceptance still requires the controller's replacement-gate authorization. The original gate result remains in the controller report.

## Browser auth setup readiness

A successful sign-in redirect can render the map's Settings button before its LiveView has connected. The shared E2E panel helper must await `[data-phx-main].phx-connected` before clicking; otherwise the initial click can be lost and auth setup times out waiting for the panel close control. Waiting for `/map/v2` alone does not establish event readiness. Keep the native globe form submission, unchecked assertion, panel close and saved-session assertions.

The native Tools control is `map-button-tools`; the helper's historical `create` alias maps to that panel. The browser witness `native/map-panel-readiness.spec.js` delays the LiveView WebSocket, opens Settings through the shared helper, verifies the globe preference after reload and checks the Tools alias. Removing the connection wait or restoring the old `map-button-create` selector must fail it. App runtime and lifecycle admission are unchanged.


## Family and realtime browser acceptance

Family visibility and member controls belong to `panel=family`, opened through `map-button-family`; Layers retains the other map layers. Browser successors retain member timestamps, history colors, centering, empty states and saved visibility. The scoped helper opens the panel only after the native connection is ready.

When a point invalidation interrupts live mode's initial baseline read, the pending delivery must survive the replacement refresh. The recent-point owner cancels the old baseline and preserves its previous identity before refreshing, then renders the latest admitted row. Other invalidation kinds still establish a baseline without manufacturing a new marker. Disabling live mode and changing ranges retain their cancellation and clearing boundaries.

The deterministic witness is `native live marker retains a point arriving during the enabling baseline` in `spec/javascript/phoenix_m6_host_recent_test.mjs`. Its named mutation removes delivery preparation before reconnect. Existing marker, duplicate suppression, disabled-state and late-read tests remain required. This corrects a native baseline race; Rails already renders admitted point broadcasts directly in `app/javascript/maps_maplibre/utils/realtime_points.js`.

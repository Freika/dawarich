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

T2 supplies `DawarichWeb.InsightsRoutes`, `DawarichWeb.InsightsRedirect` and `InsightsYearMap`. Its route/alias/shared-hook integration must land together: route previews and their JSON alias bypass document conversion, stats index/year redirect to insights, and the month route stays native. The controller report contains T5's six-file integration patch, including route-ledger and route-test updates, for application after T2's modules land. Navbar entries already consolidate on insights. T3 supplies the nullable family address projection; T1 supplies the version-three reference archive.

This is implementation documentation, not release or production-serving acceptance.

# Experimental map matching administration

The native admin instance settings page has an **Experimental features** section generated from `Dawarich.Experimental.entries/0`. Map matching is the first registered experiment. The page and its connection-test action require a self-hosted administrator; unauthorized users receive the Rails authorization refusal.

`atlas_url` configures the HTTP(S) Atlas service. `map_matching_enabled` enables the instance-wide experiment. `map_matching_shadow_mode` processes eligible tracks while retaining the original display. Environment values `ATLAS_URL`, `MAP_MATCHING_ENABLED` and `MAP_MATCHING_SHADOW_MODE` lock their fields and display their variable names. An Atlas URL is required when enabling map matching. URL validation and persistence use the existing instance settings input and writes.

`POST /admin/settings/test_map_matching` requires the authenticated session and CSRF token. It tests the saved or environment-pinned URL using the Atlas connection-test client, and redirects back to the experimental section with version/revision or an error code. A failed health check is advisory and does not prevent saving settings. Save URL edits before testing the connection.

The privacy notice explains that coordinates, timestamps and GPS accuracy are sent to the configured Atlas service. The interactive Berlin demo contains synthetic coordinates and a prerecorded matched polyline, independent of users' traces and the configured Atlas endpoint. It mounts the shared `map_matching_demo_controller.js` through the native import map and switches emphasis between original and matched paths.

New copy is translated in all seven locales. `test/dawarich_web/admin/experimental_section_test.exs` covers pinned controls, prerequisite validation, connection responses, refusal, CSRF and locale availability. `spec/javascript/map_matching_demo_controller_test.mjs` covers the demo geometry and switch. Existing admin page parity tests compare retained sections after isolating the added experimental navigation; their original fixtures remain unchanged.

Selected-track map controls and rendering are separate Task 11 work and are not implemented here. The controller allocation and detailed verification evidence are recorded outside the repository in the Task 10 implementation report.

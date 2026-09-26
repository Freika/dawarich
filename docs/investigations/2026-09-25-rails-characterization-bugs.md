# Rails defects found during Phoenix characterization and C2

Date: 2026-09-25. Updated: 2026-09-26. Initial base: local `dev` at `f73605cb9`. The places fix (`fix/places-direct-open`) is merged into `feat/phoenix-port`.

| Defect | Cause | Rails repair |
|---|---|---|
| `/stats/:year/:month` returns 500 without a stat | The month partial dereferences a missing `Stat`. | Render the existing localized empty state when the stat is absent. |
| Preheating creates an unfinished yearly digest | `Cache::PreheatInsightsDigests` selects the current year. | Select completed years; hide already persisted current-year digests from the web and API lists. |
| Release 1.0.2 transportation backfill enqueues nothing | Migration `20260125100000` references the removed `TransportationModes::BackfillJob` and filters integer `imports.source` against text values. | Keep released history intact. A new migration queues a batched walker for tracks missing segments or having an unknown mode, and queues import backfills using the five integer enum values. The new walker excludes deleted users and uses the current `ReclassifyTrackJob`. It does not invoke the fleet-wide job reserved for a manual post-anchor run. |
| Track-split defaults disagree | The `users.settings` column still defaults to 1000 m and 60 min while SafeSettings and the map panel use 500 m and 30 min. | A new migration changes the column default for new users; existing saved settings remain untouched. |
| Map “Reset to defaults” can lose its save and retain miles | The controller reloads before the asynchronous save finishes, and the reset payload lacks `distance_unit`. | Queue the reset after earlier saves, await it before reload, and explicitly reset distance and nested map filters. |
| Manual image build publishes `latest` | `workflow_dispatch` has no prerelease flag and takes the stable-release tag branch. | Add `latest` only for release events. |
| Direct `/places/:id` opens a bare fragment and an HTML Notes save fails | The route always renders a Turbo-frame body without a map host; `PlacesController#update` handles only Turbo Stream. The map has no place deep link or detail drawer host. | On `fix/places-direct-open`, redirect direct GET and HTML PATCH to `/map/v2?place_id=<id>`, keep `Turbo-Frame: place-drawer` GET and Turbo Stream PATCH, and make the map host the drawer at the place coordinates. A place marker opens the same drawer. Scope the deep link to the current user's places. |
| Sign-out no longer shows "Signed out successfully." | Since achievements shipped without a feature flag (`48f662f00`, unreleased on `dev`), the three Turbo-tracked achievement stylesheets are linked only for signed-in users. The redirect after sign-out renders `/` without them, Turbo sees a tracked-asset mismatch and reloads, and the reload has no flash. | On `fix/signout-flash-turbo-reload` (merged into `feat/phoenix-port`), both layouts link the achievement stylesheets for every visitor; a request spec requires identical Turbo-tracked head elements for visitors and signed-in users. |

## Place deep-link contract

`/places/:id` with `Turbo-Frame: place-drawer` remains the drawer fragment. A normal browser GET redirects to `/map/v2?place_id=<id>`; the map renders a `place-drawer` Turbo frame pointing at that fragment, centers on the place, and opens the places layer for that session. An HTML PATCH redirects there after success or validation failure, so a direct Notes submission cannot produce `UnknownFormat`. Place ownership is checked before either redirect or map rendering. The drawer's Notes field uses a distinct element ID because the map's place creation modal also contains a `place[note]` field.

The drawer's Edit button opens the map's place editor, which changes the name, tags and note; it replaces the popup a place marker used to show. A Turbo Stream PATCH, from Notes or from the editor, updates the contents of the `place-drawer` frame instead of replacing the frame, so Close and later marker clicks keep working after a save. The drawer's Delete button sends `DELETE /places/:id` from the frame (it used to post to `/places.<id>`, which has no route); the frame request gets a Turbo Stream flash instead of the places-index redirect, and on success the drawer closes and the place's marker is removed from the places layer. The map controller exposes the deep-linked place as `@drawer_place`, not `@place`, because the creation modal's `form_with scope: :place` would otherwise prefill its fields with that place.

## Ecto port consequence

C2 ports current Rails behavior, including the released 1.0.2 migration's absent backfill. Do not edit or reinterpret that migration in the Ecto port. C2 needs counterparts for the new repair and track-split default migrations after these Rails branches enter the integration branch. C3 must port the repair's job chain; C4 should verify a 1.0.1 snapshot through both migrators with row-level checks after the jobs complete. Neither change belongs in C2's owned worktree during this handoff.

The two migration branches both change `db/schema.rb`. When combined, regenerate it at version `2026_09_25_100100` with the `500`/`30` column default.

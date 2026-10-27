# Map visit drafts

Map v2 uses `maps_maplibre/utils/visit_draft.js` to turn recorded Points into a Visit draft. It sorts Points by timestamp, splits stays when a gap exceeds the user's merge threshold, and uses the latest stay. The draft's location is the median latitude and longitude, and its times are the first and last Point timestamps. Several stays produce a warning.

Create Visit uses an active selection immediately. Without a selection, a map click opens the form with the current time and one hour later, then fetches Points within a 100 m bounding box for the map's date range. History fills only time fields the user has not edited. Closing or reopening the form invalidates pending results. The server renders the user's merge threshold, including its default, into the modal.

Both create and edit forms use `VisitPlaceSearch` as a saved Place picker. Picker mode reports the choice to the form and submits an explicit `place_id`; timeline mode retains its immediate Visit update and shared Place creation workflow. The existing Place search endpoint supplies saved Places and reverse-geocoded suggestions. `Places::UserSearch` includes Places with Visits and exposes `has_visits`, scoped to the requesting user. The form preselects the nearest saved Place within 100 m that has Visits. When no such Place exists, an external result can supply the Visit Name only when the existing server geocoding configuration permits it. Suggestions only fill an empty name field.

`Visits::Create` continues to create a second manual Visit at an existing nearby Place when its start time differs. It preserves the submitted Visit Name and the existing Place's name. An explicit different Place takes precedence. No attribution or duplicate-detection service behavior was changed.

Verification lives in `spec/javascript/visit_draft_test.mjs`, `visit_draft_flow_test.mjs`, `visit_form_draft_test.mjs`, `visit_place_search_create_test.mjs`, `spec/services/places/user_search_spec.rb`, and `spec/services/visits/create_spec.rb`. Existing map and Place request specs cover the callers. Browser checks cover English and German at desktop and mobile sizes, including saved attribution and edit mode.

The shared AFFiNE document is titled **Dawarich — Map visit drafts** (document ID `I8c-QQiGCQTNXBU8P-6LG`).

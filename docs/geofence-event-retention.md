# Geofence events after Place deletion

Geofence event history belongs to the user and survives hard deletion of its Place.
Events snapshot `place_name` when recorded, including synthetic webhook tests.
While a Place exists, the log, API and webhook payload use its live name. Normal
Place destruction refreshes every associated event's snapshot to the current name
before nullifying `place_id`; webhook deliveries remain attached to their events.
Webhook filter removal and deactivation on Place deletion keep their existing rules.

`GET /api/v1/geofence_events` returns `place_id: null` and the saved `place_name`
for a deleted Place. Filtering by an existing Place continues to use `place_id`.
Settings → Geofencing and webhook delivery history display the same fallback name.
Queued webhook payloads retain the nested `place` object: `id`, `latitude`,
`longitude` and `radius` are null when the Place is gone; `name` is the snapshot.
The event's own `location` remains available.

State reconstruction ignores events without a Place. Merging Places moves all
historical events to the survivor and refreshes their snapshots, including events
from a duplicate whose notifications have been switched off. Deleting the user
still removes all events and deliveries. User data export/import does not currently
include geofence events.

Migration `PreserveGeofenceEventsWithoutPlaces` backfills existing names with a
set-based SQL update, preserves indexes and makes `place_id` nullable. An existing
Place foreign key becomes `ON DELETE SET NULL`; installations without one keep
that absence. Direct SQL/bulk deletion bypasses the name refresh callback and
retains the snapshot already stored. The migration is explicitly irreversible:
restoring a mandatory Place reference could discard retained history.

This implements the event-retention bullet in Phase 6 of the approved Places
management plan (`2026-10-27-places-management-plan.md`), alongside ADR-0028's
separate archive and hard-delete semantics.

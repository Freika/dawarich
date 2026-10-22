# Exact point totals and incremental statistics

The points page and `/api/v1/points` cache the exact count, maximum timestamp,
and maximum `updated_at` for each filtered relation. Pagination headers,
serialization, ordering, conditional GET validators, and Lite's two point-count
headers keep their existing values. The first read after a change or cache
expiry still executes an exact aggregate; unchanged pages reuse it for one
hour. Cache loss falls back to the database.

## Invalidation invariant

`point_revisions` stores one random revision token per user and UTC month.
PostgreSQL statement triggers rotate tokens transactionally for INSERT, UPDATE,
DELETE, and before TRUNCATE. Updates cover both old and new owners and months,
including timestamp moves, geocoding, anomaly changes, bulk upserts, and direct
SQL. A statement rotates each affected bucket once, rather than once per point.
Random tokens avoid reusing cache entries produced inside rolled-back writes.

Read-summary keys contain the user, the fingerprint of that user's revision
rows, and a digest of the complete filtered SQL. Imports, anomaly modes,
bounding boxes, and plan windows therefore remain separate. Point changes
conservatively invalidate all of that user's read summaries. Revision metadata
is proportional to user-months; point payloads are never read for invalidation.

Default API end times and Lite's sliding lower cutoff are clamped to existing
point timestamps using the user/timestamp index. This preserves membership
exactly while allowing repeated requests between arriving/expiring points to
share cache entries. The original requested bounds still feed the API ETag.

Run the migration before serving this code. A small schema-dumper extension
preserves these functions and triggers in `db/schema.rb`, so schema-loaded
installations use the same invariant. Disabling triggers, manually deleting
revision rows, or restoring only part of the database requires clearing the
application cache before serving reads. Existing points need no revision
backfill: an empty revision fingerprint is valid until the first mutation.

The trade-off is extra revision writes and row locks during point mutations,
including metadata-only changes. The controller should measure ingest as well
as read performance when benchmarking this profile. No request-time approximate
count or periodically corrected `users.points_count` is used for exact totals.

See `single-process.md` for the independent Puma/Sidekiq memory profile.

## Background refresh work

`Tracks::TimeChunkProcessorJob` projects only ID, timestamp, coordinates, and
device identity for buffered segmentation. Its locked orphan re-read also loads
both altitude columns for elevation calculations and preloads device sources.
Neither bulk read loads raw payloads or geodata. Locking, ownership checks,
track boundaries, distances, and elevation behavior are preserved.

Toponym reconciliation still visits a bounded number of statistics per run,
but compares a checkpoint before streaming the month's points. The checkpoint
includes revisions for the UTC months intersecting the local month, timezone,
minimum city duration, canonical country names, and the stored toponyms.
Unchanged months skip the cursor entirely. Point updates and deletions, settings
changes, and manually damaged results trigger a refresh. Adjacent UTC months
may conservatively invalidate a local month.

The dirty-day queue still forces its refresh and cache invalidation; retries,
missing-month discovery, full-stat scheduling, and sweep watermarks retain their
existing behavior. Checkpoints expire after seven days, so cache eviction or
expiry causes a bounded reconciliation scan rather than stale statistics.

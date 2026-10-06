# Native track follow-ups (A12f-3b R04–R05)

The track package consumes its effects through existing native workers and direct
native calls. No reverse-row poller, additional registry entries, routes, or
migration is introduced. The Rails handlers remain available during coexistence.

`Tracks.Owner.lock/2` retains the ownership-row lock and selects Oban for these
track/trip producer paths when `DAWARICH_RAILS=off`. During coexistence it returns
the persisted owner. This is a scoped domain seam, not a global ownership change.

- Intake's existing backfill admission and TeslaMate's timestamp range use
  `BackfillCommands`. TeslaMate selects backfill ownership independently of
  realtime ownership. Coexistence retains the original ambient-zone payload when
  realtime is Rails-owned, and the explicit-zone payload when realtime is native.
  The durable cycle keeps its timezone, bounded timestamps,
  and one due publication; replay widens the same cycle.
- Backfill, daily, and throttled workers select native range work in standalone
  mode. Throttled continuations retain the walk, cursor, step receipt, and
  60-second delay. Legacy Redis bootstrap handoff remains in coexistence;
  standalone bootstrap uses the native walk without a Rails target.
- A realtime lock timeout uses `RealtimeCommands` and the existing shared
  120-second debounce claim to schedule one native realtime job after 45 seconds.
  `RealtimeWorker.perform/1` clears that claim before execution.
- `Tracks.Effects` routes native range ownership to `NativeChanges`, which bumps
  every UTC year covered by the changed interval using the existing track tile
  keys and publishes Rails-compatible created/updated/destroyed messages to the
  authenticated user's TracksChannel. Orphan deletion uses the same seam.
  Empty change sets do nothing. Tile and Cable failures retain Rails' best-effort
  behavior. PostgreSQL Cable publication participates in the caller transaction.
- Realtime success selects points created strictly after the captured five-minute
  boundary, with no reverse-geocoding timestamp. Provider configuration gates the
  selection. Persistent point claims suppress duplicate enqueue; jobs contain at
  most 100 IDs, `force=false`, and the existing reverse worker cursor/identity.
- Transportation progress retains event receipts and the atomic native counter,
  publishes current status on the user's TracksChannel, and handles missing
  native status without depending on a Rails consumer. Coexistence with a Rails
  owner and legacy status retains the source command.
- Trek trip calculation publishes the existing native composite command in
  standalone mode. Existing calculation workers retain ordered, replay-safe
  distance/country/completion effects and pending trip deduplication.

## Integration handoff

HOT owns registry/route mounting; this package needs no new mount or registry key.
Existing track, reverse-geocoding, transportation and trip mappings must remain.
RX-POINTS owns arrival anomaly/point/live/visit effects and realtime arrival
admission. Intake has no lasting diff here. TeslaMate changes only backfill
admission: retain its independent `BackfillCommands.put/4` call when merging the
shared effects file. `RealtimeCommands.trigger/3` is available to that package;
its no-Oban option publishes the registered realtime command to the outbox.
Accepted foreign leases and coexistence handbacks remain separate from this
producer closure. This package does not dispose preexisting reverse rows.

## Verification

`a12f3b_r04_test.exs` and `a12f3b_r05_test.exs` contain the eight named plan tests.
Each has behavioral RED, native GREEN, a failing named reverse-publication
mutation, and restored GREEN evidence in the controller execution report.
The tests exercise real ownership rows, durable cycles/walks, Oban jobs,
PostgreSQL Cable events, Redis tile tokens/progress, and trip terminal events.
Source characterization uses the existing backfill/job-command RSpec batch.
Package gates are compile with warnings as errors, formatting, full ExUnit seed
404 through the controller suite runner, secret scanning, and a clean tree.
Seed 202 belongs to the controller's integrated head.

The retained release audit follows the delegated track effect seam without
removing a handler assertion. The A8 census requires both sets of JSON-only
closure captures and preserves all retained HTML/base assertions. Missing local
JS dependencies are setup; neither correction changes product behavior.

The matching AFFiNE document is titled
“Dawarich — Native track follow-ups (A12f-3b R04–R05)”. The repository document is
the code-coupled counterpart; the execution report contains exact gate totals.

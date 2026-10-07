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
- `Tracks.Effects` routes native range ownership to `NativeChanges`, which records
  a shared `AfterCommit.Worker` tracks intent and database visibility generation
  in the track transaction. The worker checks Redis epoch writes before Cable
  delivery; errors retain retry debt without rolling back committed tracks.
  Every incomplete attempt re-reads committed created/updated track values.
  Stored messages remain a fallback for rows deleted since intent creation,
  preserving historical creation and stable delivery positions. Destroyed IDs
  remain durable. SQL receipts and shared Cable event identities suppress
  successful replay; failed publication rolls back its receipt and can retry.
- Tile validators include the shared database generation, which becomes visible
  at outer commit and rolls back with track changes. Redis cleanup is retryable
  and cannot restore a stale validator. The local telemetry commit hook is removed.
  Preexisting `NativeChangesWorker` rows dispatch through the same shared worker
  with a stable intent derived from their Oban job ID. Keep this compatibility
  module until all legacy notification debt has drained. New writes create only
  shared intents on the projections queue.
- Realtime success selects points created strictly after the captured five-minute
  boundary, with no reverse-geocoding timestamp. Provider configuration gates the
  selection. Persistent point claims suppress duplicate enqueue; jobs contain at
  most 100 IDs, `force=false`, and the existing reverse worker cursor/identity.
- Transportation progress retains event receipts and the atomic native counter,
  publishes current status on the user's TracksChannel, and handles missing
  native status without depending on a Rails consumer. During coexistence, an
  active Rails-created run keeps its Rails status, total and start time regardless
  of track execution ownership. Progress uses the existing `transport_progress`
  Rails command with one receipt per event; no native key shadows that run.
  Native-created runs retain their native counter across execution-owner changes.
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

`tracks/native_effects_regression_test.exs` adds four deterministic regression
probes for Cable row-lock failure, generation completion/publication replay,
outer-commit/rollback epochs, and Rails run ownership. Each has RED, GREEN,
a named failing mutation, and restored GREEN evidence in the fix report.
Retained R05/E14A1 terminal-effect tests consume the committed notification jobs
before checking Cable delivery. E151 treats those jobs as drain debt until
they complete; release completion must not hide pending notification work.

The retained release audit follows the delegated track effect seam without
removing a handler assertion. The A8 census requires both sets of JSON-only
closure captures and preserves all retained HTML/base assertions. Missing local
JS dependencies are setup; neither correction changes product behavior.

The matching AFFiNE document is titled
“Dawarich — Native track follow-ups (A12f-3b R04–R05)”. The repository document is
the code-coupled counterpart; the execution report contains exact gate totals.

# A12rel release adapters

This slice implements two release job adapters behind default-off registry entries
(`claimable: false`). Missing ownership/schema continues to run the original Rails
jobs. It adds no runtime child, queue, capacity setting or public schema migration.
No live ownership change or lifecycle enablement was performed.

| Exact key | Rails parent | Native worker | Version 1 payload |
|---|---|---|---|
| `command:release.achievements_backfill` | `DataMigrations::BackfillAchievementsJob` | `Dawarich.ReleaseOperations.Achievements` | `{}` |
| `command:release.import_backfill` | `TransportationModes::ImportBackfillJob` | `Dawarich.ReleaseOperations.ImportBackfill` | positive integer `import_id`, existing ActiveJob `ambient_zone` |

Dispatch rejects extra fields and unknown versions. Import zones must resolve
through the existing timezone loader. Both parents use maintenance, priority 3,
26 attempts and the existing SyncScheduling backoff (ED-540).

The Rails shim forwards its original ActiveJob ID and scheduled time. Native
release-vector decoding assigns a fresh event ID to each independent intent;
version and source migration ledgers do not change. Historical integer-source
V1_0_2 preserves its rescued no-jobs query; text-source scheduling and Unreleased
import/fleet vectors preserve exact argument order and delays 120/30/10 seconds.
V1_15_2 and V1_16_0 achievements jobs retain empty arguments and zero wait.

Achievements first checks countries, then loads missing subdivision codes from
registry definitions, including continent definitions with subdivision level.
Upsert and geometry repair commit independently of bulk publication. Existing
seed timestamps and geometry bytes remain exact; generated timestamps are checked
against database statement bounds. A failed publication rolls back its marker and
outbox write while retaining committed regions. Partial repair and activity writes
remain retryable. Completed publication is suppressed under ED-541.

The achievement parent publishes silent, forced, stale-only bulk options through
`command:achievements.bulk_check`. Explicit bulk work is independent of
`cron:achievements_bulk_check_job`; leaves use `command:achievements.check` at each
200-user transaction boundary, with 300-second staggering. Force retains the
existing leaf meaning. Stable IDs are UUIDv5: the parent event plus
`release.achievements.bulk` produces the bulk ActiveJob ID, the existing URL
namespace plus `achievements.bulk:job:<job_id>` produces its root, and that root
plus `check:<user_id>` produces each child. Reverse kind
`release_achievements_bulk_check` carries exactly `job_id`, `options`, `run_at`;
the registered Rails handler restores that ActiveJob ID before enqueue. Existing
`achievements.bulk_check_leaf` reverse delivery rechecks current leaf ownership.
Accepted native parents finish after release; new bulk/leaf publication follows
current ownership. The two-connection race tests cover 200/201/401 eligible users,
stale filtering, publication rollback, retry and completed replay.

Import source support stays integer 0/1/2/3/6. Semantic timelineObjects and phone
rawSignals/root-array activities modify only selected import points, preserve full
motion_data records and existing keys, and keep source time ranges, sixty-second
windows and tie rules. Google records, OwnTracks and GeoJSON skip activity parsing
and still run the track phase. Missing/deleted/unsupported imports do nothing;
absent attachments, failed downloads and rescued malformed JSON still reprocess
tracks. Shape and SQL errors stop before tracks while retaining earlier activity
commits. Each distinct existing track has its own transaction; inference failure
uses the import-only fallback, preserves manual/source segments, and publishes the
existing tracks_changed callbacks. Single-track reset remains strict.

Reader checksum, declared-size and empty-byte checks remain enabled (ED-542).
Readable-but-invalid attachment source outcomes are captured alongside native
skip-activity/continue-tracks outcomes. Eugene acceptance is pending before native
ownership or lifecycle activation; it does not block default-off implementation
or merge. ED-543–549 are reserved, unused.

Operators use the existing Rails `JobOwnership.release!(exact_key, by: actor)` to
pin Sidekiq ownership; `JobOwnership.unpin!(exact_key, by: actor)` removes that pin
without claiming this default-off entry. For pending commands, use
`JobCommands.rehome!('release.achievements_backfill', by: actor)` or
`JobCommands.rehome!('release.import_backfill', by: actor)`. Rehome preserves due
time and the import ambient zone, invokes the original Rails class and reports
moved/left/error. Unsupported versions and dispatched work remain in place.
Release parent, explicit bulk, leaf and cron keys independently. Retain accepted
work, processed identities and durable reverse/callback publications during
handback; unpinning alone does not enable these adapters.

Evidence uses the existing A12d2/normal-import generators and source JSON/input
bytes under `app-phoenix/test/fixtures/a12rel`. The corpus test compares complete
rows, EWKB, motion data, errors, callbacks, schedules and committed snapshots.
The `:rails_parity`, `:a12rel_reverse_handoff` producer must run immediately before
the `:eval` Rails “A12rel handoff” consumer on the same assigned Phoenix scratch
DB; missing rows fail. Ordinary full ExUnit excludes rails_parity and ordinary
Rails runs exclude eval. Full branch seeds are 404 and 202 via existing slot-aware
scripts; the controller owns the third integration seed.

The controller merges this slice before A12h resumes its all-vectors Task 6
checkpoint and Task 7 live-insertion gate. AddPointDimensionColumnsJob and
DropLegacyLatLonJob remain A12h deferrals. This cut does not close A7 fleet
ownership, adapter retirement, Sidekiq drain, Cloud activation, supported-upgrade
matrix, or release acceptance. Browser/stand/image checks are deferred to the
controller mini lane. No AFFiNE write belongs to this data-exposure-sensitive task.

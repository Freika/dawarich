# A7r2 import, export and user-data handoff

The default-off A12d3 schedule and reversible drain procedure is documented in
[A12d3 schedules and Sidekiq drain](phoenix/a12d3-schedules-drain.md). It retains
all 125 source classes and framework jobs, maps 24 Rails schedules (cache
coexistence still blocks full closure), and uses existing owner/rehome/status
tools. Native redacted drain inspection is `dawarich jobs drain-status`; default
`dawarich jobs status` retains its Rails parity output. Explicit idle-role configuration is available only after release drain
acceptance; tests do not authorize a live Sidekiq shutdown. ED-520–ED-522 record
UTC firing instants, skipped activation catch-up and pending-import retention.
Source jobs and Redis stay through the separately approved rollback window.

The A7r2 feature branch implements P24–P34, R2 and U1–U14 of
`2026-10-03-phoenix-a7-remaining-imports-exports-plan.md` in the sibling
`superpowers/plans` directory. A7r1 is integrated; A7r2 remains pending
controller integration and release acceptance.

Supported owner-scoped import pages and writes include non-GPX sources.
Foreign imports and unsupported rows replay to Rails before pipeline effects.
Export deletion supports DELETE and form POST with `_method=DELETE`.
Signed Active Storage routes retain their capability and checksum checks.
Settings use GET `/settings/users/export` and POST `/settings/users/import`.

Rails and Phoenix write backup export records in ascending ID order. Rails
previously used unspecified database order; no consumer depends on that order.
The Rails fixture dataset resets the export sequence after its explicit IDs,
so newly created backup records have the same order as the native fixture seeds.

HTTP rollback keys are `imports`, `exports`, `active_storage` and `user_data`
in `DAWARICH_RAILS_ROUTES`. Settings backup routes also honor `settings`.
HTTP rollback does not change worker ownership or drain queued commands.
Integration/settings CRUD, import APIs and unsupported formats retain their
existing Rails owners.

All new registry entries remain `claimable: false`:

| Kind | Keys |
|---|---|
| Commands | `imports.immich_geodata`, `imports.photoprism_geodata`, `imports.teslamate_sync`, `imports.trek_sync`, `imports.trek_import`, `users.export_data`, `users.import_data` |
| Cron | `watcher_job`, `stale_jobs_recovery_job`, `teslamate_sync_job`, `trek_sync_job` |

The command and cron ownership keys have `command:` and `cron:` prefixes.
User-data commands are version 1 and capture user/import identity, time zone
and locale. Existing Rails job shims forward old queued jobs with their
original job ID. Native archive discovery routes source 8 through the
user-data restore worker and retains the import lease/ownership fence.

The existing A1 ownership workflow remains required before activation:
exercise old queued versions, claim/drain and rollback/rehome with synthetic
inputs. `JobCommands.rehome!` returns pending outbox commands to their Rails
producer; failed pushes retain unpushed rows. The HTTP `user_data` rollback
key alone does not rehome either user-data command.

Local branch acceptance uses `resync-check.sh` seed 404, `seedrun.sh` seed 202,
the plan's scoped Rails specs, two fixture recordings and byte diffs,
RuboCop without cache, and branch/changed-file gitleaks scans. Existing schema
isolation, import writer, GPX, storage, crypto, lease and export tests remain
part of the full ExUnit tier. Final totals are recorded in the controller's
`orch/out/fix-a7r2.report.md` handoff. Seed 303 runs on the controller's
integration head.

The merged-slice regressions materialize purge batches before deleting rows,
so nested-loop plans cannot change the selected batch during deletion.
Geocoding cache-hit coverage observes the successful Rails Lua reservations
without relying on a short-lived bucket surviving between assertions.
Achievement ownership checks retain explicit `user_data` rollback replay,
and public achievement pages compare the complete tracked Rails import map.

Normal lifecycle and ZIP fanout parity tests observe enqueue order with a
shared test sequence across native and reverse commands. The sequence and
columns are removed at teardown; production schemas are unchanged. Physical
heap order and transaction timestamps cannot establish enqueue order after
DELETE-based fixture cleanup. Reordering regressions retain the complete
Rails field and enqueue-order comparisons.

Full RSpec, browser/stand, image/Compose and PgBouncer topology acceptance
remain controller release work. No AFFiNE synchronization is performed for
this data-exposure-sensitive task.

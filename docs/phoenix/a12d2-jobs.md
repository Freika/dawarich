# A12d2 residual jobs

This cut implements twelve Rails job classes while retaining their source jobs and execution shims. Every new registry entry is `claimable: false`; local tests do not activate ownership, drain Sidekiq or remove Rails. HTTP route hand-back is independent of job ownership.

| Rails class | Ownership key |
|---|---|
| Tracks::BackfillGenerationJob | command:tracks.backfill |
| Tracks::ThrottledBackfillJob | command:tracks.throttled_backfill |
| Families::AutoCreationJob | command:families.auto_create |
| Families::MemberSyncJob | command:families.member_sync |
| Places::DeleteIfOrphanJob | command:places.delete_if_orphan |
| Places::OrphanCleanupJob | command:places.orphan_cleanup |
| Places::NameFetchingJob | command:places.name_fetch |
| Places::BulkNameFetchingJob | command:places.bulk_name_fetch |
| Achievements::BulkCheckJob | command:achievements.bulk_check and cron:achievements_bulk_check_job |
| AirTrail::SyncSchedulingJob | cron:airtrail_flight_import_job |
| TeslaMate::SyncSchedulingJob | cron:teslamate_sync_job |
| Trek::SyncSchedulingJob | cron:trek_sync_job |

Retained cron expressions are `30 1 * * *`, `0 2 * * *`, `30 2 * * *` and `0 */6 * * *`, respectively. Serialized cron-origin markers prevent a Rails firing from forwarding a duplicate native-owned sweep. Explicit unmarked achievements calls retain their arguments. Eligible users are ordered by ID before filtering current achievements and assigning five-second offsets.

K8 ranges and K9 walks live in shared `phoenix.track_backfill_ranges` and `phoenix.track_backfill_walks`. Publication, receipts and state transitions use the same transaction. K8 carries a cycle and ambient zone; K9 carries its walk, cursor, selected window, expiry and stable step identity. Legacy Redis snapshots remain Rails compatibility work. Native K9 bootstrap detects an occupied per-user legacy key and sends it through the registered Rails adopter before fresh SQL bootstrap. Positive TTL is preserved, never inferred as a cursor. Redis probe failures also take this compatibility path.

Rails-owned children use durable reverse intents. Failed or aborted enqueue retains the intent; retry resumes the same committed cycle/walk or cron receipt. It cannot consume a newer range or replace a pending cursor. The poller finishes reverse handlers' after-commit callbacks before acknowledgement. Family insertion uses a savepoint: source-handled insert failures leave no partial rows, while later sync failures still roll the whole family transaction back. Notification failure keeps the successfully created family. Existing mail and integration transport remain Rails-owned.

Source parity retains entitlement, consent, family locale and membership dates; place naming, geodata and visit renaming; orphan user/reference guards; scheduler selection; K8 lookback/day boundaries; and K9 strict cursor windows and delays. The source corpus contains 126 cases. Four failure projections were corrected after isolating actual family transaction rollback: AutoCreationJob `sync_error`/`error`, MemberSyncJob `member_error`/`error`. No successful source projection changed.

The bounded differences are [ED-480–485](../../app-phoenix/parity/expected_diffs.md): durable state/replay, low-priority transport, reverse timing, error representation, the active-visit orphan race and residual physical queue routing. K9 repeat/error normalization is confined to the two named state/replay cases. Family and orphan workers use the existing maintenance queue; place naming uses reverse_geocoding. Queue capacity and performance are unchanged and unclaimed. Rails-owned ingest retains the original timestamps/user_id reverse payload and its existing Rails ambient-zone behavior; native K8 captures the producer zone in shared state.

For local checks, use the allocated worktree and private test databases, Rails `RAILS_ENV=test DATABASE_NAME=...`, the worktree's private Redis URL, and Mix 1.18.3/OTP27. Never print environment credentials. Preserve and restore `swagger/v1/swagger.yaml` around each RSpec invocation.

```sh
# app-phoenix; use the task's required Mix/database environment inline
mix test test/dawarich/jobs/a12d2_corpus_test.exs
mix test test/dawarich/jobs/a12d2_corpus_test.exs --include rails_parity --only a12d2_reverse_handoff
# Immediately at the worktree, against the same Phoenix *_scratch database
bundle exec rspec spec/services/residual_job_commands_spec.rb --tag eval --example 'consumes actual native reverse rows through the registered handlers' --example 'same-slot Rails and native crons sweep once for all four exact owner keys' --seed 101
# Source comparison first; only after success, two WRITE_PHOENIX_FIXTURES=1 runs and cmp
bundle exec rspec app-phoenix/scripts/parity/a12d2_jobs_spec.rb --seed 101
```

The ordinary corpus uses existing JobsCase/ScratchRepo reset support. A stale place left by another case requires rebuilding the existing public baseline. The handoff verifies the baseline migration version and sets Rails' standard environment/schema metadata so Rails cannot purge committed producer rows. It publishes actual reverse rows; the immediate Rails consumer invokes registered handlers and cleans only its own synthetic rows and sequence changes.

Rollback releases the exact job key; accepted Oban work and durable reverse work continue to settle. Pending-only rehome preserves due times and carried state, while dispatched work stays accepted. Parent and leaf keys remain independent. Avoid deleting typed state, legacy snapshots or pending publications during hand-back.

Remaining Rails-owned slices include account lifecycle webhooks/destruction and Partnero signup; admin EnqueueBackgroundJob; transportation import/reclassification; bulk visit suggestions and visit redetection; nightly point geocoding; pending import cleanup; and release achievements backfill. Integration now registers extraction recovery, TeslaMate/Trek children, user data/recalculation and anomaly backfill in their existing cuts; their activation/drain work remains separate. Digest/stat/cache residues retain A12d1b2–b4 owners; mail, tile/token/progress and broad fan-out retain their existing cuts. A12d3 owns cron activation and all legacy/Sidekiq/outbox/reverse drains; A12h boot/migrations/seeds, A12f Ruby-free images/upgrade closure and A13f Redis deletion remain prerequisites.

Full local ExUnit gates use only seeds 404 and 202 through the existing resync/seedrun scripts and slot.sh. The bounded Rails slice also uses slot.sh; targeted tests and generators run directly. RuboCop always uses `--cache false`. Secret scans cover branch commits and changed files only. Detailed commands, mutations, counts and commits belong in the delegate report.

Browser characterization, stand smoke tests, Docker/image checks and mini work are deferred to the controller mini lane. No SSH, live ownership flip, drain, Rails removal or AFFiNE write is part of this data-exposure-sensitive task.

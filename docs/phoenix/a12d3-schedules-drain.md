# A12d3 schedules and reversible Sidekiq drain

2026-10-05. Default-off implementation; live ownership, final Sidekiq drain,
rollback-window closure and image/topology acceptance remain controller work.
No HTTP routes or authentication ownership change. No AFFiNE writes for this
data-exposure-sensitive slice.

## Owner authority and retained sources

Missing owner rows mean Sidekiq. `DAWARICH_OBAN_JOB_KEYS` selects explicit
comma-separated known registry keys; empty claims nothing. Unknown, duplicate
or wildcard selections fail. Existing `claimable: false` entries remain inert.
Persisted pinned Sidekiq owners survive native restart. Removing opt-in does
not release persisted owners. `JobOwnership` / native `Ownership` fence effects
with shared SQL locks; ordered joint Lite cron/mail locks make transfers atomic.

Keep all Rails jobs, reverse handlers, Sidekiq consumers and the Rails poller
through the rollback window. Registry replacements describe native seams;
they do not prove source producer closure. The tested inventory has 125
application job classes, excluding ApplicationJob and concerns, plus framework
Active Storage and Action Mailer jobs. `RailsJobOwners` and its inventory test
are the executable exact class/key mapping. Retired classes still need retained
queued instances to finish or an explicit controller disposition.

## All 24 source schedules

Native state purge at `17 * * * *` is additional correctness-state maintenance,
not a Rails schedule. TeslaMate/Trek each have one registered wrapper; accepted
older scheduler workers remain supported and block activation until complete.
The earlier A12d3 coverage count was 23 native schedules plus the cache
wrapper. A12f-3b G01–G04 now retain all 24 schedules in the native registry;
see [cron closure](a12f3b-cron.md) for timezone, slot, child and accepted-work
contracts. Cache source boot cleaning is retired under ruling 8 after reader
proof; native warming remains and accepted cache jobs still drain. Schedule
registration does not establish source quiescence or an idle Sidekiq.

| Name | Expression / Rails queue | Native module and prerequisites |
|---|---|---|
| bulk_stats_calculating_job | `0 */1 * * *` / stats | `stats/bulk_sweep_worker.ex`, existing; fence/catch-up audit. |
| visit_suggesting_job | `5 0 * * *` / visit_suggesting | `visits/bulk_sweep_worker.ex`; A12d3 native composition and source shim. Explicit bulk calls remain accepted commands, not cron skips. |
| watcher_job | `0 */1 * * *` / imports | `imports/watcher_worker.ex`, existing; A7 full producer closure prerequisite. |
| airtrail_flight_import_job | `0 2 * * *` / imports | `air_trail/sync_scheduling_worker.ex`; keep A12d2 marker/slot fencing. |
| teslamate_sync_job | `30 2 * * *` / imports | Keep `integrations/teslamate_scheduling_worker.ex`; older duplicate registration removed from ImportEntries; child routed by current owner. |
| trek_sync_job | `0 */6 * * *` / imports | Keep `integrations/trek_scheduling_worker.ex`; older duplicate registration removed from ImportEntries; child routed by current owner. |
| app_version_checking_job | `0 */6 * * *` / app_version_checking | `app_version/check_worker.ex`, existing. |
| cache_preheating_job | `0 0 * * *` / cache | `cache/preheat_sweep_worker.ex` retains native warming; source boot cleaning retirement follows ruling 8, accepted source warming drains. Coexistence pins retain Rails selection. |
| daily_track_generation_job | `0 */12 * * *` / tracks | `tracks/daily_worker.ex`, existing K9 native path; accepted walkers drain independently. |
| nightly_reverse_geocoding_job | `15 1 * * *` / reverse_geocoding | `geocoding/nightly_worker.ex`; A12d3 native composition and source shim. Preserve force and invalidation. |
| nightly_family_invitations_cleanup_job | `30 2 * * *` / families | `families/invitation_cleanup_worker.ex`, existing. |
| stale_jobs_recovery_job | `*/30 * * * *` / exports | `imports/stale_worker.ex`, existing; A7 closure prerequisite. |
| family_location_requests_expiry_job | `30 * * * *` / families | `families/location_request_expiry_worker.ex`, existing. |
| points_counter_correction_job | `0 */6 * * *` / low_priority | `users/points_counter_correction_worker.ex`, existing. |
| lite_archival_warning_job | `0 3 * * *` / archival | `lite/archival_warning_worker.ex`; joint with `command:mail.user.archival_approaching` in Rails, native atomic joint handling needed. |
| raw_data_archive_job | `0 3 1 * *` / archival | `raw_data/archive_worker.ex`; `catch_up: false`, keep accepted user/cursor chain. |
| raw_data_verify_job | `0 5 * * *` / archival | `raw_data/verify_worker.ex`, existing. |
| raw_data_clear_job | `0 3 8 * *` / archival | `raw_data/clear_worker.ex`; `catch_up: false`, keep accepted user/cursor chain. |
| monthly_digest_scheduling_job | `0 4 2 * *` / digests | `digests/monthly_schedule_worker.ex`; `catch_up: false`, keep local period/eligible users/mail dependencies. |
| yearly_digest_scheduling_job | `0 6 2 1 *` / digests | `digests/yearly_schedule_worker.ex`; `catch_up: false`, keep source period/locale. |
| pending_imports_cleanup | `15 3 * * *` / low_priority | `pending_imports/cleanup_worker.ex`; exact key has no `_job` suffix; A12d3 bounded cleanup and storage retries. |
| achievements_bulk_check_job | `30 1 * * *` / achievements | `achievements/bulk_check_worker.ex`, existing marker/slot and command split. |
| route_videos_purge_job | `45 3 * * *` / route_videos | `route_videos/purge_worker.ex`, existing. |
| stats_toponyms_refresh_job | `*/5 * * * *` / stats | `stats/toponyms_refresh_worker.ex`, existing. |


## Source job retention map

| Files (under app/jobs/) | Count | Disposition / remaining seam |
|---|---:|---|
| `achievements/{bulk_check,check}_job.rb` | 2 | native seam: `achievements.bulk_check`, `achievements.check`, bulk cron. |
| `air_trail/{import_flights,sync_scheduling}_job.rb` | 2 | native seam: AirTrail command/cron. |
| `app_version_checking_job.rb`, `areas/relabel_visits_job.rb`, `bulk_stats_calculating_job.rb` | 3 | native seam: app version cron, areas command, stats bulk cron. |
| `bulk_visits_suggesting_job.rb` | 1 | A12d3 native parent seam; explicit forms and cron distinguished. |
| `cache/{cleaning,preheating,user_preheating}_job.rb` | 3 | residual b4 + post-coexistence assignment; Rails boot/cache consumers remain. |
| `data_migrations/{add_point_dimension_columns,drop_legacy_lat_lon}_job.rb` | 2 | A12h DDL/migrator closure, not runtime scheduling port. |
| `data_migrations/backfill_achievements_job.rb` | 1 | A12rel native release adapter; accepted legacy parents/children remain supported. |
| `data_migrations/{backfill_altitude,backfill_altitude_user,backfill_motion_data,backfill_onboarding_completed,backfill_place_name_locks,backfill_point_country_id,backfill_point_dimensions,backfill_transportation_modes,cleanup_null_island,destroy_orphaned_tracks,fix_route_opacity,recalculate_anomalies,recalculate_anomalies_user,recalculate_per_tracker_tracks}_job.rb` | 14 | native release seams; old user/continuation jobs still finish or forward under characterized identity. |
| `data_migrations/backfill_places_user_id_job.rb` | 1 | synchronous `ReleaseOperations.PlacesUserId` migrator outcome, not a registry job owner. |
| `data_migrations/{backfill_country_name,backfill_families_for_family_plan,backfill_family_member_entitlements,dedupe_tracks_for_unique_index,migrate_places_lonlat,prefill_points_counter_cache,set_points_country_ids,set_reverse_geocoded_at_for_points,start_settings_points_country_ids}_job.rb` | 9 | declared retirement; queued instances still require source completion or an explicit release decision, never silently delete as superseded. |
| `enhanced_import/{destroy,extract}_job.rb` | 2 | native GPX seams; non-GPX/source replay forms are A7 residual. |
| `enqueue_background_job.rb` | 1 | deferred dispatcher: Immich/PhotoPrism/TeslaMate/geocoding forms; AirTrail seam only already routed. |
| `export_job.rb` | 1 | native `exports.points` versions 1/2. |
| `families/{auto_creation,expire_location_requests,lapse_notification,member_sync}_job.rb` | 4 | native family commands, expiry cron, lapse mail. |
| `family/invitations/{cleanup,sending}_job.rb` | 2 | native cleanup cron / invitation mail. |
| `immich/verify_enrichment_job.rb` | 1 | residual A4 enrichment verifier. |
| `import/{google_takeout,gpx_resume}_job.rb` | 2 | residual A7 source formats/resume lineage. |
| `import/{normal_resume,immich_geodata,photoprism_geodata,process,update_points_count,watcher}_job.rb` | 6 | native seams; NormalResume/Process require A7 residual shapes/continuations. |
| `imports/{destroy,prepare_download}_job.rb` | 2 | native seams with owner/blob identity; source format/storage and purge bridge residue belong A7. |
| `lite/archival_warning_job.rb` | 1 | native cron joint with mail. |
| `partnero/customer_signup_job.rb` | 1 | residual external attribution; no claim based on an existing HTTP client alone. |
| `pending_imports/cleanup_job.rb` | 1 | A12d3 native seam with shared-blob safety. |
| `places/{bulk_name_fetching,delete_if_orphan,name_fetching,orphan_cleanup}_job.rb` | 4 | A12d2 native seams. |
| `points/{anomaly_backfill_user,anomaly_filter}_job.rb` | 2 | backfill native; AnomalyFilter inventory still labels d1, alias routes to `points.anomaly_recalculate`/Tracks::Recalculate, audit actual source forms. |
| `points/nightly_reverse_geocoding_job.rb` | 1 | A12d3 native seam. |
| `points/raw_data/{archive,archive_user,clear,clear_user,verify_random}_job.rb` | 5 | native cron/accepted child chains; storage/key/verification contracts retained. |
| `posters/create_job.rb`, `reverse_geocoding_job.rb`, `route_videos/purge_job.rb`, `stale_jobs_recovery_job.rb` | 4 | native seams, stale recovery retains A7 producer closure. |
| `stats/{calculating,full_recalculation,toponyms_refresh}_job.rb` | 3 | native seams after d1. |
| `tesla_mate/{sync,sync_scheduling}_job.rb` | 2 | native leaf and scheduler exist, but A12d3 scheduler routes its child by current owner. |
| `track_segments/time_anchor_backfill_job.rb` | 1 | native release seam. |
| `tracks/{backfill_generation,boundary_resolver,daily_generation,deduplication,parallel_generator,realtime_generation,recalculate,throttled_backfill,time_chunk_processor}_job.rb` | 9 | native seams; BoundaryResolver/TimeChunk legacy accepted session work must drain, native range replacement alone is insufficient. |
| `transportation_modes/{fleet_reclassify,reclassify_track}_job.rb` | 2 | native release/leaf seams. |
| `transportation_modes/{import_backfill,user_reclassify}_job.rb` | 2 | ImportBackfill has the A12rel native adapter; UserReclassify remains residual with progress/callback semantics. |
| `trek/{import_trips,sync,sync_scheduling}_job.rb` | 3 | native leaves/scheduler exist; d2 scheduler reverse-only child publication fixed here. |
| `trips/{calculate_all,calculate_countries,calculate_distance,calculate_path}_job.rb` | 4 | native composite seam, stable run token for legacy children. |
| `users/{creation_webhook,destroy,destruction_webhook}_job.rb` | 3 | residual external notifications and destructive account lifecycle. |
| `users/digests/{calculating,email_sending}_job.rb` | 2 | transitional yearly shim/retirement; old serialized mail payloads still drain under source. |
| `users/digests/{monthly,yearly}/{calculating,email_sending,scheduling}_job.rb` | 6 | native digest calculation/mail/cron seams; source batch fences need audit. |
| `users/{export_data,import_data,mailer_sending,points_counter_correction,recalculate_data,reset_points_counter}_job.rb` | 6 | first five native seams (mailer multiple types), reset counter declared retirement; queued retired work still drain. |
| `visit_suggesting_job.rb`, `visits/{fleet_redetect,full_history_redetect}_job.rb` | 3 | native visit/release seams. |
| `visits/user_redetect_job.rb` | 1 | residual locked/progress user fan-out. |
| **Total** | **125** | no physical source deletion in A12d3. |

## Reverse handlers and framework debt

`RailsCommands::Registry.keys` and native `RailsCommands.closure_kinds/0` are
checked against each other. All 78 retained reverse kinds after the A12rel integration sync
remain BLOCKED producers even if their current backlog is zero. Operator
status lists each kind; it includes mail/digests, geocoding/place effects,
tile/cache invalidation, import-card/progress updates, storage purge,
visit-month invalidation, tracks scheduling, release achievements fanout and
retained cache warming.
Inspect the live registry on each integration head; do not infer closure from
this historical count. Unknown jobs and framework attachment/mail callbacks
remain debt. Never decode arbitrary serialized Ruby as a migration strategy.

## Phase-by-phase cutover and rollback


1. **Default-off install.** Retain Rails/Puma/Sidekiq, Redis, compatibility source jobs and all
   hand-back keys. Verify no implicit claims. Confirm unique cron entries, compatible SQL
   schemas, release readiness, native health and active source reverse poller. Never migrate
   Redis payloads by interpreting arbitrary serialized Ruby in Phoenix.
2. **Finish producer closure before final drain.** Complete the residual list below. Verify
   exact owner-class/key and reverse-kind mapping using existing tests/tools; grep producers
   and framework attachment/mail callbacks. A transient zero backlog with live Rails producers
   cannot satisfy final release acceptance. Cache coexistence is still a blocker.
3. **Incremental opt-in.** Controller selects explicit ready command/cron keys, preserves pins,
   and starts/restarts native boot with that selection. Joint Lite keys flip atomically. Lock
   conflicts fail without partial changes; don't force-flip locked long imports. Cron source
   fences and source-slot publication checks cover concurrent/delayed scheduler execution.
   Catch-up policy is explicit per entry. Keep new schedules off until their leaf owners and
   retained rollback handlers are ready. For Trek/TeslaMate wrappers require zero incomplete
   old scheduler workers via existing status tools; accepted old work drains without deletion.
   Verify housekeeping retention fences before any affected ownership transfer.
   Verify outcome per key, not just claimer process exit.
4. **Drain old work while producers move.** Existing queued source jobs finish/forward under
   compatibility shims with original job UUID. New native child work uses current owner and
   stable publication identity. During incremental coexistence retain the source reverse
   Poller; at the final Cloud switch fence it and first close native-to-Rails dependencies.
   OLD consumes only proved-safe accepted source chains. Scheduled and retry work remains
   debt until processed/resolved; never bulk-delete,
   pull all future work forward or clear dead jobs. If a source payload is unsupported, stop
   final cutover and ask the controller for its concrete disposition, retaining the payload.
5. **Final producer quiescence.** In the approved maintenance window pause incoming mutations,
   manual jobs, callbacks and every source boot/scheduler producer; retain read-only routes and
   hand-back. Record controlled services/processes, not a freeze/receipt artifact. Disable
   source cron loading/enqueue through installed sidekiq-cron configuration/entrypoint controls
   only after keys moved; inspect stale Redis cron registrations as well as schedule.yml.
   Do not clear schedule state. If there is no safe installed switch, stop and make the smallest
   change to existing initializer/entrypoint in a separately authorized implementation step.
6. **Observe both runtimes under quiescence.** Run existing extended `dawarich:jobs:drain_status`
   and `dawarich jobs drain-status`. Default `dawarich jobs status` retains the Rails parity
   output; drain inspection separately reports redacted SQL debt and legacy schedulers.
   Require all relevant owner keys Oban, 24 unique schedules, no
   ActiveJob/unknown work in every queue, scheduled/retry/dead/busy zero, no live fetch/reserved
   work, no future/due pending or quarantined public outbox debt, no future/due/leased/retrying
   or dead reverse debt, no unfinished source-dependent native/release operations. Historical
   terminal rows may remain; Processed receipts stay while supported delayed replay is possible,
   unfinished generations/chunks stay, and dead/unsupported debt never expires automatically.
   Fence live housekeeping that would destroy any of these until Eugene decides disposition;
   do not delete history to call outbox “empty.” Read failures/stale heartbeat mean UNKNOWN/BLOCKED.
7. **Stop Sidekiq last.** Once debt is empty, quiet all registered Sidekiq processes, let busy
   jobs settle, then graceful TERM and ensure no registered/live fetching process remains.
   Inspect again before unpausing producers; stop on a newly appearing item. Shared SQL/Redis
   inspection is not an atomic global snapshot—producer quiescence and stopped consumers
   establish the boundary, not two lucky readings. Sidekiq pause alone is insufficient.
8. **Idle role and reopen native producers.** Only after release acceptance set worker role to
   sidekiq_idle. One web BEAM handles Oban; the worker container is inert and its actual argv
   matches health checks. Topology smoke proves privileges, health, SIGTERM and no extra DB
   pool/cron. Redis remains for cache/Cable/other owners; A13f removal is separate.
9. **Rollback while window is open (rulings 4/7, 2026-10-06).** Fence all new
   native/source producers, incoming mutations, callbacks and manual work. Enumerate
   every Registry key and persisted owner, resolve unknown rows and release each actual
   key to Sidekiq with pinned=true; joint releases are atomic and held locks are never
   forced. Keep Phoenix workers/relay alive until pre-fence outbox, accepted Oban,
   release operations and successors finish with original identities and due times.
   Require the binary rollback observation to be empty with OBSERVED certainty;
   unknown/read failures, dead/quarantined/future/reverse or unfinished work block.
   No rehome/transfer, backup restore, inverse migration or deletion is performed.
   Stop all Phoenix writers/claimers and retained helpers/Poller, verify absence and
   re-inspect debt, then start stock Rails **1.15.3** on the same DB/storage. Restore
   source producers once and verify pins, health/auth/API keys, Phoenix-era rows and
   objects, and one source schedule slot before reopening traffic. Stock 1.15.3 has
   no port ownership CLI: run release/status on the retained control plane before
   stopping it. See the full
   [manual rollback and deferred G48](a12f-ruby-free-release.md#a12f-3c-same-database-rollback-to-rails-1153).
   This supersedes the earlier pending-rehome proposal; existing coexistence tools
   remain historical interfaces for their owners. External delivery stays at least once.
10. **Close rollback window only by Eugene's release decision.** A12f deletes Rails/Ruby/source
    payload support and owns irreversible upgrade refusal/rollback matrix. This branch makes
    no such decision. Retain Redis until A13f's stable-release prerequisites are satisfied.

Operator commands in tests/local rehearsal carry the command convention's Ruby activation,
`RAILS_ENV=test DATABASE_NAME="$RDB" REDIS_URL="$TEST_REDIS_URL"` inline, e.g.:

```zsh
eval "$RUBY_ACTIVATION" && RAILS_ENV=test DATABASE_NAME="$RDB" REDIS_URL="$TEST_REDIS_URL" bundle exec rails dawarich:jobs:drain_status
eval "$RUBY_ACTIVATION" && RAILS_ENV=test DATABASE_NAME="$RDB" REDIS_URL="$TEST_REDIS_URL" bundle exec rails 'dawarich:jobs:release[cron:visit_suggesting_job]'
eval "$RUBY_ACTIVATION" && RAILS_ENV=test DATABASE_NAME="$RDB" REDIS_URL="$TEST_REDIS_URL" bundle exec rails dawarich:jobs:status
```

Production deployment commands/resources are a separate operator assignment, not executable
under this delegate's test-only resource restrictions. No SSH or remote DB command is supplied.


## Idle worker role

Native shutdown stops the jobs workers subtree, then locally pauses Oban queues,
before draining the front and stopping Oban and the database. The existing
12-second Oban shutdown grace remains unchanged. Pausing prevents new local
execution; it neither cancels accepted work nor proves completion. Other nodes
continue accepting work. Accepted work may commit durable successors and Rails
reverse effects while local queues are paused; retain both consumers until
these debts resolve. Forward retirement and binary rollback have separate checks.

`DAWARICH_PROCESS_ROLE` accepts unset/empty/`web` (existing behavior) or
`sidekiq_idle` (explicit opt-in); other values fail. The sidekiq entrypoint
keeps privilege and environment handling, then the explicit idle role executes
`dawarich start` before any database wait. Application starts an empty existing
supervisor: no Repo, Redis, Endpoint, Puma, Oban, relay or cron. The web BEAM
remains the only native jobs runtime. The normal entrypoint still executes
`bundle exec sidekiq` for source operation and rollback.

The installed Elixir 1.18.3 release template's `start` arm does not forward
trailing arguments. The existing release env template therefore sets the idle
short node name to literal `sidekiq`; the BEAM argv receives `-sname sidekiq`.
There is no shell sleep loop. Local tests establish role classification, empty
children and clean supervisor shutdown. Actual container argv, health,
privileges and SIGTERM require the controller image/topology lane.

## Explicit differences

ED-520 extends the existing UTC scheduler policy: new Oban parents use
Etc/UTC while Rails sidekiq-cron uses ambient TZ/Time.zone/OS. For Berlin,
these regular firing instants differ (winter/summer UTC, outside transition
hours); source window/eligibility computation still carries its ambient zone.
DST transition dates must use their actual offset at the source firing time.
The original corpus pins Berlin DST windows and UTC parent outcomes.

| Schedule | Rails Berlin winter UTC | Rails Berlin summer UTC | Native UTC |
|---|---|---|---|
| visit_suggesting_job | previous day 23:05 | previous day 22:05 | 00:05 |
| nightly_reverse_geocoding_job | 00:15 | previous day 23:15 | 01:15 |
| pending_imports_cleanup | 02:15 | 01:15 | 03:15 |

ED-521: effectful/seasonal cron activation skips blind immediate catch-up.
Regular schedules and accepted children remain; shared Processed UUID receipts
suppress same-slot source/native fanout and remain retained for delayed replay.
The real Ruby/BEAM collision test proves missing-owner locks, timeout, old slot,
publish rollback, both owner directions and pinned original-slot replay.
This provides no exactly-once external mail/webhook guarantee.

Slotted source nightly geocoding commits point receipts, stable reverse intents and
user invalidation intents together in SQL before Sidekiq delivery. A failed enqueue
leaves the intents recoverable by the reverse poller. Root completion and user
invalidation use separate shared identities; accepted continuations settle their
carried users even after a replay completes the root. Un-slotted source calls retain
their existing enqueue path.

ED-522: native unshared expired pending-import rows/references remain until
retryable object deletion succeeds, unlike Rails purge/purge_later row removal.
Rechecks retain live shared references; this admits no wrong-owner/blob purge.
S3 deletion treats blank or ambiguous 404 responses as unconfirmed absence and
retains all references. Only an explicit object-specific `NoSuchKey` confirms absence.
Both pending-import workers use the configured maintenance queue at priority 3.

## Release prerequisites beyond this branch


The following remain named work, not compressed into “enable all jobs.”

1. **Cache closure:** finish b4 disabled composition, then separately authorize post-coexistence
   native warming/invalidation/reader/cache-cleaning retirement. Current `cache_jobs_scheduled`
   boot sentinel, Cache::CleaningJob and warming reverse delegation keep Rails/Sidekiq alive.
2. **A12d2 residual parents:** EnqueueBackgroundJob; Visits::UserRedetectJob;
   TransportationModes::UserReclassifyJob. A12rel supplies the achievements parent adapter. Preserve exact dispatcher
   forms, lock/progress and notification effects before claiming their replacement keys.
3. **Account/external effects:** Users::{DestroyJob,CreationWebhookJob,DestructionWebhookJob},
   Partnero::CustomerSignupJob; user soft-delete/dependency/attachment lifecycle and external
   delivery/retry semantics need a dedicated bounded security-sensitive cut.
4. **A7/A4 closure:** GoogleTakeout/GPX resume, EnhancedImport non-GPX source fallback,
   Process/NormalResume residual payloads, retained import-backfill compatibility, storage
   purge/representation/analyze jobs and Immich::VerifyEnrichmentJob. Do not mark a native
   Import route as proof its callback and reverse-effect chain is native.
5. **Release/migrator:** A12h runs native recorded jobs/seeds/entrypoints, closes remaining DDL
   classes and deferred decoder outcomes; historical/declared-retired data jobs still require
   real backlog disposition. A12d3 does not execute arbitrary data migrations from Sidekiq.
6. **Reverse effect closure:** tile epoch, import-card updates, visit-month invalidation, tracks
   untracked scheduling, geocoding/place effects, prepared-download purge, mail and any new
   retained warming/invalidation. Inventory actual Registry handlers at execution; every live
   Rails-only kind remains a final-drain blocker even if its current queue is empty.
7. **Legacy accepted work:** old track sessions/chunks, trip run tokens, export/import uploads,
   raw-data user chains, source transitional digest/mail and retired counter jobs. Let compatible
   source finish/forward, do not synthesize a native identity or drop jobs based on class label.
8. **Release topology:** installed sidekiq-cron disable/loading switch, Cloud concurrency budget,
   idle argv/health, graceful shutdown, jobs pooler/image smoke through existing scripts. No
   browser for this area; whole release still has its browser/platform matrix.
9. **A12f/A13f:** Rails deletion/Ruby-free images and irreversible upgrade matrix; Redis deletion
   only after the required stable release. Do not credit those rows to this plan's tests.

Open questions for Eugene (release decisions only):

- When may coexistence end so the separately scoped cache retirement can execute? Until that
  explicit authorization, retained warming/cleaning remains a final Sidekiq-idle blocker.
- Which release closes the rollback window and what disposition is approved for any unrecoverable
  historical dead/unsupported job? Default here is retain/block, never destructive clearing.

The assigned local rehearsal resources are Redis 7247, Rails database
`dawarich_test_a12d3` and Phoenix database `dawarich_phoenix_test_a12d3`.
The open release decisions preserve cache coexistence and retain/block defaults.


## A12f-3c final Cloud checkpoints (2026-10-06)

The phase list above preserves incremental coexistence history. Controller
ruling 2's final Cloud cut uses separate NEW Phoenix-only and OLD drain-only
roles, with two independent checkpoints detailed in
[the package P handoff](a12f-ruby-free-release.md#a12f-3c-operator-cut-over-and-old-shutdown-handoff).
At traffic switch, NEW's image/HTTP/lifecycle/shared-storage proof and accepted
chain isolation must be complete; disable OLD publication, boot/cron/manual/
callback producers and reverse Poller. Only proved-safe accepted source debt
may drain on OLD. NEW never uses OLD as an upstream.

OLD shutdown follows full G49 under producer quiescence: D pre_quiet observations,
quiet all identified fetchers, settle effects, require explicit stopping state
and no probes, check native shutdown debt, TERM, then independently inspect
process absence and repeat post_stop/source/native observations. UNKNOWN,
unreadable, newly appearing, unknown/retired/dead work blocks and remains stored.
D's integrated review fix and E's actual smoke/stop evidence are prerequisites;
this runbook is not their execution result. Resume native producers only after
absence proof. Ruling 7's same-DB rollback pins every real key then drains natively;
no pending transfer is used. Release dates/windows remain Eugene's values.


## H03/H04 SQL observation boundary

`Jobs.Drain.status/1` labels its observation `scope: native_sql` and source
`NOT_OBSERVED` / `UNKNOWN`, with `source_inspection_required`. Its `g49` field
is always `BLOCKED`; native `binary_rollback: OBSERVED_EMPTY` describes only
SQL debt after every known owner is pinned Sidekiq. This is required even if
source Redis is reachable, empty or unavailable: the native observer does not
read it. Database read failure retains UNKNOWN and blocks every native result.
The retained Rails `JobDrain.status` independently counts source queued,
scheduled, retry, dead, busy, reserved and unknown work, plus changed/read
failures. Release acceptance combines observations with actual producer fences.

H03 originally identified three live producer gaps: the place reverse-geocoding
adapter, the point achievement helper during coexistence, and Null Island
follow-ups. Their native adapters and terminal-effect/zero-reverse/Rails
hand-back proofs are now implemented in R13k05, R14helper and R19k04; see
[a12f3b-pages-producers.md](a12f3b-pages-producers.md). H03a exercises native
place publication and explicitly pins that command back to Rails before its
reverse-debt assertions. All 78 closure kinds, residual producer blockers,
source-inspection requirements and G49 refusal remain intact. These three
repairs do not establish all-producer closure or release acceptance.

R10k01 is now repaired at all three progress publication sites through
`Imports.Progress.publish!/3`, with actual native parent ownership, native
terminal/subscriber effects and unchanged Rails-owned coexistence payloads.
The named `R10progress`, `R10gpx` and `R10normal` regressions cover both modes
and fail individual old-publisher mutations.

The final R01–R20 recheck repairs **R12k02 `exports.purge`** through the actual
export parent ownership and the unchanged shared storage-first purge helper.
Native-owned coexistence and standalone delete physical objects before blob
rows, retain retry targets and protect shared attachments. Rails-owned
coexistence keeps the original payload bytes. `R12k02`/`R12parents` prove both
export types, both modes, mixed ownership and actual storage terminal effects.

The same pre-fix all-kind probe found R19k06's missing
`command:visits.user_redetect` Registry entry and R09k03/R09k04's native-owned
legacy handover. The existing user-redetect worker is now registered unclaimable;
its real fleet child completes natively. The source-owner census names the
native key and retains the accepted `:a12d2` source residue. GPX/normal handover refuses unsupported
native work without source publication or false settlement while its parent is
native; Rails-owned resume retains the exact payload and receipt. Named
`R19k06`, `R09gpxownership` and `R09normalownership` tests and independent
mutations prove these boundaries.

H03/H04 local producer and ED disposition evidence is recorded in
`fix2-hot-h03-closure.report.md` and
[a12f3b-pages-producers.md](a12f3b-pages-producers.md). No durable closure kind,
source disposition, debt or release gate is removed. Native SQL still cannot
certify source drain, and G49 remains blocked pending external observations,
fences, quiescence and lifecycle acceptance.

H03b retains unreadable-database and all-key pin safety. H04 reuses the existing
Cloud operator HTTP/connected-auth test and the actual native trip/release
rollback test; the latter asserts unchanged source queues while SQL native
work drains and still reports source inspection required. Their independent
selectors are `h04_case:H04a` and `h04_case:H04b`.

The [part-B handoff](a12f3b-pages-producers.md) maps route, reverse, source and
cron evidence, the 125/78/24 inventories and approved NE dispositions. The
[release runbook](a12f-ruby-free-release.md) retains R1/J1/J2/L1, G42–G49 and
A12f-3c fence/old-app shutdown owner requirements. Source and Cloud lifecycle
refusals remain intact. Ruling 7 is authoritative: pin all keys Sidekiq, drain
accepted native work, stop Phoenix, then start Rails 1.15.3 on the same data.
No transfer, dead-payload purge or SQL-only source-drained success is allowed.

# Standalone reverse-consumer audit

Status: DONE for the audit and small fixes; **standalone is not complete for all asynchronous side effects**. Audited 2026-10-06 on `feat/fix-standalone`, starting at the assigned integrated standalone head. This is a source/registry audit, not a production queue census or a claim of deployment acceptance. Only synthetic local tests were used.

## What matters for tonight

1. Export deletion is fixed: the deletion transaction removes unshared blob rows and persists object keys/service names in a native Oban purge. Signed blob redirects and existing native disk URLs return 404 immediately. Physical deletion retries without losing keys; shared attachments survive. Previously issued S3 URLs remain subject to S3 deletion/URL expiry until the worker executes; no remote storage was contacted for this audit.
2. **Remaining storage/privacy gaps:** prepared-import-download purge and route-video rejected/detached-blob purge are still unconditional Rails commands. Poster deletion is native after ownership is claimed, but an explicitly pinned Rails owner still delegates its purge.
3. **Live point arrivals are not async-complete:** anomaly job scheduling, realtime track/visit debounce, live point/family/shared broadcasts and tile-token invalidation still use Rails consumers. Successful point ingestion is not proof these effects occur.
4. **Import/delete/edit side effects remain incomplete:** postprocessing fanout, deletion callbacks, achievements, stats/cache invalidation and several Turbo broadcasts still depend on Rails. Root workers may mark work finished after emitting those rows.
5. All 97 current job registry entries are selected by standalone, including residual mail. They have native top-level workers. This does **not** consume `phoenix.rails_commands`. Some top-level workers only delegate or finish by delegating. Explicit ownership pins and foreign-lease handbacks remain honored; they can strand work without Rails and need operator disposition.
6. Small safe wiring added: standalone `Cache.Schedule.preheat_user` with an Oban owner queues the existing `PreheatUserWorker` directly at the captured due time/zone/source UUID. A pinned Rails owner still produces a reverse command. The sweep wrapper remains Rails-dependent; its retained global warming/retirement is not ported here.

## Interpretation and mechanism

`y` means an existing native worker can perform the core requested computation; it does not imply a native adapter consumes this reverse payload. `n` means the exact requested consumer/composite/broadcaster is missing (even where smaller native parts exist). **Every reverse row left in `phoenix.rails_commands` has no native poller in this head.** Jobs.Dispatch only reads `public.job_outbox`; direct Oban children bypass Dispatch. A Rails poller may itself produce native outbox work, so removing Rails also strands those intermediate producer steps.

Modes: **U** unconditional reverse producer, including after successful native work; **O** only when selected ownership is Rails (pinned/unclaimed rows remain possible); **H** explicit ownership/lease handback; **D** retained registry kind with no Phoenix reverse insertion site found; **fixed** changed in this branch. P0 is privacy/retention after deletion; P1 broken writes/derived-data integrity; P2 stale UI/enrichment/email; P3 optional warming. Conditional rows are ranked by the effect when Rails ownership is selected, not asserted as failures under fully claimed native ownership. Original raw points/archives are retained on stalled imports; this audit found missing completion/derived effects, not evidence that successful ingestion loses its primary rows.

## Ranked reverse-kind registry — all 78 kinds

| Kind | Impact / mode | Producing action | Native consumer exists? | Effect without Rails / disposition |
| --- | --- | --- | --- | --- |
| `imports.prepared_download_purge` | P0 / U | Replace a prepared import download | n — exact authorized purge consumer absent | Detached source/prepared data remain in storage and downloadable by retained signed capability; privacy and storage retention. |
| `route_videos.attachment_job` | P0 / U | Upload rejected/unattached video or delete/rebind a route video | n — exact detached/rejected blob consumer absent; retention cron is different | Rejected/deleted video blobs remain accessible and retained; privacy and storage retention. |
| `exports.purge` | P0 resolved / fixed | Delete an export | y — Exports.PurgeWorker; transactional native enqueue | Blob capabilities and disk access revoked immediately; durable storage purge retries; shared blobs retained. Coexistence still delegates. |
| `imports.destroy_requested` | P0 conditional / O/H | Delete an import or hand back its destruction lease | y — Imports.DestroyWorker | Native owner processes directly; pinned/unclaimed or explicit ownership handback leaves destruction pending with retained data. |
| `imports.extraction_destroy_requested` | P0 conditional / O | Delete extracted enhanced import data | y — EnhancedImport.DestroyGpxWorker | Native owner writes outbox; pinned/unclaimed Rails route retains requested-to-delete extracted data. |
| `posters.purge` | P0 conditional / O | Delete a poster | y — Posters.PurgeWorker (direct native child) | Native owner queues native purge; pinned/unclaimed Rails route retains supposedly deleted poster blobs indefinitely. |
| `share_management.live_revoked` | P0 conditional / D | Retained reverse revocation kind; revoke a shared link | y — ShareManagement.Mutations publishes native Cable directly | No Phoenix reverse insertion found; native revocation does not need Rails. Preexisting reverse rows still need disposition. |
| `airtrail_stats` | P1 / U | AirTrail flight sync | y — Stats.CalculateMonthWorker; flight-month fanout absent | Flight-inclusive monthly/year stats stay stale. |
| `imports.destroy_achievements` | P1 / U | Delete an import | y — Achievements.CheckWorker; composite handoff absent | Achievement totals retain deleted location data. |
| `imports.destroy_callbacks` | P1 / U | Delete import points/visits or extracted data | n — places and reclassification workers exist, composite callback absent | Orphan cleanup and reclassification stay stale after destructive changes; no additional primary deletion, but inconsistent derived data. |
| `imports.destroy_stats` | P1 / U | Finish deleting an import | y — Stats.CalculateMonthWorker; affected-month fanout absent | Stats retain deleted location data. |
| `imports.postprocessing_step` | P1 / U/O | Finish import or schedule its extraction | n — exact composite reverse-step consumer absent; component workers exist | schedule_stats (months + achievements), schedule_visit_suggesting and extract never run; command step is owner fallback for tracks.generate_range/imports.update_points_count. Imported points persist, derived views stale and extraction absent. |
| `points.anomaly_filter` | P1 / U | Point ingestion and TeslaMate sync | n — AnomalyFilter.call exists; no queued arrival-range worker | Live-ingest anomaly evaluation never starts; import postprocessing does call native filter inline, with separate Rails-dependent followups. |
| `points.anomaly_stats` | P1 / U | Anomaly filtering flags points | y — Stats.CalculateMonthWorker; queue/zone/month adapter absent | Flagged anomalies continue contributing to old stats until an independent native recalculation. |
| `points.live_broadcast` | P1 / U | Ingest locations from trackers/API | n — exact live point/family/shared privacy-aware broadcaster absent | Live-map/family/shared subscribers receive no arrival update; stored points survive. |
| `points.tile_epoch` | P1 / U | Ingest/import/restore/edit/delete/flag points | n — exact Points::TileEpoch invalidator absent | Year tile tokens remain unchanged; readers/caches can serve stale points after successful writes/deletes. |
| `points.web_destroy_follow_up` | P1 / U | Delete individual/bulk points in browser or API | n — exact epoch/stats/tracks/achievement composite absent; component workers exist | Deletion succeeds while tracks, stats, achievements and tiles remain stale; potentially visible deleted geometry. |
| `release_null_island_follow_up` | P1 / U | Upgrade/release null-island cleanup | n — exact cleanup/epoch/visit/stats/track composite absent | Cleanup followups remain pending: derived visits/tracks/stats/tiles can still contain removed geometry. |
| `release_reclassify_tracks` | P1 / U | Upgrade/release transportation operation | y — Transportation.ReclassifyTrackWorker; release fanout absent | Release completes its root while tracks never receive the intended reclassification. |
| `release_user_redetect` | P1 / U | Upgrade/release visits fleet redetect | y — Visits.RedetectWorker; staggered release fanout absent | Users keep old machine visits even though root release job completes. |
| `schedule_untracked_tracks` | P1 / U | Extract enhanced import GPX / complete import followups | y — Tracks.RangeWorker; import-range scheduler absent | Untracked imported points do not get scheduled for native track generation by this path. |
| `stats.caches_invalidated` | P1 / U | Calculate stats, refresh toponyms, finish nightly geocoding | n — exact retained multi-cache invalidator absent | Stats/insights cached reads may lag successful database recalculation. |
| `tracks.realtime` | P1 / U | Point ingestion and TeslaMate sync | y — Tracks.RealtimeWorker; Rails debounce producer absent natively | No immediate track generation from arrivals; daily native sweep may repair later. |
| `tracks_changed` | P1 / U | Generate/recalculate/reclassify/delete tracks or release orphan cleanup | n — exact tile-epoch + track Cable publisher absent | Track tiles and subscribed map refreshes stay stale after native DB changes. |
| `visit_months_changed` | P1 / U | Relabel/delete/rebuild visits or change areas | n — exact month-summary cache invalidator absent | Visit summaries retain old/deleted data until expiry or recomputation. |
| `visits.realtime` | P1 / U | Point ingestion | n — exact realtime visit debounce/composition absent; SuggestWorker exists | No realtime visits from arrival; bulk cron may repair later. |
| `visits.web_redetect` | P1 / U | Request full-history visit redetection in settings | y — Visits.RedetectWorker; web payload translation absent | UI accepts request but cooldown/rebuild never starts; visits stay unchanged. |
| `exports.points_created` | P1 conditional / O | Create point export | y — Exports.PointsWorker, command:exports.points | Only pinned/unclaimed Rails owner emits this reverse row; native owner writes executable job_outbox. If reverse route is selected, export remains created forever. |
| `family_location_request_mail` | P1 conditional / O | Ask a family member for location | y — Mail.LocationRequestWorker via mail.family_location_request | Native owner writes outbox; Rails-owner reverse route never emails request, despite persisted request record. |
| `imports.destroy_terminal` | P1 conditional / H | Finish already removed import after ownership changed | n — exact removed-state terminal handback absent; DestroyWorker has native completion | Native work handed to Rails never performs terminal stats/notifications/receipts; primary deletion may already have happened. |
| `imports.extraction_requested` | P1 conditional / O | Request enhanced import GPX extraction | y — EnhancedImport.ExtractGpxWorker | Native owner writes outbox; pinned/unclaimed Rails route accepts request but never extracts. |
| `imports.normal_resume` | P1 conditional / H | Non-GPX import ownership/lease handback | y — Imports.ProcessWorker; explicit Ruby resume protocol is not native | Handed-back normal import cannot resume without Rails; original blob remains for recovery. |
| `imports.resume` | P1 conditional / H | GPX import ownership/lease handback | y — Imports.ProcessGpxWorker; explicit Ruby resume protocol is not native | Handed-back import cannot resume without Rails; do not force or double-run a foreign lease. |
| `imports.upload_created` | P1 conditional / O | Upload/claim/watch/import a file, including PhotoPrism/Immich and user-data restore | y — ProcessGpxWorker / ProcessWorker / UserData.ImportWorker via native format routing | Native owner routes supported formats to outbox. Rails-owner command never starts processing; metadata and blobs persist but points never load. |
| `integrations.airtrail_flights` | P1 conditional / O | Daily/manual AirTrail sync | y — AirTrail.ImportFlightsWorker | Native owner queues native flight import; Rails-owner reverse route never fetches flights. |
| `integrations.teslamate_sync` | P1 conditional / O | Scheduled TeslaMate sync | y — Imports.Teslamate.SyncWorker | Native owner queues native sync; Rails-owner reverse route never imports locations; TeslaMate native followups are separately listed. |
| `integrations.trek_sync` | P1 conditional / O | Scheduled Trek sync | y — Imports.Trek.SyncWorker | Native owner queues native sync; Rails-owner reverse route never imports flights. |
| `points.anomaly_backfill` | P1 conditional / O | Request anomaly reset/recalculation API | y — Points.AnomalyBackfillWorker | Native owner writes outbox; Rails-owner reverse request remains pending. |
| `points.anomaly_recalculate` | P1 conditional / O/H | Flag anomalies and recalculate impacted tracks, or edit points | y — Points.AnomalyFilter.RecalculateWorker / Tracks.RecalculateWorker | Native owner writes outbox/executes native track recalculation; Rails-owner fallback leaves tracks stale. |
| `posters.created` | P1 conditional / O | Create a poster | y — Posters.CreateWorker | Native owner writes job_outbox; Rails-owner reverse row never generates the poster. |
| `release.anomalies` | P1 conditional / D | Registered release reverse kinds; native release commands | y — ReleaseOperations.Anomalies / AnomaliesUser / PerTracker | No Phoenix reverse insertion site found; native release workers registered. Accepted legacy reverse payloads need disposition. |
| `release.anomalies_user` | P1 conditional / D | Registered release reverse kinds; native release commands | y — ReleaseOperations.Anomalies / AnomaliesUser / PerTracker | No Phoenix reverse insertion site found; native release workers registered. Accepted legacy reverse payloads need disposition. |
| `release.per_tracker` | P1 conditional / D | Registered release reverse kinds; native release commands | y — ReleaseOperations.Anomalies / AnomaliesUser / PerTracker | No Phoenix reverse insertion site found; native release workers registered. Accepted legacy reverse payloads need disposition. |
| `stats.calculate_month` | P1 / O/U | Stats scheduling and point-position changes | y — Stats.CalculateMonthWorker | Normal scheduling uses native owner; API position effect emits reverse directly with a different payload. Its months can remain stale. |
| `stats.full_recalculation` | P1 conditional / D | Registered reverse kind; Phoenix recalculation root uses native command directly | y — Stats.FullRecalculationWorker | No Phoenix reverse insertion site found; retained/accepted reverse payload needs Rails disposition, while native root is executable. |
| `tracks.backfill` | P1 / O/U | Point arrivals/backfill and TeslaMate sync | y — Tracks.BackfillWorker / BackfillCommands.ingest | Intake uses native ownership-aware scheduler; TeslaMate unconditionally emits timestamp-form reverse payload, unlike native cycle-form payload. Its backfill can stay unscheduled even when registry is claimed. |
| `tracks_generate_range` | P1 conditional / O | Backfill/daily/throttled track generation fanout | y — Tracks.RangeWorker | Native owner queues native child; Rails owner leaves generation window unprocessed. |
| `tracks_throttled_backfill` | P1 conditional / O | Schedule Cloud throttled track backfill or its next continuation | y — Tracks.ThrottledBackfillWorker | Native owner persists and queues native continuation; Rails-owner reverse scheduling never progresses. |
| `trips.calculate` | P1 conditional / O | Import Trek flight/trip or calculate trip stats | y — Trips.CalculateWorker | Trek path has Rails-owner reverse branch; browser trip action refuses non-native ownership before writing. Reverse route leaves trip stats stale. |
| `users.export_data` | P1 conditional / O | Export full account backup | y — UserData.ExportWorker | Native owner writes outbox; pinned/unclaimed Rails route leaves backup absent indefinitely. |
| `users.import_data` | P1 conditional / O | Restore account archive | y — UserData.ImportWorker | Native owner writes outbox; Rails owner accepts upload but never restores it. Source archive persists. |
| `users.recalculate_data` | P1 conditional / D | Registered reverse kind; native settings recalculation producer | y — Users.RecalculateWorker | No Phoenix reverse insertion site found; native producer/outbox consumer exists. Preexisting reverse payload is not consumed natively. |
| `enhanced_import_card` | P2 / U | Enhanced GPX extraction changes an import | n — exact Rails enhanced-card broadcaster absent | Enhanced-import card can stay stale; native events on some paths are separate. |
| `geocode_recent_points` | P2 / U | Native realtime track generation finishes | y — Geocoding.ReversePointWorker; recent-point selection/dedupe fanout absent | Recently tracked points keep missing geodata. |
| `imports.destroy_complete` | P2 / U | Start/progress/finish import deletion | n — exact Rails status/complete Turbo effects absent; native Imports.Events exists | Rails-facing progress and completion broadcasts/notification effects are absent; native LiveView refresh is separate. |
| `imports.destroy_status` | P2 / U | Start/progress/finish import deletion | n — exact Rails status/complete Turbo effects absent; native Imports.Events exists | Rails-facing progress and completion broadcasts/notification effects are absent; native LiveView refresh is separate. |
| `imports.progress` | P2 / U | GPX/normal import progress/completion | n — exact Rails Turbo row renderer absent; native Imports.Events/PubSub refresh exists | Rails/Turbo import rows do not refresh; native LiveView subscribers still refresh. Not primary import data loss. |
| `reverse_geocode_place` | P2 / U | Create/change a place via visit/location processing | y — Geocoding.ReversePlaceWorker; payload/ownership admission absent | Place country/city/address stays unfilled; native worker alone does not consume this reverse row. |
| `tracks_realtime_retrigger` | P2 / U | Realtime generation detects a race | y — Tracks.RealtimeWorker; debounce/retrigger absent | Track race recovery is never scheduled; cron/backfill may eventually repair. |
| `transport_progress` | P2 / U | Reclassify transportation tracks with progress reporting | n — exact deduplicated progress counter consumer absent | Progress remains running/stale although actual track classification may finish. |
| `achievements.bulk_check_leaf` | P2 conditional / O | Cron/manual bulk achievement fanout | y — Achievements.CheckWorker | Native owner queues child; Rails-owner reverse leaf never checks achievements. |
| `achievements.check` | P2 / O/U | Point editing and anomaly backfill achievement followup | y — Achievements.CheckWorker | Anomaly backfill selects owner; point editing emits reverse unconditionally. Those edits do not update achievements. |
| `digests.calculate_month` | P2 conditional / O | Monthly digest scheduling | y — Digests.MonthlyWorker | Native owner queues native digest; Rails-owner reverse route leaves monthly digest absent/stale. |
| `digests.calculate_year` | P2 conditional / O | Yearly digest scheduling | y — Digests.YearlyWorker | Native owner queues native digest; Rails-owner reverse route leaves yearly digest absent/stale. |
| `digests.email_month` | P2 conditional / O | Monthly digest mail | y — Mail.Digests.MonthlyWorker via mail.digest.monthly | Native owner writes outbox; Rails-owner reverse route sends no monthly email. |
| `digests.email_year` | P2 conditional / O | Yearly digest mail | y — Mail.Digests.YearlyWorker via mail.digest.yearly | Native owner writes outbox; Rails-owner reverse route sends no yearly email. |
| `geocoding.reverse_point` | P2 conditional / O | Point edit or nightly reverse-geocoding batch | y — Geocoding.ReversePointWorker | Native owner queues native worker/outbox; Rails-owner reverse route leaves point geodata unfilled. |
| `imports.prepare_download` | P2 conditional / O/H | Download an import that needs preparation, or ownership fallback | y — Imports.PrepareDownloadWorker | Native owner generates download; reverse route remains queued with no prepared download. |
| `mail.family_lapse` | P2 conditional / O | Family owner plan lapses | y — Mail.FamilyLapseWorker | Native owner writes outbox; Rails-owner reverse route sends no lapse notice. |
| `place_name_fetch` | P2 conditional / O | Create/edit visit/place or bulk place-name fanout | y — Places.NameFetchWorker | Native owner writes outbox/child; Rails-owner reverse row leaves place unnamed. |
| `places_bulk_name_fetch` | P2 conditional / O | Request bulk place-name fetch | y — Places.BulkNameFetchWorker | Native owner queues native bulk fanout; Rails-owner reverse root remains unprocessed. |
| `places_delete_if_orphan` | P2 conditional / O | Delete visits/place references | y — Places.DeleteIfOrphanWorker | Native owner writes native children; Rails-owner reverse route leaves orphan place rows. |
| `places_orphan_cleanup` | P2 conditional / O | Request orphan-place cleanup / child handoff | y — Places.OrphanCleanupWorker | Native owner queues native cleanup; Rails-owner route leaves orphan places. |
| `posters.progress` | P2 conditional / D | Retained reverse progress kind; native poster generation | y — Posters.ProgressWorker (native child) | No Phoenix reverse insertion found; native Command.progress always queues native worker and native Cable publication. |
| `release_achievements_bulk_check` | P2 conditional / O | Release achievement backfill | y — Achievements.BulkCheckWorker | Native owner queues stable native bulk root; Rails-owner reverse root remains unprocessed. |
| `visits.suggest` | P2 conditional / O | Nightly visit suggestion fanout | y — Visits.SuggestWorker | Native owner queues native suggestion; Rails-owner reverse route leaves visits absent. |
| `cache.preheat_sweep` | P3 / U | Daily cache-preheating cron | n — PreheatSweepWorker only delegates; no native global-warming sweep | Cron successfully emits unconsumed reverse rows; boot/global warming absent. Ruling 8 retirement needs its prescribed proof/drain; no silent retirement here. |
| `cache.preheat_user` | P3 resolved / P3 pin / fixed/O | Per-user cache preheating schedule | y — Cache.PreheatUserWorker; standalone :oban path wired here | Standalone native owner warms native digests directly with stable identity/zone/due time. Explicit pinned Rails owner still queues reverse work and needs operator disposition. |

## Registry startup and mail census

Standalone returns `Jobs.Registry.entries()` (all 97), rather than `Registry.claimable()` (all these rollout entries still advertise `claimable: false`). Runtime installs that list in `:job_entries`; Jobs.Supervisor starts Relay/HealthRefresher/Claimer, and Claimer.claim_all calls claim on every selected entry without filtering the rollout flag. Application starts Oban with the registry crontab. Claimer waits for release readiness and respects pins and legacy-scheduler/foreign ownership fences. No top-level registry worker is omitted specifically by standalone. Do not remove these fences or forcibly claim a pinned Sidekiq owner to make a test pass.

Native children that need no top-level ownership registration include export/poster/pending-import storage purge workers, poster progress, import continuations, recovery mail and test-email work. They run on the already configured Oban queues. Ordinary mail registry entries include family invitation/lapse, welcome, archival warning, OAuth link and account-destroy confirmation plus explore-features mail. ResidualEntries adds **mail.family_location_request**, **mail.digest.monthly**, **mail.digest.yearly**; all are in standalone's 97-entry list. ResidualCommands and LapseNotices select native outbox after ownership is Oban; only their explicit Rails-owner branches depend on Rails.

Recovery.MailWorker.enqueue inserts directly into Oban; native SMTP transport/config still governs deliverability. DeviseResidual renders email/password-change messages natively. TestEmailWorker and Mail.Delivery do not enqueue Sidekiq. Source search for LPUSH/RPUSH and Sidekiq payload/enqueue code found **no direct Phoenix Sidekiq Redis queue writer**. `:sidekiq` selection in Phoenix producers means reverse commands or admission rejection, not a direct Redis enqueue. Sidekiq metrics aggregation/operator redirects/native-command classification are read/route/CLI surfaces, not work producers.

The complete registered top-level inventory follows. Each has native core consumer **y**; any Rails-only nested work is separately listed in the reverse table above. Production actions which only write `job_outbox` are consumed natively by Dispatch; decoder errors/unknown accepted payloads are quarantined, not silently dropped. Retained unknown/dead/retired work and reverse rows require disposition before shutdown (ruling 10), and were not deleted here.

| Registry key | Native worker |
| --- | --- |
| `command:posters.create` | `Dawarich.Posters.CreateWorker` |
| `cron:route_videos_purge_job` | `Dawarich.RouteVideos.PurgeWorker` |
| `command:imports.destroy` | `Dawarich.Imports.DestroyWorker` |
| `command:imports.prepare_download` | `Dawarich.Imports.PrepareDownloadWorker` |
| `command:points.anomaly_recalculate` | `Dawarich.Points.AnomalyFilter.RecalculateWorker` |
| `command:imports.process_gpx` | `Dawarich.Imports.ProcessGpxWorker` |
| `cron:app_version_checking_job` | `Dawarich.AppVersion.CheckWorker` |
| `command:users.explore_features_mail` | `Dawarich.Mail.ExploreFeaturesWorker` |
| `command:trips.calculate` | `Dawarich.Trips.CalculateWorker` |
| `cron:nightly_family_invitations_cleanup_job` | `Dawarich.Families.InvitationCleanupWorker` |
| `cron:family_location_requests_expiry_job` | `Dawarich.Families.LocationRequestExpiryWorker` |
| `cron:points_counter_correction_job` | `Dawarich.Users.PointsCounterCorrectionWorker` |
| `command:exports.points` | `Dawarich.Exports.PointsWorker` |
| `command:mail.family_invitation` | `Dawarich.Mail.FamilyInvitationWorker` |
| `command:mail.family_lapse` | `Dawarich.Mail.FamilyLapseWorker` |
| `command:mail.user.welcome` | `Dawarich.Mail.WelcomeWorker` |
| `command:mail.user.archival_approaching` | `Dawarich.Mail.ArchivalApproachingWorker` |
| `command:mail.user.oauth_account_link` | `Dawarich.Mail.OauthAccountLinkWorker` |
| `command:mail.user.account_destroy_confirmation` | `Dawarich.Mail.AccountDestroyConfirmationWorker` |
| `cron:lite_archival_warning_job` | `Dawarich.Lite.ArchivalWarningWorker` |
| `command:achievements.check` | `Dawarich.Achievements.CheckWorker` |
| `command:areas.relabel_visits` | `Dawarich.Areas.RelabelWorker` |
| `command:imports.update_points_count` | `Dawarich.Imports.UpdatePointsCountWorker` |
| `command:imports.airtrail_flights` | `Dawarich.AirTrail.ImportFlightsWorker` |
| `command:tracks.generate_range` | `Dawarich.Tracks.RangeWorker` |
| `command:tracks.generate_realtime` | `Dawarich.Tracks.RealtimeWorker` |
| `command:tracks.recalculate` | `Dawarich.Tracks.RecalculateWorker` |
| `command:transportation.reclassify_track` | `Dawarich.Transportation.ReclassifyTrackWorker` |
| `cron:daily_track_generation_job` | `Dawarich.Tracks.DailyWorker` |
| `command:geocoding.reverse_point` | `Dawarich.Geocoding.ReversePointWorker` |
| `command:geocoding.reverse_place` | `Dawarich.Geocoding.ReversePlaceWorker` |
| `command:visits.suggest` | `Dawarich.Visits.SuggestWorker` |
| `command:visits.full_history_redetect` | `Dawarich.Visits.RedetectWorker` |
| `command:enhanced_import.extract_gpx` | `Dawarich.EnhancedImport.ExtractGpxWorker` |
| `command:enhanced_import.destroy_gpx` | `Dawarich.EnhancedImport.DestroyGpxWorker` |
| `command:stats.calculate_month` | `Dawarich.Stats.CalculateMonthWorker` |
| `cron:stats_toponyms_refresh_job` | `Dawarich.Stats.ToponymsRefreshWorker` |
| `cron:bulk_stats_calculating_job` | `Dawarich.Stats.BulkSweepWorker` |
| `command:stats.full_recalculation` | `Dawarich.Stats.FullRecalculationWorker` |
| `command:users.recalculate_data` | `Dawarich.Users.RecalculateWorker` |
| `command:points.anomaly_backfill` | `Dawarich.Points.AnomalyBackfillWorker` |
| `command:release.anomalies` | `Dawarich.ReleaseOperations.Anomalies` |
| `command:release.anomalies_user` | `Dawarich.ReleaseOperations.AnomaliesUser` |
| `command:release.per_tracker` | `Dawarich.ReleaseOperations.PerTracker` |
| `command:release.achievements_backfill` | `Dawarich.ReleaseOperations.Achievements` |
| `command:release.import_backfill` | `Dawarich.ReleaseOperations.ImportBackfill` |
| `command:release.point_dimensions_country` | `Dawarich.ReleaseOperations.PointBackfill` |
| `command:release.route_opacity` | `Dawarich.ReleaseOperations.RouteOpacity` |
| `command:release.onboarding_completed` | `Dawarich.ReleaseOperations.OnboardingCompleted` |
| `command:release.orphaned_tracks` | `Dawarich.ReleaseOperations.OrphanedTracks` |
| `command:release.tracks_dedup` | `Dawarich.ReleaseOperations.TracksDedup` |
| `command:release.place_name_locks` | `Dawarich.ReleaseOperations.PlaceNameLocks` |
| `command:release.time_anchor` | `Dawarich.ReleaseOperations.TimeAnchor` |
| `command:release.transportation` | `Dawarich.ReleaseOperations.Transportation` |
| `command:release.visits_fleet_redetect` | `Dawarich.ReleaseOperations.VisitsFleetRedetect` |
| `command:release.null_island` | `Dawarich.ReleaseOperations.NullIsland` |
| `command:release.motion_data` | `Dawarich.ReleaseOperations.MotionData` |
| `command:release.altitude` | `Dawarich.ReleaseOperations.Altitude` |
| `cron:raw_data_archive_job` | `Dawarich.RawData.ArchiveWorker` |
| `cron:raw_data_verify_job` | `Dawarich.RawData.VerifyWorker` |
| `cron:raw_data_clear_job` | `Dawarich.RawData.ClearWorker` |
| `command:imports.trek_import` | `Dawarich.Imports.Trek.ImportWorker` |
| `command:imports.trek_sync` | `Dawarich.Imports.Trek.SyncWorker` |
| `command:imports.teslamate_sync` | `Dawarich.Imports.Teslamate.SyncWorker` |
| `cron:stale_jobs_recovery_job` | `Dawarich.Imports.StaleWorker` |
| `cron:watcher_job` | `Dawarich.Imports.WatcherWorker` |
| `command:imports.photoprism_geodata` | `Dawarich.Imports.Integrations.PhotoprismWorker` |
| `command:imports.immich_geodata` | `Dawarich.Imports.Integrations.ImmichWorker` |
| `command:imports.process_normal` | `Dawarich.Imports.ProcessWorker` |
| `command:users.import_data` | `Dawarich.UserData.ImportWorker` |
| `command:users.export_data` | `Dawarich.UserData.ExportWorker` |
| `command:digests.calculate_month` | `Dawarich.Digests.MonthlyWorker` |
| `command:digests.calculate_year` | `Dawarich.Digests.YearlyWorker` |
| `cron:monthly_digest_scheduling_job` | `Dawarich.Digests.MonthlyScheduleWorker` |
| `cron:yearly_digest_scheduling_job` | `Dawarich.Digests.YearlyScheduleWorker` |
| `command:mail.family_location_request` | `Dawarich.Mail.LocationRequestWorker` |
| `command:mail.digest.monthly` | `Dawarich.Mail.Digests.MonthlyWorker` |
| `command:mail.digest.yearly` | `Dawarich.Mail.Digests.YearlyWorker` |
| `command:cache.preheat_user` | `Dawarich.Cache.PreheatUserWorker` |
| `cron:cache_preheating_job` | `Dawarich.Cache.PreheatSweepWorker` |
| `command:tracks.backfill` | `Dawarich.Tracks.BackfillWorker` |
| `command:tracks.throttled_backfill` | `Dawarich.Tracks.ThrottledBackfillWorker` |
| `command:families.auto_create` | `Dawarich.Families.AutoCreateWorker` |
| `command:families.member_sync` | `Dawarich.Families.MemberSyncWorker` |
| `command:places.delete_if_orphan` | `Dawarich.Places.DeleteIfOrphanWorker` |
| `command:places.orphan_cleanup` | `Dawarich.Places.OrphanCleanupWorker` |
| `command:places.name_fetch` | `Dawarich.Places.NameFetchWorker` |
| `command:places.bulk_name_fetch` | `Dawarich.Places.BulkNameFetchWorker` |
| `command:achievements.bulk_check` | `Dawarich.Achievements.BulkCheckWorker` |
| `cron:airtrail_flight_import_job` | `Dawarich.AirTrail.SyncSchedulingWorker` |
| `cron:teslamate_sync_job` | `Dawarich.Integrations.TeslaMateSchedulingWorker` |
| `cron:trek_sync_job` | `Dawarich.Integrations.TrekSchedulingWorker` |
| `cron:achievements_bulk_check_job` | `Dawarich.Achievements.BulkCheckWorker` |
| `cron:pending_imports_cleanup` | `Dawarich.PendingImports.CleanupWorker` |
| `cron:nightly_reverse_geocoding_job` | `Dawarich.Geocoding.NightlyWorker` |
| `cron:visit_suggesting_job` | `Dawarich.Visits.BulkSweepWorker` |
| `command:visits.bulk_suggest` | `Dawarich.Visits.BulkSweepWorker` |

## Native forwarding producers and their user actions

| Producer/action | Forward work and consumer | Rails dependency |
| --- | --- | --- |
| Posters create/delete/progress | posters.create; CreateWorker plus PurgeWorker/ProgressWorker children | ownership-selected reverse fallback for create/purge only |
| Point export / full-account export / archive restore | exports.points, users.export_data, users.import_data | ownership-selected reverse fallback; restore PointWriter still emits tile invalidation |
| Upload / OAuth pending upload claim / watcher / photo integrations | imports.process_gpx, imports.process_normal, users.import_data | format/ownership-selected upload reverse fallback; both native import engines emit progress/postprocessing effects |
| Import delete and enhanced extraction/delete | imports.destroy, enhanced_import.extract_gpx, enhanced_import.destroy_gpx | ownership fallback plus unconditional deletion callbacks and prepared-blob purge |
| Import download preparation | imports.prepare_download | ownership/lease fallback; native preparation does not replace prepared-download blob purge |
| Import postprocessing | tracks.generate_range, imports.update_points_count | native outbox selected for command step; stats/visits/extract reverse steps unconditional |
| Location ingestion / position edit / point move/delete / anomaly backfill | tracks.backfill/recalculate, geocoding.reverse_point, points.anomaly_backfill, points.anomaly_recalculate, achievements.check | reverse-only arrival effects, delete composite and several edit/anomaly dependent effects remain |
| Trips and Trek imports | trips.calculate | browser rejects non-native owner; Trek import has reverse fallback |
| Stats requests / periodic recalculation / toponyms | stats.full_recalculation, stats.calculate_month | month owner fallback; native completion emits cache invalidation |
| Visit requests / periodic suggestions / cleanup | visits.suggest, visits.bulk_suggest, visits.full_history_redetect; places.* children | native consumers active, web redetect still reverse-only; visit-summary cache effects remain |
| Track backfill/daily/realtime/transportation | tracks.generate_range/realtime/backfill/throttled_backfill/recalculate, transportation.reclassify_track | native computations active; tracks_changed, recent geocode, retrigger, progress still reverse |
| Families invitation/location requests/lapse/maintenance | mail.family_invitation, mail.family_location_request, mail.family_lapse; families.auto_create/member_sync; maintenance cron | residual/lapse mail owner fallback; live point broadcaster absent; family core native |
| User/auth lifecycle and notifications | mail.user.*, users.explore_features_mail; direct recovery mail/TestEmailWorker/Mail.Delivery | native consumers/transport; no direct Sidekiq enqueue |
| Monthly/yearly digests | digests.calculate_month/year and mail.digest.monthly/yearly | native core active; calculation/mail owner reverse fallback |
| Release data operations | release.* registered workers | native top-level active; transport/visits/null-island followups plus cache/tile/track effects still reverse |
| Raw-data archive/verify/clear | raw_data_* cron workers | native core consumers registered; no new reverse insertion sites found |
| App-version/points counter/family cleanup/pending cleanup/state purge | native cron workers | native core consumers registered; no new reverse insertion sites found |
| Cache warming | cache.preheat_user / cron:cache_preheating_job | per-user native scheduling fixed; sweep still only delegates |

## Source call-site census

The following includes **every direct RailsCommands.insert! call site** found under `app-phoenix/lib` after the fixes, with dynamic producer expansions described below. It deliberately includes owner fallback and dormant compatibility paths. References use repository-relative paths and line numbers; no runtime allocations or secrets are recorded.

| Call site | Reverse kind / dynamic selector |
| --- | --- |
| `app-phoenix/lib/dawarich/achievements/bulk_check.ex:89` | `achievements.bulk_check_leaf` |
| `app-phoenix/lib/dawarich/air_trail/flights.ex:128` | `airtrail_stats` |
| `app-phoenix/lib/dawarich/areas.ex:107` | `visit_months_changed` |
| `app-phoenix/lib/dawarich/cache/preheat_sweep_worker.ex:26` | `cache.preheat_sweep` |
| `app-phoenix/lib/dawarich/cache/schedule.ex:34` | `cache.preheat_user` |
| `app-phoenix/lib/dawarich/digests/schedule.ex:35` | `type` |
| `app-phoenix/lib/dawarich/exports/delete.ex:44` | `exports.purge` |
| `app-phoenix/lib/dawarich/families/lapse_notices.ex:44` | `mail.family_lapse` |
| `app-phoenix/lib/dawarich/geocoding/nightly_sweep.ex:109` | `stats.caches_invalidated` |
| `app-phoenix/lib/dawarich/geocoding/nightly_sweep.ex:125` | `geocoding.reverse_point` |
| `app-phoenix/lib/dawarich/imports/bulk_writer.ex:32` | `points.tile_epoch` |
| `app-phoenix/lib/dawarich/imports/bulk_writer.ex:54` | `points.tile_epoch` |
| `app-phoenix/lib/dawarich/imports/destroy.ex:68` | `imports.destroy_requested` |
| `app-phoenix/lib/dawarich/imports/destroy_effects.ex:17` | `kind` |
| `app-phoenix/lib/dawarich/imports/destroy_effects.ex:37` | `points.tile_epoch` |
| `app-phoenix/lib/dawarich/imports/destroy_effects.ex:58` | `visit_months_changed` |
| `app-phoenix/lib/dawarich/imports/destroy_handover.ex:79` | `kind` |
| `app-phoenix/lib/dawarich/imports/download_producer.ex:57` | `imports.prepare_download` |
| `app-phoenix/lib/dawarich/imports/gpx_handover.ex:142` | `imports.resume` |
| `app-phoenix/lib/dawarich/imports/gpx_lifecycle.ex:125` | `imports.progress` |
| `app-phoenix/lib/dawarich/imports/gpx_progress.ex:30` | `imports.progress` |
| `app-phoenix/lib/dawarich/imports/import_blob_purges.ex:57` | `imports.prepared_download_purge` |
| `app-phoenix/lib/dawarich/imports/integrations/photo_import_record.ex:233` | `imports.upload_created` |
| `app-phoenix/lib/dawarich/imports/manual_extraction.ex:65` | `kind` |
| `app-phoenix/lib/dawarich/imports/normal_handover.ex:164` | `imports.normal_resume` |
| `app-phoenix/lib/dawarich/imports/normal_lifecycle.ex:149` | `imports.progress` |
| `app-phoenix/lib/dawarich/imports/postprocessing/commands.ex:8` | `imports.postprocessing_step` |
| `app-phoenix/lib/dawarich/imports/prepare_download_worker.ex:162` | `imports.prepare_download` |
| `app-phoenix/lib/dawarich/imports/teslamate/effects.ex:45` | `kind` |
| `app-phoenix/lib/dawarich/imports/trek/records.ex:104` | `trips.calculate` |
| `app-phoenix/lib/dawarich/imports/upload_records.ex:68` | `imports.upload_created` |
| `app-phoenix/lib/dawarich/ingest/intake.ex:92` | `points.tile_epoch` |
| `app-phoenix/lib/dawarich/ingest/intake.ex:182` | `kind` |
| `app-phoenix/lib/dawarich/integrations/sync_scheduling.ex:103` | `integrations.airtrail_flights` |
| `app-phoenix/lib/dawarich/integrations/sync_scheduling.ex:124` | `integrations.teslamate_sync` |
| `app-phoenix/lib/dawarich/integrations/sync_scheduling.ex:127` | `integrations.trek_sync` |
| `app-phoenix/lib/dawarich/mail/residual_commands.ex:51` | `reverse` |
| `app-phoenix/lib/dawarich/pending_imports/claim.ex:77` | `imports.upload_created` |
| `app-phoenix/lib/dawarich/places/bulk_name_fetch_worker.ex:39` | `places_bulk_name_fetch` |
| `app-phoenix/lib/dawarich/places/bulk_name_fetch_worker.ex:64` | `place_name_fetch` |
| `app-phoenix/lib/dawarich/places/job_commands.ex:13` | `place_name_fetch` |
| `app-phoenix/lib/dawarich/places/job_commands.ex:26` | `places_delete_if_orphan` |
| `app-phoenix/lib/dawarich/places/job_commands.ex:36` | `places_orphan_cleanup` |
| `app-phoenix/lib/dawarich/places/job_commands.ex:43` | `places_bulk_name_fetch` |
| `app-phoenix/lib/dawarich/places/orphan_cleanup_worker.ex:48` | `places_orphan_cleanup` |
| `app-phoenix/lib/dawarich/point_exports.ex:81` | `exports.points_created` |
| `app-phoenix/lib/dawarich/points/anomaly_backfill.ex:73` | `points.tile_epoch` |
| `app-phoenix/lib/dawarich/points/anomaly_backfill_worker.ex:114` | `kind` |
| `app-phoenix/lib/dawarich/points/anomaly_filter/effects.ex:26` | `points.tile_epoch` |
| `app-phoenix/lib/dawarich/points/anomaly_filter/effects.ex:50` | `points.anomaly_stats` |
| `app-phoenix/lib/dawarich/points/anomaly_filter/effects.ex:80` | `points.anomaly_recalculate` |
| `app-phoenix/lib/dawarich/points/anomaly_filter/recalculate_worker.ex:38` | `points.anomaly_recalculate` |
| `app-phoenix/lib/dawarich/points/api_anomaly.ex:53` | `points.anomaly_backfill` |
| `app-phoenix/lib/dawarich/points/api_position.ex:122` | `points.tile_epoch` |
| `app-phoenix/lib/dawarich/points/api_position.ex:135` | `stats.calculate_month` |
| `app-phoenix/lib/dawarich/points/api_position.ex:142` | `achievements.check` |
| `app-phoenix/lib/dawarich/points/api_writes.ex:68` | `kind` |
| `app-phoenix/lib/dawarich/points/api_writes.ex:167` | `points.anomaly_recalculate` |
| `app-phoenix/lib/dawarich/points/api_writes.ex:174` | `kind` |
| `app-phoenix/lib/dawarich/points/api_writes.ex:220` | `points.web_destroy_follow_up` |
| `app-phoenix/lib/dawarich/points/web_destroy.ex:74` | `points.web_destroy_follow_up` |
| `app-phoenix/lib/dawarich/posters/command.ex:24` | `posters.created` |
| `app-phoenix/lib/dawarich/posters/command.ex:29` | `posters.purge` |
| `app-phoenix/lib/dawarich/rails_effects.ex:8` | `points.tile_epoch` |
| `app-phoenix/lib/dawarich/rails_effects.ex:15` | `schedule_untracked_tracks` |
| `app-phoenix/lib/dawarich/rails_effects.ex:22` | `enhanced_import_card` |
| `app-phoenix/lib/dawarich/rails_effects.ex:32` | `visit_months_changed` |
| `app-phoenix/lib/dawarich/rails_effects.ex:48` | `reverse_geocode_place` |
| `app-phoenix/lib/dawarich/release_operations/achievements.ex:64` | `release_achievements_bulk_check` |
| `app-phoenix/lib/dawarich/release_operations/null_island.ex:51` | `release_null_island_follow_up` |
| `app-phoenix/lib/dawarich/release_operations/orphaned_tracks.ex:53` | `tracks_changed` |
| `app-phoenix/lib/dawarich/release_operations/transportation.ex:52` | `release_reclassify_tracks` |
| `app-phoenix/lib/dawarich/release_operations/visits_fleet_redetect.ex:43` | `release_user_redetect` |
| `app-phoenix/lib/dawarich/route_videos/writes.ex:129` | `route_videos.attachment_job` |
| `app-phoenix/lib/dawarich/route_videos/writes.ex:160` | `route_videos.attachment_job` |
| `app-phoenix/lib/dawarich/stats/calculate_month.ex:133` | `stats.caches_invalidated` |
| `app-phoenix/lib/dawarich/stats/refresh_toponyms.ex:62` | `stats.caches_invalidated` |
| `app-phoenix/lib/dawarich/stats/schedule.ex:34` | `stats.calculate_month` |
| `app-phoenix/lib/dawarich/tracks/backfill_commands.ex:43` | `tracks.backfill` |
| `app-phoenix/lib/dawarich/tracks/backfill_commands.ex:91` | `tracks_throttled_backfill` |
| `app-phoenix/lib/dawarich/tracks/backfill_worker.ex:95` | `tracks_generate_range` |
| `app-phoenix/lib/dawarich/tracks/daily_worker.ex:121` | `tracks_generate_range` |
| `app-phoenix/lib/dawarich/tracks/effects.ex:16` | `tracks_changed` |
| `app-phoenix/lib/dawarich/tracks/realtime_worker.ex:53` | `geocode_recent_points` |
| `app-phoenix/lib/dawarich/tracks/realtime_worker.ex:65` | `tracks_realtime_retrigger` |
| `app-phoenix/lib/dawarich/tracks/throttled_backfill.ex:77` | `tracks_generate_range` |
| `app-phoenix/lib/dawarich/tracks/throttled_backfill.ex:93` | `tracks_throttled_backfill` |
| `app-phoenix/lib/dawarich/transportation/reclassify_track_worker.ex:66` | `transport_progress` |
| `app-phoenix/lib/dawarich/user_data/import_commands.ex:43` | `@command` |
| `app-phoenix/lib/dawarich/user_data/restore/point_writer.ex:67` | `points.tile_epoch` |
| `app-phoenix/lib/dawarich/visits/bulk_sweep.ex:115` | `visits.suggest` |
| `app-phoenix/lib/dawarich/visits/web_settings.ex:42` | `visits.web_redetect` |
| `app-phoenix/lib/dawarich_web/user_data_controller.ex:29` | `users.export_data` |

Dynamic selectors were traced to their literals/callers: Intake.commands! chooses points.anomaly_filter, tracks.realtime, visits.realtime and points.live_broadcast (tracks.backfill uses BackfillCommands.ingest); TeslaMate.Effects.finalize chooses points.anomaly_filter/tracks.realtime/tracks.backfill; Points.ApiWrites chooses points.tile_epoch/achievements.check and ownership-selected geocoding.reverse_point/tracks.recalculate adapters; AnomalyBackfillWorker emits ownership-selected achievements.check. Digests.Schedule chooses digests.calculate_month/year; Mail.ResidualCommands selects family_location_request_mail and digests.email_month/year. ManualExtraction chooses imports.extraction_requested/extraction_destroy_requested. DestroyHandover chooses imports.destroy_requested/imports.destroy_terminal. DestroyEffects.insert! callers emit imports.destroy_status/callbacks/achievements/stats/complete. UserData.ImportCommands.@command is users.import_data. These expansions are all represented in the 78-kind table.

Postprocessing's step values were traced separately: schedule_stats, schedule_visit_suggesting, extract and ownership fallback command. Destroy callback steps are places_cleanup and reclassify_tracks. These composite kinds are not classified as fully native merely because their leaf consumers already exist.

Direct Cable publication is native via Cable.Bus (Redis/PgBus) and Cable.EventsRelay/PubSub. ShareManagement.Mutations emits its revoked event directly and does not insert share_management.live_revoked. Posters.Command.progress always inserts its native ProgressWorker. Missing Rails-rendered Cable effects are specifically imports.progress, enhanced_import_card, imports.destroy_status/complete, tracks_changed, points.live_broadcast, and the composite destruction/postprocessing callbacks above. CableProxy terminal rejection is distinct from producing a broadcast. Native broadcasts still require the configured Cable bus and native channel admission; this audit is not a browser/Cable deployment proof.

## Scope boundary

No large missing composite/debounce/broadcaster consumer was ported. Existing registry consumers are already selected/claimable in standalone, so no blanket ownership override was added. Only export storage deletion and the per-user cache schedule received native wiring. Remaining unconditional gaps above are explicit follow-up work, and pinned/unclaimed ownership/foreign-lease reverse work needs safe operator disposition. No production queue census, remote DB/storage, SSH, deployment, ownership cutover or accepted-payload deletion was performed.

The master plan's security-sensitive delegate rule prohibits AFFiNE writes for this assignment. Repository counterpart: `docs/phoenix/standalone-reverse-gaps.md`; this audit is also delivered to the controller under the assigned report filename. AFFiNE synchronization is intentionally pending an authorized controller update.

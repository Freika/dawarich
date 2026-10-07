# Standalone reverse gaps after H02

All 78 reverse kinds remain in the retained closure inventory. Native producer activation does not consume historical `phoenix.rails_commands` rows. No reverse poller, generic dispatcher, ownership rewrite, or accepted-work deletion is introduced.

The H02 enumeration test partitions every kind into 50 native consumption paths and the 28 explicit gaps below. Partial kinds are listed as gaps whenever another producer or historical payload still needs disposition. RX terminal tests prove their native domain effects; the H02 test verifies registry composition, configured child queues and actual point-effect/mail dispatch. This census is not a release/drain certificate.

| Known gap kind | Remaining contract |
| --- | --- |
| `achievements.bulk_check_leaf` | Bulk cron source-owner child selection awaits F G01-G04. |
| `cache.preheat_sweep` | Cron sweep still delegates; retirement and accepted-work disposition await cron/source work. |
| `cache.preheat_user` | Native warming exists, but retained Sidekiq pins still produce reverse work; CACHE/source activation deferred. |
| `exports.points_created` | RX-EXPORTS/source export producer activation is outside the merged tonight packages. |
| `geocoding.reverse_point` | Point edits are native; nightly source-owner fanout still awaits cron activation. |
| `imports.destroy_terminal` | Historical removed-state handback needs source payload and accepted-work disposition; no fresh standalone handback. |
| `imports.normal_resume` | Historical Ruby non-GPX resume envelopes require plan E disposition; standalone uses native lease recovery. |
| `imports.resume` | Historical Ruby GPX resume envelopes require plan E disposition; standalone uses native lease recovery. |
| `integrations.airtrail_flights` | Scheduler child ownership and source envelopes await plan E / F G01-G04. |
| `integrations.teslamate_sync` | Scheduler child ownership and source envelopes await plan E / F G01-G04. |
| `integrations.trek_sync` | Scheduler child ownership and source envelopes await plan E / F G01-G04. |
| `place_name_fetch` | RX-PLACES/source place ownership adapter is outside tonight merged packages. |
| `places_bulk_name_fetch` | RX-PLACES/source place ownership adapter is outside tonight merged packages. |
| `places_delete_if_orphan` | Import callbacks have direct native children; general place producer ownership awaits RX-PLACES/source work. |
| `places_orphan_cleanup` | RX-PLACES/source place ownership adapter is outside tonight merged packages. |
| `reverse_geocode_place` | Exact place producer adapter has not merged; a registered leaf worker alone does not close it. |
| `release.anomalies` | No fresh reverse insertion; historical accepted release payloads await plan E disposition. |
| `release.anomalies_user` | No fresh reverse insertion; historical accepted release payloads await plan E disposition. |
| `release.per_tracker` | No fresh reverse insertion; historical accepted release payloads await plan E disposition. |
| `release_achievements_bulk_check` | Release/source root ownership activation is deferred. |
| `release_null_island_follow_up` | Composite release followup has not merged in tonight packages. |
| `release_reclassify_tracks` | Release fleet fanout has not merged in tonight packages. |
| `release_user_redetect` | Release fleet fanout has not merged in tonight packages. |
| `tracks_generate_range` | Backfill children are native; daily scheduler child ownership awaits F G01-G04. |
| `trips.calculate` | Trek source producer ownership and historical payload disposition await plan E. |
| `users.export_data` | User-data source producer ownership/payload activation awaits plan E. |
| `users.import_data` | Native import upload routing exists; separate account archive source admission awaits plan E. |
| `users.recalculate_data` | Native recalculation exists; historical/source envelopes await plan E disposition. |

Plan E source payloads and F G01-G04 cron integration are outside tonight's scope. Seed 202 runs on the integration head. Coexistence retains explicit Rails-owner selection and all closure kinds. Standalone additions keep rollout claimable:false and never modify persisted source pins.

AFFiNE synchronization awaits the controller: the master execution plan's security-sensitive delegate boundary prohibits writes for this assignment. Repository counterpart is this document; the assigned controller report and gap list contain the evidence.

H02 mounts `Points.JobEntries.entries()` into the composed registry: tile epoch, live broadcast and anomaly arrival, each version 1 on the projections queue. Existing RX-TRACKS, RX-IMPORTS, RX-STATS, RX-MEDIA and RX-VISITS entries/direct children remain their merged producer implementations. Location-request and family-lapse mail now select existing native outbox/delivery workers in standalone even under a retained source pin; digest mail already does this. Delivery retains its recipient checks, claim identity and replay suppression.

The integration check exposed additional point-edit producer gaps: general API edits and position edits emitted achievement reverse commands unconditionally, and API geocoding/track recalculation still selected persisted source ownership. The minimum seams use existing CheckWorker (source-default notify:true and oldest timestamp), ReversePointWorker and RecalculateWorker in standalone. Flag-unset branches retain their prior payloads and owner selection. No new worker or queue is introduced.

Verification: `test/dawarich/a12f3b_h02_test.exs` owns the exhaustive census and registry/queue/callback checks, real point-effect outbox dispatch, real point edits, and native family SMTP-boundary delivery. The retained RX task tests additionally prove each domain's terminal effect; census module availability alone is not treated as that terminal proof. A source-pinned foreign lease is never overridden by this registry composition.

Merged producer reconciliation: TeslaMate standalone now reuses RX-POINTS anomaly/realtime entrypoints while retaining RX-TRACKS BackfillCommands and its legacy-ingest option for flag-unset parity. RX-POINTS' visits assertion follows the RX-VISITS durable visits.suggest outbox/debouncer contract, retaining timezone, lookback, delay, opt-out and Rails-owner assertions. No parallel visit scheduling path is activated.

Registry census integration: the retained Rails-job ownership table declares the three point effect keys as native producers, and the exact command-type census retains the Rails command set plus four named native point effect types (including the preexisting anomaly-recalculation compatibility worker). The H02 enumeration also checks the point keys have producer declarations. H01 test cleanup now restores absent application settings by deleting them; its existing route test exercises absence separately from an explicit nil value. This prevents test-order leakage without changing auth or routing production behavior.

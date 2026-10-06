# A12f-3a bootstrap contracts

Baseline: `8d6368fc3187db758151a4d401547d93612d26bb` (Rails 1.15.3 synchronized), branch `feat/a12f3a-o`, 2026-10-06. Scope O01–O05; O06–O08 are later integration. Source deletion, production ownership changes, deployment and release acceptance are excluded.

## O01: current-head route refresh

Read the controller census at `/Users/frey/projects/dawarich/.scratch/route-ownership/{route-ownership.md,classified-routes.json,phoenix-routes.json,rails-routes.json}`. Its revision is `4628a6659cf75db62b4cb09c813151268b01c630`. `git diff --stat` to the baseline for `config/routes.rb`, `app/controllers`, and `app-phoenix/lib/dawarich_web` is empty; all cited source registrations and dispatch anchors remain valid. The census is outside this worktree and is read-only. No new census driver or manifest was added.

The census has 374 unique method/path patterns: self-hosted 2 native, 195 conditional, 175 Rails, 2 redirect; its Cloud-unset comparison is 2/184/186/2. Unset defaults to self-hosted and is NOT explicit Cloud. `SELF_HOSTED=false` separately closes A8 actions/navigation/settings (`a8_gate.ex:6,58,63`), trips/places gates and self-hosted slices. Missing source methods remain distinct gaps. A native logged-out redirect does not establish authenticated parity. GET's HEAD behavior remains governed by `strangler.ex:85,100`, with native unsliced pages subject to the same gates and sliced HEAD handed back.

Every ledger row below retains optional format; dots, unsupported Accept/query/client/session envelopes still hand back. Unknown Cloud deployment flags and actual source backlog are not inferred. The master 125/78/24 aggregate belongs to sibling closure work, not this census.

| Method | Source path | Baseline class | Domain | Source registration |
|---|---|---|---|---|
| GET | `/settings/visits(.:format)` | CONDITIONAL | V | `config/routes.rb:68` |
| PATCH | `/settings/visits(.:format)` | CONDITIONAL | V | `config/routes.rb:68` |
| PUT | `/settings/visits(.:format)` | CONDITIONAL | V | `config/routes.rb:68` |
| GET | `/settings/users/export(.:format)` | CONDITIONAL | E | `config/routes.rb:75` |
| POST | `/settings/users/import(.:format)` | CONDITIONAL | E | `config/routes.rb:76` |
| POST | `/tracks/recalculation(.:format)` | RAILS | W | `config/routes.rb:92` |
| POST | `/visits/redetections(.:format)` | CONDITIONAL | V | `config/routes.rb:96` |
| GET | `/imports/:id/download(.:format)` | CONDITIONAL | I/F | `config/routes.rb:115` |
| DELETE | `/imports/:import_id/extraction(.:format)` | CONDITIONAL | I/F | `config/routes.rb:116` |
| POST | `/imports/:import_id/extraction(.:format)` | CONDITIONAL | I/F | `config/routes.rb:116` |
| GET | `/imports(.:format)` | CONDITIONAL | I/F | `config/routes.rb:114` |
| POST | `/imports(.:format)` | CONDITIONAL | I/F | `config/routes.rb:114` |
| GET | `/imports/new(.:format)` | CONDITIONAL | I/F | `config/routes.rb:114` |
| GET | `/imports/:id/edit(.:format)` | CONDITIONAL | I/F | `config/routes.rb:114` |
| GET | `/imports/:id(.:format)` | CONDITIONAL | I/F | `config/routes.rb:114` |
| PATCH | `/imports/:id(.:format)` | CONDITIONAL | I/F | `config/routes.rb:114` |
| PUT | `/imports/:id(.:format)` | RAILS | I/F | `config/routes.rb:114` |
| DELETE | `/imports/:id(.:format)` | CONDITIONAL | I/F | `config/routes.rb:114` |
| GET | `/tracks/:track_id/segments(.:format)` | CONDITIONAL | W | `config/routes.rb:119` |
| PATCH | `/tracks/:track_id/segments/:id(.:format)` | CONDITIONAL | W | `config/routes.rb:119` |
| PUT | `/tracks/:track_id/segments/:id(.:format)` | RAILS | W | `config/routes.rb:119` |
| GET | `/visits(.:format)` | CONDITIONAL | V | `config/routes.rb:129` |
| PATCH | `/visits/bulk_update(.:format)` | CONDITIONAL | V | `config/routes.rb:136` |
| DELETE | `/visits/bulk_destroy(.:format)` | CONDITIONAL | V | `config/routes.rb:137` |
| POST | `/visits/merge(.:format)` | CONDITIONAL | V | `config/routes.rb:138` |
| PATCH | `/visits/:id(.:format)` | CONDITIONAL | V | `config/routes.rb:134` |
| PUT | `/visits/:id(.:format)` | CONDITIONAL | V | `config/routes.rb:134` |
| DELETE | `/visits/:id(.:format)` | CONDITIONAL | V | `config/routes.rb:134` |
| POST | `/areas(.:format)` | RAILS | W | `config/routes.rb:141` |
| PATCH | `/areas/:id(.:format)` | RAILS | W | `config/routes.rb:141` |
| PUT | `/areas/:id(.:format)` | RAILS | W | `config/routes.rb:141` |
| GET | `/places/nearby(.:format)` | CONDITIONAL | P | `config/routes.rb:144` |
| GET | `/places(.:format)` | CONDITIONAL | P | `config/routes.rb:142` |
| POST | `/places(.:format)` | CONDITIONAL | P | `config/routes.rb:142` |
| GET | `/places/:id(.:format)` | CONDITIONAL | P | `config/routes.rb:142` |
| PATCH | `/places/:id(.:format)` | CONDITIONAL | P | `config/routes.rb:142` |
| PUT | `/places/:id(.:format)` | CONDITIONAL | P | `config/routes.rb:142` |
| DELETE | `/places/:id(.:format)` | CONDITIONAL | P | `config/routes.rb:142` |
| GET | `/exports(.:format)` | CONDITIONAL | E | `config/routes.rb:147` |
| POST | `/exports(.:format)` | CONDITIONAL | E | `config/routes.rb:147` |
| DELETE | `/exports/:id(.:format)` | CONDITIONAL | E | `config/routes.rb:147` |
| POST | `/route_videos(.:format)` | CONDITIONAL | R | `config/routes.rb:149` |
| DELETE | `/route_videos/:id(.:format)` | CONDITIONAL | R | `config/routes.rb:149` |
| POST | `/trips/:id/recalculate(.:format)` | CONDITIONAL | T | `config/routes.rb:152` |
| POST | `/trips/:id/export(.:format)` | CONDITIONAL | T | `config/routes.rb:153` |
| POST | `/trips/:trip_id/notes(.:format)` | CONDITIONAL | T | `config/routes.rb:155` |
| PATCH | `/trips/:trip_id/notes/:id(.:format)` | CONDITIONAL | T | `config/routes.rb:155` |
| PUT | `/trips/:trip_id/notes/:id(.:format)` | CONDITIONAL | T | `config/routes.rb:155` |
| DELETE | `/trips/:trip_id/notes/:id(.:format)` | CONDITIONAL | T | `config/routes.rb:155` |
| GET | `/trips(.:format)` | CONDITIONAL | T | `config/routes.rb:150` |
| POST | `/trips(.:format)` | CONDITIONAL | T | `config/routes.rb:150` |
| GET | `/trips/new(.:format)` | CONDITIONAL | T | `config/routes.rb:150` |
| GET | `/trips/:id/edit(.:format)` | CONDITIONAL | T | `config/routes.rb:150` |
| GET | `/trips/:id(.:format)` | CONDITIONAL | T | `config/routes.rb:150` |
| PATCH | `/trips/:id(.:format)` | CONDITIONAL | T | `config/routes.rb:150` |
| PUT | `/trips/:id(.:format)` | CONDITIONAL | T | `config/routes.rb:150` |
| DELETE | `/trips/:id(.:format)` | CONDITIONAL | T | `config/routes.rb:150` |
| GET | `/tags(.:format)` | CONDITIONAL | W | `config/routes.rb:180` |
| POST | `/tags(.:format)` | CONDITIONAL | W | `config/routes.rb:180` |
| GET | `/tags/new(.:format)` | CONDITIONAL | W | `config/routes.rb:180` |
| GET | `/tags/:id/edit(.:format)` | CONDITIONAL | W | `config/routes.rb:180` |
| PATCH | `/tags/:id(.:format)` | CONDITIONAL | W | `config/routes.rb:180` |
| PUT | `/tags/:id(.:format)` | CONDITIONAL | W | `config/routes.rb:180` |
| DELETE | `/tags/:id(.:format)` | CONDITIONAL | W | `config/routes.rb:180` |
| DELETE | `/points/bulk_destroy(.:format)` | CONDITIONAL | W | `config/routes.rb:207` |
| GET | `/points/:id/address(.:format)` | CONDITIONAL | W | `config/routes.rb:210` |
| GET | `/points(.:format)` | CONDITIONAL | W | `config/routes.rb:205` |
| PUT | `/stats/update_all(.:format)` | RAILS | Q | `config/routes.rb:218` |
| GET | `/stats(.:format)` | CONDITIONAL | Q | `config/routes.rb:216` |
| GET | `/insights/details(.:format)` | CONDITIONAL | Q | `config/routes.rb:231` |
| GET | `/insights(.:format)` | CONDITIONAL | Q | `config/routes.rb:229` |
| GET | `/stats/:year(.:format)` | CONDITIONAL | Q | `config/routes.rb:234` |
| GET | `/stats/:year/:month(.:format)` | CONDITIONAL | Q | `config/routes.rb:235` |
| PUT | `/stats/:year/:month/update(.:format)` | RAILS | Q | `config/routes.rb:236` |
| GET | `/shared/month/:uuid(.:format)` | RAILS | Q | `config/routes.rb:240` |
| PATCH | `/stats/:year/:month/sharing(.:format)` | RAILS | Q | `config/routes.rb:245` |
| GET | `/digests(.:format)` | CONDITIONAL | Q | `config/routes.rb:252` |
| POST | `/digests(.:format)` | RAILS | Q | `config/routes.rb:252` |
| GET | `/digests/:year(.:format)` | CONDITIONAL | Q | `config/routes.rb:252` |
| DELETE | `/digests/:year(.:format)` | RAILS | Q | `config/routes.rb:252` |
| GET | `/shared/digest/:uuid(.:format)` | RAILS | Q | `config/routes.rb:255` |
| PATCH | `/digests/:year/sharing(.:format)` | RAILS | Q | `config/routes.rb:256` |
| GET | `/map/v1(.:format)` | RAILS | M | `config/routes.rb:297` |
| GET | `/map/v2(.:format)` | CONDITIONAL | M | `config/routes.rb:298` |
| GET | `/map/timeline_feeds/:id/track_info(.:format)` | CONDITIONAL | M | `config/routes.rb:300` |
| GET | `/map/timeline_feeds/calendar(.:format)` | CONDITIONAL | M | `config/routes.rb:301` |
| GET | `/map/timeline_feeds(.:format)` | CONDITIONAL | M | `config/routes.rb:299` |
| GET | `/map/residency(.:format)` | CONDITIONAL | M | `config/routes.rb:303` |
| GET | `/map(.:format)` | CONDITIONAL | M | `config/routes.rb:307` |
| GET | `/maps/v2(.:format)` | RAILS | M | `config/routes.rb:308` |

## Admission and ownership boundary

`endpoint.ex:18,33` orders static/PublicFiles/AuthGate/Strangler/Router. `strangler.ex:85–110` resolves route, owner, numeric constraints, page envelope and domain gate BEFORE dispatch; `strangler.ex:78` proxies absent/refused routes. `strangler.ex:124–137` checks route prefix plus optional independent rails_key. Domain gate exceptions/exits return false at `strangler.ex:105–119`. `api/body.ex:108` retains raw bytes for replay. A12f-2 owns these global transport rules; this package does not broaden them.

`rails_form.ex:22–29` enforces content/header/method/session/user/origin/CSRF before writes. `a8_request.ex:21–55` and `map_write_request.ex:16–65` read/retain bytes, parse shape, assign action/method/format and call that admission. `imports_request.ex:24–30` admits after parsing. Their refusals are pre-effect replay. Post-effect recovery must not replay; later domain tasks must replace reachable source semantic refusals with terminal source-equivalent errors.

| Domain | Current HTTP key / dispatch | Reachable source residual | Final owner / disposition |
|---|---|---|---|
| Q | stats/digests/insights; rails_pages_routes.ex:41–56, insights_gate.ex | Stats/digest writes and public sharing lack routes; detail query/state gates remain | Q01–Q14 native results, O06 method/independent shared-key wiring; sibling cache owner |
| M | map; page_routes.ex:65–76, map_frame_routes.ex:17–32 | v1/maps-v2 redirects absent; frame legacy/Cloud envelopes refuse | M01–M07 retain both bookmarks and characterized failure, O06 wiring |
| W | tags/points/tracks; page_routes.ex:13–28, map_frame_routes.ex:8 | Segment PUT, areas POST/PATCH/PUT and track recalculation absent; segment_editor.ex:88–192 rolls back :rails | W01–W13 native writes/errors/worker, O06 areas key separate from map |
| P | places; a8_routes.ex:54–68, map_frame_routes.ex:36–44 | Places gates reject Cloud/legacy/provider shapes; CLI backfill/cleanup still source remedy | P01–P10 retain provider/aliases/errors; O02 focused seams, O06 wiring |
| I/F | imports; import_routes.ex:7–17, imports_gate.ex:6–22 | PUT absent, raw multipart unsupported, stored state gate, upload_admission.ex:58–87 legacy/empty formats | I/F retain all enum codecs/lineage/resume, O07 route wiring; unknown serialized work remains drain-owned |
| E | exports/user_data; export_routes.ex, user_data_routes.ex:32 | Restore/attachment/storage/payload admission and source reverse purge | E01–E06 native outcomes, O07 preserve independent user_data key |
| T | trips; a8_routes.ex:20–52, trips_gate.ex | web_description.ex:17 rich-content replay, plan_read.ex:84 legacy settings, web_write.ex:51/web_recalculate.ex:51 | T01–T10 retain ActionText/embeds and legacy failure, O07 wiring |
| V | visits/settings; a8_routes.ex:81–132, a8_gate.ex:63 | web_settings.ex:116–120 state/Cloud :rails, merge content/state errors | V01–V09 native terminal outcomes, O07 wiring |
| R | route_videos; a8_routes.ex:70–79 | File/recipe/storage admission, source failed versus rejected cleanup | R01–R09 preserve retention and client hooks, O07 hook registration |

HTTP prefix keys are coexistence rollback switches, not job authority. `jobs/registry.ex` and its existing imported entries keep domain entries `claimable: false`; sibling rows20–22 own readiness/cron/source accepted-work closure. Existing typed workers expose `args_from_command(version,payload)` and `perform(%Oban.Job{})`. No new framework, schema, transport policy or arbitrary Ruby deserialization is introduced.

## Reachable reverse effects

| Source call site | Kind / accepted-work identity | Disposition |
|---|---|---|
| stats/schedule.ex:34; stats/calculate_month.ex:133; stats/refresh_toponyms.ex:62 | stats calculation schedule, stats.caches_invalidated (user/year/month); owner-controlled schedule | Q + sibling cache/producer owners consume existing contracts |
| digests/schedule.ex:35 | monthly/yearly digest payload with run_at due time | Q + sibling mail/schedule owner; preserve locale/zone and identity |
| places/job_commands.ex:13,26,36,43; bulk_name_fetch_worker.ex:39,64; orphan_cleanup_worker.ex:48 | place_name_fetch, places_delete_if_orphan, places_orphan_cleanup, places_bulk_name_fetch | P native command/worker; retain source ownership until sibling readiness |
| tracks/effects.ex:16; realtime_worker.ex:53,65; backfill_commands.ex:43,91; daily_worker.ex:121; throttled_backfill.ex:77,93 | tracks_changed, geocode_recent_points, tracks_realtime_retrigger, tracks.backfill, tracks_generate_range, tracks_throttled_backfill | W and sibling geocode/cache/producer owners; preserve event_id and due-time fences |
| visits/web_settings.ex:42; bulk_sweep.ex:90 | visits.web_redetect, visits.suggest with user/zone/event identity | V + sibling producer/ownership owner |
| imports/upload_records.ex:68; destroy.ex:68; destroy_effects.ex:17,37,58; bulk_writer.ex:32,54 | imports.upload_created, purge/tile epoch/visit_months_changed | I/F + storage/cache owners; no post-commit fallback |
| imports/manual_extraction.ex:65; download_producer.ex:57; prepare_download_worker.ex:162; import_blob_purges.ex:57 | extraction, imports.prepare_download, imports.prepared_download_purge | I/F + storage owner; accepted work keeps source drain fence |
| imports/gpx_handover.ex:142; normal_handover.ex:164; gpx_lifecycle.ex:125; gpx_progress.ex:30 | imports.resume, imports.normal_resume, imports.progress; cursor/receipt lineage | F native continuation; unknown source payload blocks transition and is preserved |
| exports/delete.ex:41; user_data/import_commands.ex:43; restore/point_writer.ex:67 | exports.purge, users.import_data, points.tile_epoch | E + storage/cache owners; malformed source backups retain failures |

Ruling7: pin every key to Rails, drain accepted native work to zero, stop Phoenix, then start Rails1.15.3 against the same DB/storage. No native-to-Sidekiq transfer, inverse migration or backup restore. Cloud NEW server is Phoenix-only; old Rails is drain-only. Preserve source tools and all unknown/retired/dead payloads until dispositioned. Production flag evidence and release G42–G49 are deferred.

Retirement candidates NE1–NE6 default to Rails parity: retain redirects, legacy failures, Places aliases, supported imports/continuations, visible cache semantics and rich trip/visit content. Only an explicit controller ruling changes this default.

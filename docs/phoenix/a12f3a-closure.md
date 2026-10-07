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

## O02: focused dispatch handoff

The shared entry points remain Plug `init(opts)` / `call(conn,opts)`. `A8Request.request_module(conn)` selects TripRequest, PlaceRequest, VisitRequest (including settings), or RouteVideoRequest. Each domain exposes `target(path_info) -> {action,methods,overrides} | nil`, `action(action,effective_method) -> action`, `fields?(action,body) -> boolean`, `query_keys(action) -> [string]` and `repeated_keys() -> [string]`. Shared A8Request keeps raw byte reading, method normalization, format negotiation, `api_query/api_params/a8_action/a8_method/a8_format` assignments and RailsForm CSRF/session admission. Its generic `member/4`, `root?/2`, `nested?/3`, `scalar_map?/1` remain available to the domain parsers.

`A8Gate.request_gate(conn)` selects the matching focused RequestGate; `actions?(conn,params)` retains self-hosted/query policy in each domain, while A8Gate retains common content/header/format-envelope checks. VisitRequestGate owns existing `navigation?/2` and `settings?/2`. Route metadata still points at A8Gate, so these seams are effective immediately without touching O06/O07 routes.

O02 review correction: A8Gate has no independent self-hosted veto before the domain call. All four focused action gates retain their existing self-hosted guards, so current explicit Cloud rejection is unchanged. The named regression `O02: the domain gate decides Cloud admission while shared envelope guards remain` temporarily changes the trip domain policy in the test process, verifies delegated Cloud admission and shared header/content/dotted-path rejection, and restores the original compiled gate. Unsupported queries remain domain rejections. Reintroducing the shared self-hosted veto is its production mutation.

`MapWriteRequest.request_module(conn)` selects MapTagRequest, MapPointRequest, MapSegmentRequest or AreaRequest. Those modules expose `target/1`, `action/2`, `fields?/2`, `query/1 -> {:ok,map} | :replay` and `format/2 -> {:ok,:html|:turbo_stream} | :replay`. Shared MapWriteRequest retains raw-body/header/CSRF/method mechanics and existing `api_*` / `map_write_*` assigns. AreaRequest deliberately retains the absent-area result (`target -> nil`); W10 adds its source shape and O06 wires methods later. Segment PUT also remains a distinct O06 gap. Generic `id?/1`, `root?/2`, `nested?/2` stay shared.

`ImportsRequest.request_module(conn)` selects Imports.UploadForm for POST /imports, otherwise Imports.UpdateForm. Each exposes `field?({key,value})`; the extracted shapes are byte-for-byte equivalent to existing admission, including its current union of import fields. I owns further source-backed changes. Import reads, raw multipart parsing, auth/CSRF and `api_query/api_params` remain shared.

`MapGalleryCards.route_video_card(assigns)` preserves the existing annotated component surface and forwards to RouteVideoCard.route_video_card/1. Only video markup/helpers moved; poster markup and its phases remain in MapGalleryCards. R owns RouteVideoCard; the sibling poster owner can edit the retained poster body independently.

Evidence: named tagged O02 test initially RED (undefined `A8Request.request_module/1`), GREEN, M-O02 RED (VisitRequest versus RouteVideoRequest), restored GREEN. Targeted A8 request/gate endpoint, map-write admission, imports upload, gallery and O02 regression batch: 31 tests, 0 failures (seed404). New test uses actual decoded request/results, exact forwarded original bytes and unchanged SQL counts/outbox/reverse commands; explicit Cloud A8 gates remain closed. No domain behavior expansion or ownership activation was included.


## O03: current source contract handoff

The existing source generators now emit Q01–Q14, M01–M07, W01–W13 and P01–P10 in the plan-owned fixture paths. These are live Rails response/SQL/job observations with synthetic actors. Request captures preserve source errors, media, Location, selected security/cache headers, cookie presence/attributes and flash; replay metadata and before/after domain rows accompany writes. Source assertion tables stay in their original named examples. The new files supplement the retained smaller corpora used by existing parity tests.

Stats captures include all twelve update months, POST overrides, invalid numeric versus nonnumeric months, update-all, digest year coercion/bounds, missing deletes, UUID rotation, sharing booleans/expiry choices, public HEAD/expired/disabled/missing responses, insight filters and all eight cold-cache detail frames across shipped locales. `month=0` and `month=13` redirect without jobs; `month=bogus` raises a source routing failure. Digest creation accepts the source numeric prefix (`2024junk`) and preserves rejected year redirects.

Map captures cover both legacy redirects including invalid encoded queries, feed/calendar/track/residency frames, point/address/tag/segment reads and writes, source segment PUT, top-level area create/PATCH/PUT and override, rename/no-op/reshape effect distinctions, recalculation idle/processing HTML/Turbo behavior and reclassification batches of 100 with failure status. An area HTML request can persist its source change before returning 406; this is a terminal source effect, never a reason to replay.

Places captures retain list/drawer/create/update/delete/nearby controller observations and execute NearbySearch with only its synthetic geocoder boundary replaced: cached success/empty, uncached nil/failure, rounding/config cache identity, timeout/TLS/unexpected failures. Places background jobs remain source-recorded through A12d2. The A12e generator executes both legacy Rake aliases for zero/103 users, ignored extra argv, deleted-user exclusion, delays, enqueue/SQL failures and the partial second-batch failure; orphan count uses the exact source console recipe including blank versus retained notes. P10 carries the actual legacy alias observations; native aliases/owner concurrency remain P-owned implementation evidence.

The two missing-timezone visit cases in the shared map recorder now assert the current UTC default (`Users::SafeSettings::DEFAULT_VALUES`), replacing stale Berlin expectations. Explicit Berlin cases remain explicit. No owner flag or route is widened by these captures.


Full source responses use the existing fixture recorder's synthetic signing secret and deterministic opaque RNG inputs. JWT signing is synthetic too. CSRF/nonces/stream signatures, opaque subscription JWT links/API-key metadata and Rails debug exception identity are normalized; source statuses, error classes/messages, markup structure, query bytes and SQL/job observations are preserved. The backtrace path normalizer now matches only the line-number suffix after a path character so large geometry/base64 strings cannot cause repeated matching or a raised regexp timeout. Generator code snippets in local error pages are version-coupled; byte proof therefore uses two final captures from the same source revision.

The finalized O03 source command passed twice (85 examples, 0 failures each). Full fixture-tree `diff -ru` and country-name `cmp` both exit0. Seed UPSERT clocks and CLI private Oban input state are pinned/cleaned; existing CLI formatting and unrelated zone-alias bytes are restored. The shared map writer also emits V01–V04 in this commit so downstream source verification has its companion files; O05 completes their broader visit handoff.

## O04: imports, continuation and backup source contracts

I01–I12, F01–F26 and E01–E11 come from the retained Rails generators. Import packets include raw/signed/invalid/duplicate/descriptor/empty uploads, PATCH/PUT/source/status errors, destroy, original/preparing/prepared/missing downloads, and extraction/unextraction phases in both hosting modes. Producer packets retain watcher, Immich, TeslaMate, stale-import, PhotoPrism and OwnTracks Trekker source outcomes.

Formats retain every source enum dispatch plus unsupported/nil/ZIP input and the existing real decoder corpora. GPX and normal resume execute the real lease/receipt services with absent/mismatched/completed/deleting/deleted-user/forward/repeat/fallback/busy variants. Google continuation retains malformed cursor entries and scheduling. Whole-import postprocessing records the completed parent and warning notification when child scheduling fails. Semantic/phone/Polarsteps enhanced adapters have positive and malformed captures; the Records translator's observed enhanced-row result remains zero.

Exports include real JSON/GPX worker archive entries, deletion/attachment effects and user-data form/controller traces in all shipped locales. Backups retain both reader versions, all entity sections, batch boundaries, attachment/manifest/JSONL/root errors and post-commit anomaly/storage failures. Clock/sequence/opaque crypto inputs are synthetic and deterministic. The old backup corpus is byte-identical; the fourteen GPX extraction fixtures intentionally refresh anonymous IDs/clock through the existing DeterministicInputs helper.

The exact O04 source batch passed twice: 47 examples, 0 failures each. Full fixture-tree diff and country-name comparison exit0. No owner flag, transport policy, runtime registry or Rails production behavior changed.

## O05: trips, visits and route-video source contracts

T01–T10 retain trip pages, all remaining methods/errors/effects, calculation/windows and sanitized rich descriptions. The added embed case uses real ActionText attachment content and records its signed reference, storage metadata and dependent rich-text/attachment deletion while the blob remains. V01–V09 retain map/list/drawer/settings/write and actual detection/history/month/notification pipelines, including noted and null-attachable content. The existing deterministic helper pins model and instance-setting sequences; the legacy visit corpus intentionally refreshes anonymous IDs/clock. R01–R09 retain owned/foreign/missing reads, uploads, recipe/storage/metadata failures, rejected versus failed cleanup, capacity and retention, download/deletion and studio markup.

R08/R09 source binding review: `_studio.html.erb` exposes video-studio targets/actions for date range, format/theme/visualization/fog/route/marker/camera/units/HUD/watermark, render/cancel/save and result state. The source controller portals once to body, installs open/resize listeners, removes them on disconnect, invalidates stale async operations and tears down maps/results on close. Switching to poster preserves the provider and locked trip range. Rendering uses the existing renderer with AbortController/progress and source settings; cancel aborts it. Date/settings changes clear the prior result; result cleanup revokes the object URL and disables saving. `save_video.js` performs direct upload then CSRF-protected Turbo POST with name/file/settings/provenance, preserving source error/stream handling. The retained source client tests pass100/100 with0 failures/skips. This characterizes source behavior; native hook registration belongs to O07 and browser/release acceptance remains deferred.

The exact finalized O05 source batch passed twice: 51 examples, 0 failures each. Full fixture-tree diff and country-name comparison exit0. No app.js hook, domain owner flag or production behavior was changed in O05.

## Bootstrap full-suite compatibility seams

The first prescribed seed404 gate completed with 8547 tests and 23 failures. The new aggregate contract JSON files were being mistaken for individual legacy page cases. Existing page corpus readers now select paired JSON/HTML artifacts; aggregate packets remain captured for the domain owners. Segment PUT remains in W08/W09, with no legacy native-case companion until O06 admission exists. No native test was skipped or weakened.

The refreshed missing-zone source fixture defaults to UTC, so the A8 fixture harness supplies UTC too. GPX destroy uses the captured visit identity rather than a stale literal primary key. The real Rails completion recorder schedules untracked work before its card command; EnhancedImport.State.completed! now preserves that FIFO order. This one-line production correction is the minimum seam needed to consume the refreshed source capture, with no route, registry or ownership expansion.

Evidence: the focused seven-file regression batch passed194 tests,0 failures. The existing named GPX completion test fails when the command order is reversed (9 tests,1 failure,8 unselected) and passes after restoration (9 tests,0 failures,8 unselected). The segment source recorder passed twice with byte-equal output; its final guard-clause-only cleanup passed again. No new named test was introduced by these compatibility corrections.

The required whole-tree format gate also exposed two baseline share-link templates. Applying the prescribed formatter to only those templates is a formatting prerequisite; their domain behavior and ownership remain unchanged. Full-suite checks include their existing parity coverage. Repository evidence and the final gate results are indexed in the assigned implementation report and the shared AFFiNE pages/domain closure plan index.

Seed202 then exposed a baseline release-operation test input that formed a 32-bit point epoch by adding the retained user sequence. The minimum test-only seam uses the fixed valid synthetic epoch, preserves all1000 users and the exact pagination/cursor/job assertions, and seeds a high user identity to prove independence from prior suite order. The sequence is saved/restored. Existing named test evidence: RED integer overflow, GREEN, M-O-GATE-timestamp failure when identity-derived epoch is restored, restored full-module GREEN for202/404. No production change, new test exclusion or timeout increase; both prescribed full seeds are rerun after this committed input correction.

Under concurrent suite load, the retained A12rel adapter test exceeded its unchanged60-second limit while seeding6309 region rows individually. Its fixture setup now inserts the exact rows in500-row batches (19 statements), keeping every source geometry/identity/clock/worker/committed-connection assertion. Focused GREEN completed in11 seconds. M-O-GATE-corpus omitting source region55001 fails the exact source row projection; restored202/404 GREEN is recorded. This is a test-only setup optimization, with no reduced corpus, production change, skip or longer timeout.

## O06–O08: integration route reconciliation

Integration baseline: `aa5270f9f939ab138447f7f1271495ecbe0afab4`,
`feat/phoenix-port`, 2026-10-07. This supplement supersedes the bootstrap's
missing-route observations above; it preserves their historical source census.
The assigned base already contains the Q/M/W/P/I/F/E/T/V/R handlers, area
POST/PATCH/PUT, segment PUT, import PUT/extraction, native stats/digest actions,
map redirects and VideoStudio hook registration. No duplicate routes or hook
registrations were added. Handler existence was checked against that integration
base before native registration was asserted.

The O01 ledger contains 90 source method/path rows. O06 checks 47 declarations
and O07 checks the remaining 43. Review R1 showed that the original 516 replay
probes used unsupported envelopes, so they did not establish key independence.
Those probes remain only raw-envelope replay evidence across explicit Cloud and
self-hosted modes and fresh/legacy settings; their results are not native
admission evidence.

The corrected aggregates pair every source method and its original HEAD variant
with an eligible request through the real Endpoint on self-hosted: 90 methods and
39 HEAD variants, 129 pairs. Each pair first clears rollback keys, asserts its
eligibility gate, a native 200/301/302/303 outcome and original native-method
marker, and no Rails connection. It rolls that probe's database transaction back,
then sends the identical method, path, query and body with only the selected key
pinned. Rails must receive the exact request line and entity bytes, return 204,
and leave full domain/user/attachment/outbox rows and reverse commands unchanged.
GET/HEAD probes are bodyless; writes use the signed synthetic session and valid
CSRF token. Owned imports/trips/segments/visits/tags/areas and signed synthetic
upload blobs provide eligible state. The current public missing-capability branch
is tested as a native redirect. Backup GET/HEAD also gets the same behavioral
pair in explicit Cloud mode. Places/video Cloud gates and unsupported legacy
settings remain their owners' deferred boundaries. No Cloud admission is inferred
from self-hosted evidence.

| Source routes / key | Rows | Native handler disposition |
|---|---:|---|
| stats | 6 | Native implemented: StatsLive, StatsActions and StatSharing |
| digests | 5 | Native implemented: DigestsLive, DigestActions and DigestSharing |
| insights | 2 | Native implemented: InsightsLive and details frame |
| shared month/digest | 2 | Native implemented: SharedStatsPage; independent `shared` key |
| map and bookmark redirects | 8 | Native implemented: MapLive, MapFrames and MapRedirects |
| points / tags / tracks / areas | 17 | Native implemented: scoped reads and existing point/tag/segment/area/recalculation actions |
| places | 7 | Native implemented: PlacesLive, PlaceNavigation and PlaceActions; CLI stays outside HTTP |
| imports / extraction / downloads | 11 | Native implemented: ImportsLive, ImportsController and ImportsDownload |
| exports / current-user backup | 5 | Native implemented: ExportsLive/Create/Delete and UserDataController |
| trips / private notes | 14 | Native implemented: TripsLive, TripActions and TripNoteActions |
| visits / redetection / visit settings | 11 | Native implemented: VisitsNavigation, VisitActions and VisitSettingsActions |
| route videos | 2 | Native implemented: RouteVideoActions; existing native VideoStudio hook |

O06 changes only public month/digest metadata: `router.ex:246–250` uses `shared`,
so private `stats` or `digests` pins leave public capability routes native.
The broad shared pin still restores Rails before auth, data access or effects.
Areas, tags, points, tracks and places retain independent first-segment keys;
pinning map alone leaves the declared write handlers eligible.

O07 preserves visit settings under the broad `settings` pin; the existing
`visits` pin covers visits and redetection independently. `user_data` remains
independent. `UserDataRoutes.native?/2` delegates HEAD eligibility to the existing
GET gate; J's Strangler/Plug.Head still preserves the original method and removes
the wire entity. The real backup GET/HEAD in self-hosted and Cloud creates one
native export outbox row, returns the recorded redirect and emits no reverse
command. An injected before-send failure after publication leaves exactly one
row and makes no Rails connection. Unsupported form/client/CSRF envelopes retain
pre-effect coexistence replay and native standalone terminal refusal.

### Deferred owner prerequisites and retained branches

All 90 ordinary handlers exist on the integration base. No route is deferred
because its handler module is missing. Registration does not close every rare
source envelope or make its worker claimable.

| Reachable branch | Disposition / owner |
|---|---|
| Dotted/JSON/XHR/valueless browser envelopes; ambiguous body/session/CSRF; strict stats update/sharing year/month route constraints | Deferred owner prerequisite: A12f-2 J shared Strangler/transport constraints. Existing source refusals and standalone native errors remain; no shared guard was bypassed here. |
| Places and video coexistence Cloud gates; missing/foreign segment frame admission; unrecognized stored import state | Deferred owner prerequisite: P/R/M/I domain gates and their documented source-error matrices. Existing eligible native journeys are retained. |
| W legacy date/settings/container/numeric coercion tails and achievement debounce after outbox dispatch | Deferred owner prerequisite: W and shared achievement worker; see `a12f3a-w-closure.md`. |
| Cold cache invalidation, tile epochs, track/visit live events, restore follow-up sinks | Deferred owner prerequisite: sibling rows 19–22; Q/W/I/E/V owner handoffs remain authoritative. |
| Typed worker registration, producer/cron readiness, accepted legacy lineage and unknown serialized payload disposition | Deferred owner prerequisite: sibling registry/drain owners. Preserve inert entries and accepted UUID/blob/cursor/receipt fences; unknown payloads block their affected transition. |
| Browser/codec workflows, real stands/images, production pins and G42–G49 | Deferred controller release lane; seed 202 runs on the integration head under ruling 14. |

No needs-Eugene retirement remains open here: rulings 9–17 retain bookmarks and
maintenance aliases, preserve characterized Rails defects, drain accepted source
work before retirement, and retain the Rails application for same-DB rollback.

### Shared owner handoff

The native reverse-kind/key/identity contracts were reused without modifying
registry, scheduler, effect sinks or ownership policy:

| Producer / native key | Identity, due time and fence | Existing detailed counterpart |
|---|---|---|
| `stats.calculate_month`, `stats.full_recalculation`, `digests.calculate_year` | Versioned outbox, actor/year/month/zone and producer metadata, fresh event UUID, captured current due time; persisted owner lock and transaction | `a12f3a-q-closure.md`, `stats/web_commands.ex`, `digests/web_commands.ex` |
| points stats/track/achievement follow-ups; `areas.relabel_visits`; `transportation.user_reclassify` | Actor/track/area identities, achievement pending dedupe/minimum timestamp and 60-second due time, child batches of 100 with 10-second spacing; owner/actor/event fences | `a12f3a-w-closure.md` |
| `places.name_fetch`, `places.delete_if_orphan`, `places.orphan_cleanup`, `places.bulk_name_fetch` | Scoped user/place, unique event UUID; supplied cleanup due time retained in native and compatible reverse paths; owner lock/publication transaction | `a12f3a-p-closure.md` |
| GPX/normal continuations and extraction; prepared-download purge | Import/blob/user/source-blob and accepted event/immutable receipt/cursor lineage; immediate extraction scheduling and lease/owner/attachment fences | `a12f3a-i-closure.md`, `a12f3a-f-closure.md` |
| `exports.points`, `users.export_data`, `users.import_data` | Existing export/user/locale/zone payloads, current due time, accepted event and import/blob identity; lease, transaction and storage attachment fences | `a12f3a-e-closure.md` |
| `trips.calculate`, trip exports and private notes | Existing actor/trip/note and attachment identity, native calculation/export event; existing context/export APIs and resource transactions | `a12f3a-t-closure.md` |
| `visits.full_history_redetect`, visit suggestions and month invalidation | Version-1 actor/zone/plan/locale, accepted event identity and completion-based cooldown; actor/owner lock and existing month-worker fences | `a12f3a-v-closure.md` |
| route-video attachment cleanup | Attachment record/name/ID, blob and actor snapshot, retained/shared blob safety and durable deletion dedupe; native storage job, compatible explicit source pin | `a12f3a-r-closure.md` |

### Branch-specific expected-diff handoff (review R2)

The producer table above describes contracts; it is not an ED disposition table.
The following proposals apply only to the named branches. Sibling row 24 alone
edits `app-phoenix/parity/expected_diffs.md`; this cut leaves it untouched. No
historical ED is proposed closed in full. `O06` and `O07` evidence below means
the correspondingly named aggregates in
`test/dawarich_web/a12f3a_o_closure_test.exs`; their supported HTTP observations
establish route ownership, not worker/cron readiness or release acceptance.

| ED | Precise affected branch | Proposed disposition | Supporting test/source evidence | Remaining owner prerequisite |
|---|---|---|---|---|
| ED-119 | Shared ingestion/transport refusals: malformed JSON, ambiguous headers/session/CSRF, unsupported browser shapes | No change proposed; remains open for every unproven envelope | O02 malformed replay table; `a8_request.ex`, `map_write_request.ex`, `imports_request.ex`; O06/O07 valid forms do not exercise ingestion JSON | A12f-2 J transport and ingestion owners must prove each retained shape; original replay probes supply no closure credit |
| ED-152 | API countries/visited/digest writes, Cloud/HEAD and stored summary refusal tails | No change proposed; API branches remain open; browser digest routes do not close their API counterparts | O06 exercises web `/digests` and `/stats`; `digest_actions.ex`, `stats_actions.ex` | A12f-2 API read/write owners and shared tile/cache owner; Q owns residual stored summaries |
| ED-194 | API geocoding/photos/provider enrichment, thumbnail and provider failure/cache branches | No change proposed; remains open in this route-wiring cut | O06 places navigation is a web branch; `place_navigation.ex`; provider evidence remains in `a12f3a-p-closure.md` | Provider/API/cache owners must reconcile their separate evidence; no provider execution proven here |
| ED-212 | API tracked-months/tiles/hexagons, point writes, Cloud/HEAD and coercion tails | No change proposed; API branches remain open; browser bulk deletion supplies no API closure | O06 web `/points/bulk_destroy`; `point_list_actions.ex`; `a12f3a-w-closure.md` | A12f-2 point APIs and sibling tile/cache/invalidation owners; no API admission or sink retirement inferred |
| ED-249 | Self-hosted web imports eligible GET/new/show/edit/download, POST/create, PATCH/PUT/update, DELETE and extraction methods, with supported owned stored state | Propose bounded native ownership for the O07 eligible HTTP rows; retain explicit imports rollback and all untested envelope/state/storage branches | O07 paired Endpoint methods; `import_routes.ex`, `imports_gate.ex`, `imports_request.ex`; `a12f3a-i-closure.md` | I/F own remaining format/state/storage failures; J owns malformed transport; registry/drain owners own accepted continuation lineage |
| ED-295 | Achievement collection/detail admission, redirected/unsupported keys, sharing/unlock additions | No change proposed; no achievement route is in the 90-row census | O06/O07 route tables contain no `/achievements`; existing counterpart `a10c-achievement-actions.md` | Achievement owner and release lane retain their existing dispositions |
| ED-335 | Credentials/recovery/remember/registration/OAuth, Cloud/provider/forwarding/session refusal branches | No change proposed; authentication behavior remains open as recorded | O06/O07 consume `RailsAuth` and `RequireUser`, not native sign-in/recovery transitions; `rails_auth.ex` | A12f-2 auth owners and external lifecycle handoff; these request pairs grant no lifecycle credit |
| ED-355 | Self-hosted web points index/address, tags index/new/edit and owned track-segment GET/HEAD; independent points/tags/tracks rollback | Propose bounded native ownership for the O06 eligible reads, retaining unsupported/foreign/legacy branches | O06 paired Endpoint reads with seeded track/segment/tag/point; `map_data_gate.ex`, `map_frames.ex` | M owns foreign/missing frame and rare settings/ordering outcomes; J owns unsupported envelopes |
| ED-370 | Shared-link/notes/visits/account APIs, Cloud/HEAD/providers/deletion/remember-state branches | No change proposed; web trip notes/visits do not close API branches | O07 web `/trips/:trip_id/notes` and `/visits`; `trip_note_actions.ex`, `visit_actions.ex` | A12f-2 API owners, providers/cache, auth and external lifecycle handoff retain their boundaries |
| ED-383 | Self-hosted web tag CRUD, segment PATCH/PUT and point bulk deletion; areas and transportation recalculation web admission | Propose bounded native ownership for O06 eligible writes and independent keys; retain coercion/session/legacy/error tails | O06 paired CSRF-valid forms; `map_write_request.ex`, `area_actions.ex`, `segment_actions.ex`; `a12f3a-w-closure.md` | W and J own residual coercions/envelopes; shared achievement/cache/live sinks and controller stand acceptance remain |
| ED-392 | Current-user `/settings/users/export` GET/HEAD in self-hosted and Cloud; self-hosted `/settings/users/import` POST; admin mutations/deletion/mail/provider branches unaffected | Propose bounded native ownership for only current-user backup HTTP; retain the broad settings pin and independent user_data pin | O07 pairs and explicit Cloud backup pairs; `user_data_routes.ex`, `user_data_controller.ex`; `a12f3a-e-closure.md` | E owns storage/restore follow-ups; sibling registry/producer/drain owners and release lane; no admin/lifecycle expansion |
| ED-400 | Four `/api/v1/users/me/two_factor` management methods, Cloud/duplicate/trailing-slash refusals | No change proposed; no OTP request or assertion changed | O06/O07 route census has no OTP API; `a12f3a-closure.md` source-method census | A12f-2 OTP owner and controller integration/stand/image lane; existing local disposition retained |
| ED-410 | Achievement sharing/unlock/public presentation, runtime headers/session cookies/embeds | No change proposed; web shared month/digest metadata does not prove achievement presentation | O06 public `/shared/month` and `/shared/digest` only; `shared_stats_page.ex`; `a10c-achievement-actions.md` | Achievement/public media owners and controller browser/stand/image lane retain their evidence |
| ED-411 | Retained backup HTTP clause only: export GET/HEAD self-hosted and Cloud, import POST self-hosted; achievement sharing/unlock/public HTML, PNG/providers/admin/background producers unaffected | Propose bounded native ownership for current-user backup HTTP only; retain independent user_data/shared rollback and all unrelated achievement branches | O07 backup HTTP and no post-publication replay; `user_data_routes.ex`, `user_data_controller.ex`; O06 public stats uses shared metadata | E and typed registry/producer/drain owners must prove backup worker/restore readiness; achievement/media/release owners unchanged |

No Rails application defect was fixed by this test/doc correction.

### Reconciled source and verification evidence

The six affected existing Rails generators were rerun on the reconciled head:
stats, map frames, imports pages, trips, current-user backup and visits.
The first assertion batch completed 59 examples with three stale source-packet
failures. Stats' source 404 diagnostics included runtime logger object IDs;
imports referenced the earlier video upload asset fingerprint; backup source
summaries omitted E's captured container cases. The stats recorder now normalizes
only the two logger identity fields in those diagnostics, in addition to its
existing normalization. Source status, headers, state and effects remain asserted.
No named generator test or source application behavior was added.

Two corrected recordings of those three existing examples each passed three
examples with zero failures. Complete fixture-tree comparison and country-name
comparison both exited zero: every captured byte was identical. Updated source
packets are Q06/Q12/Q14, I01–I06 and E04 under `a12f3a_source`; the existing domain
goldens and unrelated legacy visit timezone/track locale captures retain their
pre-task bytes. The subsequent complete six-generator assertion batch passed
59 examples with zero failures. Swagger and schema remain unchanged.

Historical O06/O07 evidence below predates review R1. M-O06 removed area PUT
and checked its declaration. M-O07 removed user_data metadata and failed a
metadata assertion before its behavioral probe. Those mutations did not prove
independent rollback; the original 516 replay requests were already ineligible.
Their expanded 26-test regression batch, forced compile, format and source
recorder verification remain historical evidence for the implementation cut.

Review corrections retain the same two named route aggregates. Their initial
native-first assertions fail against the old helper; eligible resource/form
setup makes them pass. M-R1-O06 ignores the areas rollback key and fails the
behavioral `rollback areas: POST /areas` assertion. M-R1-O07 removes user_data
metadata and now fails `rollback user_data: GET /settings/users/export`, after
native eligibility and native Endpoint outcome have been proven. Both restored
selectors pass. R2's named row-24 handoff test fails on missing ED119 before the
mapping table, passes with it, fails M-R2-ED400 (omitted ED400 mapping), and passes
after restoration. Full row snapshots are collected in one SQL statement per
observation to preserve the checks without repeated database round trips.

The final focused regression batch includes the corrected closure aggregates,
existing backup/page/map/visit-settings behavior and Cloud/native lifecycle
transition guards: **34 tests, 0 failures**, seed404. No production routing or
lifecycle guard change was needed. Changed Ruby specs/RuboCop are inapplicable
to this test/doc-only correction. The forced compile, full format and controller
seed404 gate results for this correction are recorded in its fix report.



The first seed404 suite finished 9125 tests with two failures: missing vendor
poster-renderer dependencies and an incorrect draft visit-settings rollback key.
The vendor setup was completed using the exact matching local compiled cache;
visit settings retained its established independent `settings` contract. The
corrected O07 aggregate fails HEAD eligibility on its exact pre-change production
source, then passes, fails M-O07 and passes after restoration. No existing
contract assertion, timeout or skip was weakened. Final seed404 acceptance is recorded below.


Historical O08 acceptance: the required controller seed404 wrapper completed with
exit0, **9125 tests, 0 failures**. Partition summaries:

- partition-1.log: 3213 tests, 0 failures, 2 excluded, 1 skipped
- partition-2.log: 3262 tests, 0 failures, 1 excluded
- partition-3.log: 2650 tests, 0 failures, 3 excluded, 2 skipped

The inherited six exclusions and three skips are unchanged. Forced production
compile with warnings-as-errors, whole-tree format check, the 59-example Rails
source batch and changed-generator RuboCop all pass. Seed202 and the recorded
shared-owner/release prerequisites remain the controller's separate lanes.

Review-fix acceptance (2026-10-07): the required controller seed404 wrapper
completed with exit0, **9173 tests, 0 failures**. Partition summaries:

- partition-1.log: 3150 tests, 0 failures, 2 excluded, 1 skipped
- partition-2.log: 2768 tests, 0 failures, 3 excluded, 2 skipped
- partition-3.log: 3255 tests, 0 failures, 1 excluded

The six exclusions and three skips belong to the existing suite. Forced
`MIX_ENV=test mix compile --warnings-as-errors --force` and whole-tree
`mix format --check-formatted` also pass. The correction changes tests and this
ledger only; Cloud lifecycle refusal remains intact.

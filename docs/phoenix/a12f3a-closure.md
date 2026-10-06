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

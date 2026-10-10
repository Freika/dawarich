# Milestone 6 inventory and planning baseline

Read-only source inventory on app `bdaa9aa363230857b5a96fe67eb1e6d10f7390b3`, 2026-10-10. E2E source inspected at `ff256e6fd6a8a50f3f05a9e5a1e9656ef5a47b2d` (the supplied 3b checkout). Covers source milestone 6 plus onboarding and map Areas deferred by milestone 3. No production code or tests changed; no test suite, browser lane, build or runtime measurement was executed during planning. Counts below are physical source lines, including comments/blanks, not compiled bytes or an effort estimate.

## Contract, provenance and reading conventions

Scope: `docs/phoenix/native-frontend-contexts-plan-20261008.md:132` (map/replay/studios); deferral: `docs/phoenix/native-m3b-inventory.md:64` and the verified milestone 3b plan's Scope. Standing decisions: ADR-0017, behaviour assertions retained, named behaviour successors for markup assertions, Scope-taking contexts, no coexistence hand-back, standalone G44 as browser oracle, library hooks only. The verified 3b plan and its deviations are the implementation-plan template.

Citation roots: `W/` = `app-phoenix/lib/dawarich_web/`, `D/` = `app-phoenix/lib/dawarich/`, `T/` = `app-phoenix/test/`, `E/` = E2E repository (supplied 3b checkout). Rails paths start `app/`; compatibility JS starts `app-phoenix/priv/static/js/`; new native source is `app-phoenix/assets/`. `:1` in the census identifies the whole file, not a claim about a single function. **B** = behaviour/data/API invariant; **M** = markup/controller transport to replace; **C** = coexistence/replay machinery to retire for migrated consumers; **R** = route/ownership assertions to update. Proposed boundaries, risks and defaults below are planning recommendations, not implemented decisions or demonstrated leaks.

Historical acceptance, not a new m6 measurement: 3b recorded 10,097 ExUnit tests per seed (404/202), three 533/0/51 G44 lanes, ordinary native admin pages 162.8–163.3 KB decoded JS, experimental demo 1.68 MB. See `docs/phoenix/native-m3b-inventory.md:7`. Those figures do not establish map/studio budgets.

## Size and controller/module census

The complete file census is in the appendix. The important distinction is framework-independent algorithms versus controller-shaped orchestration, not whether a file is under `controllers/`.

| Source family | Measured size / examples | Meaning for migration |
| --- | --- | --- |
| `app/javascript/maps_maplibre/` | 15,204 lines; API client 1,048, replay panel 853, search manager 790 | Layers/utilities already plain classes/functions; some still import global i18n, ActionCable or receive a controller object. Split files above the 300-line production limit during extraction. |
| `app/javascript/controllers/maps/maplibre/` | 12 managers; settings 1,106, event handlers 927, selection 735 | Plain classes coupled to Stimulus targets/application and global DOM events; cannot retain their controller-shaped constructor as a substitute registry. |
| Map controller | `app/javascript/controllers/maps/maplibre_controller.js:135` connect; 2,084 lines | Owns API, layers, date/settings, timeline, selection, edits, family, replay, studios. Thin hook plus focused runtime modules replaces this composition. |
| Timeline/panel/control controllers | timeline 1,008; panel 376; controls 102; dirty settings 124; theme editor 178 | URL/calendar/frame orchestration and popup/frame callbacks are part of m6, not a minor hook rename. |
| Trip and small map owners | trip 743; preview 178; shared trip 316; shared live 284; public stats 269; family 194 | Trip/preview/public/family ownership and authorization differ. Public maps are currently HTTP documents, not LiveViews. |
| Poster | editor 923, theme picker 71; 18 poster library files | Geometry/themes/fonts/style/encoders reusable; provider lookup and editor lifecycle must change. |
| Video | Rails controller 826; 20 library files; six Phoenix hook files 834 lines | Phoenix hook already exists but still consumes Rails modules, registry provider and Turbo save; preserve its operation-version improvements. |
| Deferred CRUD/dialogs | onboarding 209; area form 113; area drawer 150; place form 182; visit form 296 | Preserve server validations and effects; move map-host orchestration to native events/components. |

## Route, session, data and write inventory

| Host / flow | Current owner and transport | Required retained behaviour / migration boundary |
| --- | --- | --- |
| `/map`, `/map/v2` | `W/page_routes.ex:82` `:rails_map`, RailsAuth + LiveAuth, map_root/map layouts; `W/map_live.ex:13` reloads MapPage in handle_params; only event is rails_flash | Both aliases, URL date/panel/import/place filters, entitlement gates; native session and typed refusals. Current connected not-found reloads same URL (`W/map_live.ex:45`); replace without a loop. |
| Map DOM | `W/layouts/map.html.heex:20` entire shell ignored; share frame/demo banner separate MapShell hooks; `W/components/map_index.ex:31` four controllers and key-bearing attributes | Keep only library canvas containers ignored; controls/dialogs/timeline become server-managed; preserve safe-area/map dimensions and date links. |
| Tiles/read APIs | `app/javascript/controllers/maps/maplibre/map_initializer.js:54` same-origin tile transform; `app/javascript/maps_maplibre/services/api_client.js:20,437,478,598,1007`; `W/api/map_controller.ex:24` and `D/map_api/closure.ex:1` | Tiles for ordinary point/track browsing. Bounded explicit fetches for selection/edit/replay/studios. Preserve pagination, import filters, profile timezone, anomalies, revisions, ETags and tile freshness. Never move point/track arrays into LiveView assigns. |
| Browser API authentication | `W/api/auth.ex:58,243,265` requires query/Bearer key; ClientSession loads session but does not substitute a cookie user (`W/api/client_session.ex:5`) | Recommendation: narrowly scoped cookie-authenticated browser read endpoints over the same domain queries, with API entitlement rules retained; external key API remains unchanged. Cookie presence alone currently cannot authenticate these reads. Controller decision required. |
| Map initial state | `D/map_page.ex:17` loads settings/import/entitlements/tags/gallery/themes; `:35` includes API key; `:88,125` references web Params | Deepen a scoped read interface, split projection/read files under 300 lines, replace domain-to-web parsing dependency. Do not claim current state is secret-free. Bounded gallery/tag/metadata budgets must be measured, not guessed. |
| Timeline/calendar/residency/track drawer | `W/map_frame_routes.ex:14` frame GETs; `app/javascript/controllers/timeline_feed_controller.js:24,131`; `app/javascript/controllers/maps/maplibre_controller.js:750` sets frame source | Native bounded day/month read models; URL remains source of date/filter/selection. Preserve midnight/DST, search end-time, journey legs, bulk visits and segment drawing. Frame transport assertions retire only after named native successors. |
| Point/segment editing | `app/javascript/maps_maplibre/editing/map_editor.js:1`; API position at `app/javascript/maps_maplibre/services/api_client.js:949`; `W/map_frame_routes.ex:8` segment form writes; `D/points/api_position.ex:9`, `D/tracks/segment_editor.ex:1` | Scope commands wrap existing revision/transaction/effects implementations. Preserve drag only in edit mode, stale conflict, undo/redo history, tile exclusion until fresh tile reload, counters/derivatives and published invalidation. Public point/segment APIs retain their wire contracts. |
| Selection/bulk/visit/place | `app/javascript/controllers/maps/maplibre/area_selection_manager.js:1`; API client `:654,704,754,804,841,861`; `W/components/map_place_modal.ex:1`, `W/components/map_modals.ex:1`; `W/map_frame_routes.ex:30` drawer/nearby | Rectangle drawing is distinct from saved circular Area CRUD. Preserve anomalies selectable, owned bulk IDs, confirmation, visit merge/confirm/delete and tag/name/note semantics. Coordinate with native Places (3d) and Visits/Trips (5); no duplicate business context. |
| Areas | `W/page_routes.ex:17` POST/PATCH/PUT/override form writes; delete is `/api/v1/areas/:id`, not form DELETE; `W/api/areas_controller.ex:1`; `D/areas/web_write.ex:7,25`, `D/areas/api.ex:62` | Native modal create/edit/delete commands; radius>0, coordinate numeric validation/rounding and retry no-op preserved. Existing relabel outbox and cleanup graph/foreign dependency guard reused. No standalone Area list page exists. |
| Map settings | controller manager `app/javascript/controllers/maps/maplibre/settings_manager.js:400,576,1055`; `D/settings.ex:11` native facade; `W/api/settings_controller.ex:1` | Settings save/recalculation through scoped contexts; UI filters/style changes stay browser-local until persisted. Preserve casts, feature/plan restrictions, dirty transportation Apply, tile fallback and custom style errors. Replace polling only after identifying authorized progress event from m4; bounded polling fallback needs explicit decision. |
| Immich map tools | `W/components/map_tools_tab.ex:75` Pro/configured controller host with key attribute; `app/javascript/controllers/maps/immich_enrich_controller.js:90` scan and selection/enrich; `W/api/immich_controller.ex:12`, `D/photos/enrichment.ex:1` | Preserve range synchronization/tolerance/match selection/markers/tooltips/provider errors and fresh Pro admission. Native scoped scan/enrich, bounded HTTP match reads and cancellation; no controller lookup or client integration secrets. |
| Trip show/form/cards/preview | `W/trips_live/show.ex:15,45` whole ignored MapShell, path_json/windows_json in assigns; `W/components/trip_form.ex:78`, `W/components/trip_card.ex:25`, `W/components/trip_map_panel.ex:12` | Trip hook owns overview/day/device data, flights/photos/plan/replay and providers. Move bulk geometry to owned read endpoints (m5 coordination); keep permitted small metadata. Preview hook/lazy visibility owns mini maps; no hidden maps accumulating across lists. |
| Public trip/track/live maps and public statistics | `W/shared_pages.ex:42` root HTTP document; `W/shared_pages/live.html.heex:1`; `W/components/shared_resource_page/track.html.heex:4`; shared controller calls `SharedApi`; `app/javascript/controllers/public_stat_map_controller.js:1` | Public owner/capability separate from authenticated Scope. Preserve phrase unlock HTTP/cookie, expiry/revocation/privacy zones/show_route/show_photos. Proposed PublicMap LiveView wrapper over admitted document; revalidate on data/event/reconnect. Controller decides bootstrap; no hook can mount on an ordinary HTTP document without a LiveSocket owner. |
| Family map and live overlays | `W/families_live/show.ex:76` FamilyPage + family-map; `app-phoenix/priv/static/js/family_page.js:1`; main map loads family API `app/javascript/controllers/maps/maplibre_controller.js:1481,1540`; channel module `app/javascript/maps_maplibre/channels/map_channel.js:1` | Native Family hook consumes authorized m4 events/refetch invalidations; permission withdrawal clears visible history/location. Reconnect refreshes membership/grant. Keep external ActionCable only for independent clients; native browser must not import it. |

### Poster flows

- Map/Trip launch through `poster-studio:open` and provider objects (`app/javascript/controllers/trip_maplibre_controller.js:432`, `app/javascript/controllers/poster_studio_editor_controller.js:131`). MapPageProvider does registry lookup (`app/javascript/poster_studio/data/providers.js:11`); TripProvider contains reusable fixed-range geometry/points (`:124`). Replace with explicitly injected data-source functions/immutable metadata, shared with video, no global controller lookup.
- Preview: `app/javascript/controllers/poster_studio_editor_controller.js:147` theme, date range, fonts, preview map; `:268` delayed restyle. Theme tokens, tile categories/POI, custom backdrop, title/subtitle/tagline/coordinates, stroke/opacity, orientation/social layouts and paper/DPI cap are in editor/library modules. Preserve at m6, including trip flight arcs (`app/javascript/controllers/trip_maplibre_controller.js:475`).
- Local export: `app/javascript/poster_studio/ui/exporter.js:11` captures bounds then overlays text; `app/javascript/poster_studio/export/png_encoder.js:70` PNG RGBA/zlib/CRC, optional pHYs; `app/javascript/poster_studio/export/pdf_encoder.js:19` PDF 1.4 single JPEG page at physical mm size. Social layout with PDF selection falls through to PNG (`app/javascript/poster_studio/ui/exporter.js:34`). Preserve filenames/DPI/layout and that existing format rule unless controller decides otherwise.
- Server gallery render is a separate engine: editor `:811` populates a hidden form and submits Turbo; `W/posters_controller.ex:35` calls Persistence; `D/posters/{command,generation,publication}.ex:1` native jobs and fenced publication. Preserve gallery status/attachments/native renderer; do not promise browser-customized PNG and server poster are identical. Scope create/delete facade and authorized m4 progress subscription replace streams.
- Print ordering: `app/javascript/poster_studio/ui/order_client.js:12` uploads a PDF via XHR; tokens/checkout URL returned; editor `:710` creates PDF then upload/checkout. This is user-visible existing scope, not optional because brief names PNG/PDF. Preserve real clicked checkout anchor, product/layout gate and error mapping. Tests must stub external service; never place a real order during acceptance. Add abort/timeout/resource ownership.

### Video flows

- Rails studio controller (`app/javascript/controllers/video_studio_controller.js:1`) and compatibility Phoenix hook (`app-phoenix/priv/static/js/hooks/video_studio.js:81`) both exist. The latter has operationVersion/disposed guards and unbind/close/destroy but keeps controller-like targets and `window.Stimulus` provider; save still renders Turbo (`app-phoenix/priv/static/js/hooks/video_studio_save.js:28`). Port useful concurrency semantics into ordinary modules, not this generic target/registry adapter.
- `app/javascript/video_studio/studio_state.js:1` settings/formats/provenance; date_range/points/load_track normalize profile dates/data; path_smoothing/route_timeline/route_clock/render_plan/camera_path preserve route progression, no-data timing, camera/outro and HUD/stat semantics.
- `app/javascript/video_studio/video_renderer.js:113` creates encoder and offscreen map; loops composited map/HUD/fog/marker frames; finally map/container cleanup `:312`. `app/javascript/video_studio/mp4_encoder.js:47` probes candidates, closes VideoFrames, bounds encoder queue at eight; abort wakes parked callbacks `:73`. MP4 with H.264 first then VP9/AV1 (`app/javascript/video_studio/codec_negotiation.js:4`) is the existing output; unsupported browser is a visible refusal, not permission to silently change to WebM/server encoding.
- Saving uses `@rails/activestorage` DirectUpload and POST Turbo response (`app/javascript/video_studio/save_video.js:1,51`). Keep signed blob/MP4/size validation, transaction, analysis, retention/eviction and purge in `D/route_videos/writes.ex:10,52`/Retention. Replace frontend adapter with native m4 storage upload capability, then Scope command containing opaque upload reference/recipe, not bytes. Binary and signed refs stay out of assigns/logs; download remains HTTP.
- Existing E2E studio checks open/controls/aspect/switch/share launcher (`E/v2/map/video-studio.spec.js:53,74,106,125,138`). Gallery spec saves a supplied synthetic MP4 (`E/trips/video-gallery.spec.js:9,24`); it does not demonstrate a real WebCodecs render→download→save. Add that browser acceptance scenario, including cancel/encoder failure and decode metadata.

### Onboarding and demo data

- `W/components/onboarding_modal.ex:17` native branch dispatches to NativeOnboarding; app layout uses it for native pages; map layout still passes auto_open to the hybrid dialog (`W/layouts/map.html.heex:76`). There is no standalone onboarding page.
- Rails auto-open is map-only, showable and per-user localStorage after successful showModal (`app/javascript/controllers/onboarding_modal_controller.js:24,53`). Completion listener attaches on that auto-open path (`:69`), PATCH completion `:187`; manual opening does not attach it through checkAndShowModal. Native modal currently closes using method=dialog without completion request (`W/components/native_onboarding.ex:40,124`; `T/dawarich_web/native_onboarding_test.exs:77`). Recommended default: preserve auto-open-path completion and manual-close semantics; controller may approve completing every dismissal explicitly.
- Native import screen links `/imports/new` (`W/components/native_onboarding.ex:154`) while hybrid dialog embeds upload. Recommend retain native link and use m4 upload page, register UX difference. Supported format/trial text/family entitlement and QR/app links retained. QR embeds API key in render (`W/components/onboarding_screens.ex:168`); provide authenticated, no-store HTTP QR delivery and remove secret-bearing assigns through shared admission projection. Never promise redaction merely by not assigning a new key field.
- Demo import/removal: `W/demo_data_actions.ex:10,30,40` synchronous domain importer/destroyer and yesterday's profile-zone map/timeline landing; APIs separate. `D/demo_data/{importer,destroyer,cleanup_scope}.ex:1` retains adoption/cleanup protections. Scoped commands plus bounded asynchronous UI state, duplicate suppression, stale result timeout and reconnect refresh; do not start an independent demo job system or move code into hooks.

## Lifecycle, security and leak-risk register

These are source risks and test obligations; planning has not reproduced new defects. If implementation fixes a Rails defect, add a specific FRB + ED + changelog and report source/test citations; no blanket “native lifecycle” row hides a fix.

| Observation | Source | Required deterministic probe / successor |
| --- | --- | --- |
| map shell imports Turbo/Stimulus, maintains applications/portals, assigns global Stimulus and a global view | `app-phoenix/priv/static/js/map_shell.js:1,9,48,73,97,109,127` | native graphs have no bridge; independent hosts; delayed chunk resolves after destroy; teardown idempotence; keyed overlays stay attached to their owner |
| Main map has explicit disconnected/init guard and cleanup | `app/javascript/controllers/maps/maplibre_controller.js:175,364,398` | retain useful guards; all layer references/listeners/fetch callbacks drained; destruction during style/data init cannot create an orphan map |
| Trip init and data fetch are async; disconnect removes map/layers but init is not guarded like main map | `app/javascript/controllers/trip_maplibre_controller.js:74,101,130,204` | deferred init/data resolve after navigation does not install layers or a map |
| Photo load races a 15 s timeout; losing request/timer not universally cancelled | `app/javascript/controllers/maps/maplibre/data_loader.js:270` | abort fetch and clear per-run timer on change/destroy; late photo callback dropped |
| API client signals are selective, several family/edit reads raw fetch | `app/javascript/maps_maplibre/services/api_client.js:20,608`; `app/javascript/controllers/maps/maplibre_controller.js:1489,1791,1825` | all owned operations accept parent signal/revision; obsolete range cannot overwrite newer data; API failures stay typed |
| Poster open/download lack operation guard/signal at editor caller | `app/javascript/controllers/poster_studio_editor_controller.js:147,597`; `app/javascript/poster_studio/render/offscreen_map.js:40` | close/destroy during theme/font/idle/PNG/PDF/print upload: no new map or download, no dangling abort listener/timer; constructor failure releases container |
| Video waits first idle without abort listener; encoder/map allocations precede try block | `app/javascript/video_studio/video_renderer.js:138,167,194` | pre-aborted signal, abort before idle, constructor/context failure and encode queue error all settle and release resources; preserve encoder backpressure cancellation |
| MapPage and TripPage expose key/state/geometry; QR reads key from current_user | `D/map_page.ex:35`; `W/trips_live/show.ex:54,63`; `W/components/onboarding_screens.ex:168` | synthetic secret absent in socket state/logs, refs never echoed; no bearer on third-party tiles; cookie-auth user checked per request; datasets remain API/tiles |
| NativeAuth delegates LiveAuth whose event check only tests user existence | `W/native_auth.ex:19`; `W/live_auth.ex:45` | immutable session identity/salt + fresh status/entitlement/membership on event/params/info/async/data; mutation context rechecks before effect |
| Family/public use ActionCable and intervals | `app/javascript/controllers/shared_live_map_controller.js:46,81,275`; `app/javascript/maps_maplibre/channels/map_channel.js:148` | native authorized delivery / m4 integration; revoke in flight drops data and clears already visible data; reconnect reauthorizes; timers unsubscribed |
| Timeline and settings use frame/stream callbacks, body/global DOM listeners/poll | `app/javascript/controllers/timeline_feed_controller.js:24,131,999`; `app/javascript/controllers/maps/maplibre/settings_manager.js:576`; `app/javascript/controllers/maps/maplibre/event_handlers.js:216` | URL/selection revisions, bounded server rows and cancellation; native point address/segment/read UI; no Turbo frame in popup strings |

Workers: no first-party `new Worker` export engine was found in the inventoried map/poster/video source; MapLibre's vendored worker is still a production requirement. WebCodecs is browser-owned, not a JS worker. A new encoder worker is an open choice, not current architecture. Count shared library workers separately from host-owned resources; do not terminate a library global pool while another map is alive.

## Pure algorithms and formats to keep

| Family | Keep | Rework boundary |
| --- | --- | --- |
| Map | GeoJSON transforms/HTML escaping; geometry/circle; route segmentation/speed colors; device/time windows; flight arcs/masking; H3 resolution; tile freshness; viewport padding | Preserve pure tests; dependency-inject i18n/style/requests. Layer constructors receive map/services, not a Stimulus controller; source disposal explicit. |
| Editing/replay | editor and point histories, tile exclusions/revisions, drag gesture; day clock/minute bucketing/photo index/stack offset; deterministic timestamp/route clocks | Hook owns current operation and cleanup; server owns conflict/ownership/effects. ReplayPanel DOM/controller orchestration split. |
| Poster | paper sizes/layout geometry/DPI stepping; themes/schema/tokens/fonts/print SKUs; frame covers/text wrapping/overlay/style; PNG pHYs/CRC/zlib; one-page physical-size PDF 1.4; filenames | MapPageProvider lookup removed; cancellation/WYSIWYG renderer and native gallery commands. Static JSON/fonts/PMTiles are retained assets. |
| Video | normalization/date_range/studio_state/provenance; route_timeline/clock/smoothing/camera/render_plan/stats/color/HUD; codec negotiation/bitrate/backpressure; MP4 muxing | Renderer lifecycle/upload adapter/preview controls split; retain recipe shape validated by `D/route_videos/recipe.ex:1`. |
| Server | Areas numeric casts/relabel graph, point/segment revision effects, native poster fencing/renderer/attachments, video retention/storage jobs, demo adoption/cleanup | Scope facade / native event changes only; neither renderer engine nor ActiveStorage database formats need a rewrite. |

## Build, chunk and asset facts

- Two graphs exist. New `app-phoenix/assets/js/app.js:1` imports Phoenix/hooks/uploader; `app-phoenix/assets/js/hooks/index.js:1` has MapMatchingDemo but no Map/Trip/PublicMap/Family/PosterStudio/VideoStudio. Native esbuild is ESM+splitting and external `/maplibre/*` (`app-phoenix/config/config.exs:36`), aliases in `app-phoenix/mix.exs:60` build/deploy/digest it. Compatibility graph uses `app-phoenix/priv/static/js/app.js:1` and Rails importmap (`D/build/importmap.ex:22`, `config/importmap.rb:6,19,20,30`). Merely deleting markers will not remove its transitive imports.
- Vendored `/maplibre/6.4.1/` has main/shared/worker MJS and licence; themes `/poster_themes/*.json`, styles `/maps_maplibre/styles/*.json`, country PMTiles are public assets. `W/public_files.ex:1` serves public files; `T/dawarich/build/native_assets_test.exs:89` currently only checks main module/light/dark presence. Production browser must verify worker relative URL, MIME, CSP, RTL script, font/glyph/sprite/theme/custom-style requests, digested chunks and offline/failed chunk behavior.
- Current export imports fflate, mp4-muxer and MapLibre through Rails importmap; native package presently contains emoji-mart and spark-md5 only (`app-phoenix/assets/package.json:1`). Add only runtime packages actually needed, pinned to approved existing equivalents; do not vendor the controller import graph or pull @rails/activestorage/ActionCable into the native build.
- Existing native build checks reject Hotwire and `app/javascript` inputs, require lazy demo, bound eager demo growth to 2 KB (`T/dawarich/build/native_assets_test.exs:27,43,56`). Preserve and generalize these to recursive static **and dynamic** imports and emitted workers. Absolute map/studio KB budgets remain unknown; measure baseline/candidate bytes per page and set reviewed budgets before acceptance. Hook wrappers belong in eager bundle; library data/engines belong in lazy chunks.

## Existing coverage and migration obligations

Coverage below is inspected source, not freshly passing evidence. “No dedicated coverage found” is a bounded search result, not proof no indirect coverage exists.

| Feature | Current B tests / source anchors | M/C/R cases and browser coverage |
| --- | --- | --- |
| Map shell/URL/settings/tiles | `T/dawarich/map_page_test.exs:34,65,88`; `T/dawarich/map_window_test.exs:1`; `T/dawarich_web/standalone_map_test.exs:34,50,66`; `T/dawarich_web/api/map_endpoint_test.exs:1`, `T/dawarich_web/api/map_golden_test.exs:1`; JS map_initializer/tile_only_cutover/map_points_cache/map_data_history_bounds tests | `T/dawarich_web/map_live_test.exs:58,73,116,140,219,278,385,487` mixed; `T/dawarich_web/map_stimulus_test.exs:12` M; `T/dawarich_web/map_navigation_test.exs:32` M/B; `E/v2/map/{core,navigation,settings,settings-sections,search,performance}.spec.js:1` |
| Layers/viewport/search | JS basemap fallback/URL, timeline fit/padding, realtime filter and map_empty_click tests | `E/v2/map/layers/{points,tracks,track-segments,tracks-anomaly,visits,places,areas,photos,heatmap,advanced,family}.spec.js:1`; visits viewport-windowing and visit-create-enables-layer |
| Timeline/day/month/filter | `T/dawarich/timeline/{days,day_rows,month_summary}_test.exs:1`; `T/dawarich_web/map_frames_regression_test.exs:32,74,107`; JS timeline_entry_fit_full_track/timeline_track_click_camera/timeline_segment_hover | Frame bytes and token assertions in `T/dawarich_web/map_frames_test.exs:107,212`; single-owner Turbo test M; `E/v2/map/timeline-*.spec.js:1` (URL hydration, day-zone isolation, loading/fit, journey leg, map-sync, filters, bulk, visit merge, replay, calendar, cluster, search end-time) |
| Point/segment edit/selection | `T/dawarich/points/*`, `T/dawarich/tracks/segment_editor_test.exs:1`; `T/dawarich_web/point_delete_tile_visibility_test.exs:1`; `T/dawarich_web/map_writes_parity_test.exs:106,202`; JS map_editor/point_edit_history/panel | `T/dawarich_web/segment_actions_test.exs:1`, `T/dawarich_web/segment_frame_test.exs:1`, `T/dawarich_web/segment_write_response_test.exs:1` mixed; `E/v2/map/{point-drag-edit-mode,point-delete,area-selection,area-selection-anomaly,area-selection-delete-anomalies}.spec.js:1`; `E/v2/segment-frame-roundtrip.spec.js:1` |
| Areas | `T/dawarich_web/area_writes_regression_test.exs:17,83`; `T/dawarich_web/standalone_area_cleanup_test.exs:31`; `T/dawarich/areas_test.exs:100,186,203`; relabel worker | `E/v2/map/area-edit.spec.js:54`, layers/areas; add native modal invalid/foreign/stale/queued-relabel and focused delete graph acceptance |
| Trip/public/family/realtime | `T/dawarich_web/trip_shared_components_test.exs:1`, shared/family API golden/security tests; `T/dawarich/shared_api/{trip,points,photos,live}_test.exs:1`; JS map_channel_contract/family_map/realtime filter | `E/v2/{trips,trips-redesign,shared-trip-link,replay-photos}.spec.js:1`, `E/v2/realtime/{family,family-realtime-broadcast}.spec.js:1`, cloud/family; obsolete controller accesses must be replaced with focused observation of hook-owned map behavior |
| Replay | JS replay_profile_timezone_minutes/replay_photo_stack_offset/maplibre_profile_timezone_range | `E/v2/map/replay.spec.js:142,221,342,758,885,958` includes conditional skips for insufficient data. Ensure seeded data fulfills assertions; add destroy/reconnect/rAF/photo cancellation tests. |
| Poster | JS poster_frame_geometry/providers/studio_providers/trip_poster_flights/order_client/studio_lifecycle; `T/dawarich/posters/*_test.exs:1` | `T/dawarich_web/posters_endpoint_test.exs:16,64,105,130` mixed B/M/C; parity byte fixtures; `E/v2/map/poster-studio.spec.js:115,133,165,179,203`, trip-poster studio. No dedicated browser PDF structure/physical page check found in these specs. |
| Video | JS video_studio_{date_range,points,route_timeline,hud_overlay,codec_negotiation,map_effects,settings,load_track,mp4_encoder}; `T/dawarich/route_videos/*_test.exs:1` | `T/dawarich_web/route_video_actions_test.exs:63,169,206,288` mixed B/M/C; `E/v2/map/video-studio.spec.js:53`, `E/trips/{video-studio,video-gallery}.spec.js:1`; real render metadata and cancellation remain browser gap |
| Onboarding/demo | `T/dawarich_web/native_onboarding_test.exs:41,77,86`; `T/dawarich_web/onboarding_modal_test.exs:51,68`; `T/dawarich/demo_data_destroyer_test.exs:1` | ignored island/upload token assertions M; `E/onboarding/{getting-started,demo_data_load,demo_data_destroy,demo_data_adoption}.spec.js:1`; native auto-open/close persistence and shared shell integration need successors |

Mixed fixtures/corpora retain every ownership, numeric/timezone, effect/rollback/storage/retention field. Remove only proven orphan HTML/controller bytes. Public API corpora/HTTP download formats remain external contracts, not dispensable markup. Registers' direct readers: `T/dawarich_web/a12f3b_s02_test.exs:655`, `T/dawarich/imports/continuation_register_test.exs:6`, `T/dawarich/release/cloud_handoff_test.exs:567`; include them after implementation edits those documents, without changing Cloud guard files.

## Recommended internal split and unresolved decisions

Four parallel implementation tracks, after a shared contract sync: **6a** foundation/build/map hosts/layers/public/family; **6b** native controls/timeline/selection/edit/replay/Areas/onboarding/Immich tools; **6c** poster preview/PNG/PDF/gallery/print; **6d** video preview/MP4/upload/gallery. Integration owner (6a) owns shared app/hook indexes/routes/gates/ED+FRB+changelog; other tracks send exact patches to that owner. Each track works only on its allocated files; this planning session dispatched no agents.

Shared seams: disposable runtime + generation, typed browser read service with request cancellation, data-source snapshot/provider interface, scoped admission and mutation result tuples, keyed studio containers, lazy engine import and asset manifest, authorized m4 progress/realtime events. Accept these interfaces before parallel UI work; pure algorithms/context regressions can be started independently. See the scratch plan for per-task files/tests/sync points and size ranges.

Open decisions with defaults: cookie browser reads (preserve external Bearer APIs); PublicMap LiveView bootstrap (retain unlock HTTP); onboarding auto-open-path completion, native imports link; preserve server-gallery engine separately from local export; preserve unsupported WebCodecs refusal and current codecs; no new encoder worker until measured need; approved measured export/bundle limits (no arbitrary quality reduction); keep print ordering with stubbed acceptance; m4/m5 must supply or explicitly transfer ownership of shared public/family/upload/timeline/trip contexts. Security/privacy/cancellation improvements require specific ED/FRB classification if Rails differs.

## Track A prerequisite and baseline check (2026-10-10)

App source: `e42a6ef0f9ed8a9f1ec7f006259fdd85b56ee9cc`; E2E source: `ff256e6fd6a8a50f3f05a9e5a1e9656ef5a47b2d`. The approved milestone 6 plan's A0/O10 prerequisite is unresolved. Milestone 4's local reference advanced from inventory `96837848a` to contract documentation `09a01685a`; its implementation report still says IN PROGRESS. Milestone 5's local reference is inventory `5d3f135f5`. Neither supplies an accepted implementation interface SHA to this branch. The current app retains hybrid upload, family/public and Trip hosts. No missing ownership was transferred and no S1 handoff is claimed.

The prescribed map page/window/live/standalone API/native asset/frontend inventory batch passed 59 tests, warnings-as-errors, exit 0. Production preparation of the same source passed, exit 0. A separate minified native esbuild graph measured 167,238 eager raw bytes / 51,397 gzip bytes, four lazy chunks and 1,368 eager demo bytes. Its recursive inputs contain neither Rails JavaScript nor Hotwire. This measures the native entry graph, not the current hybrid map/studio browser transfer graph.

Temporary query probes used only synthetic recorded fixtures and counted `[:dawarich, :repo, :query]` events. Static means one HTTP GET; connected means connecting that already rendered response; range means one date patch to the DST transition day 2026-03-29. Counts exclude Redis, workers, assets and external provider work. Warm caches can reduce the first static count by one.

| Recorded variant | Static | Connected | Range patch |
| --- | ---: | ---: | ---: |
| Empty self-hosted Pro | 16–17 | 16 | 15 |
| Owned place/import, two points, profile timezone | 18 | 18 | 17 |
| Timeline and nine tags | 16 | 16 | 15 |
| Cloud Lite | 17 | 17 | 16 |
| Cloud Pro, three posters/two videos | 20 | 20 | 19 |
| Trip with synthetic path | 35–36 | 22 | unmeasured |
| Family owner | 19 | unmeasured | unmeasured |
| Family member | 19 | unmeasured | unmeasured |
| Absent public share | 2 | HTTP only | HTTP only |

Probe tests: “map baseline query instrumentation observes static connected and range reads” and “Trip family and public baseline instrumentation observes owned page reads”. Both were RED with disconnected telemetry, GREEN with the real query attachment, failed the named disconnect-telemetry mutation, and restored GREEN. The restored prescribed batch plus both probes passed 61 tests, warnings-as-errors, exit 0. Temporary tests were removed after archiving evidence; no implementation or retained regression tests changed.

A0 remains incomplete. Accepted m4/m5 interfaces or an explicit controller transfer are required before freezing S1. Active unlocked public/populated family/DST data capacity, browser per-page transferred bytes, maps/listeners/workers/rAF/object URLs, post-GC memory, eager wrapper allowance and preview concurrency remain unmeasured/unapproved. The date patch above checks query instrumentation, not DST data correctness. Standalone G44 baseline core/poster/video specs passed 23 tests, zero failures/skips/flaky, exit 0, on the source identities above. The first sandbox attempt refused Chromium MachPortRendezvous; the same command passed outside the sandbox. These existing hybrid journeys cannot substitute for native lifecycle or unmeasured resource budgets. All started services were stopped and their ports checked closed. No new runtime cap is asserted, no Rails defect was fixed, and no production code was changed.

## Results after planning

Production and tests unchanged. This document records source evidence and uncovered verification gaps; runtime map/query/leak/chunk baselines remain an implementation Task A0 obligation. No services or test suites started. No Rails defect was fixed during planning.

## Rails bugs fixed (changelog)

none

## Appendix — complete browser source census

Generated from the inventoried files at the head above. Counts are lines; citations identify file beginnings. `MapLibre managers` are already plain classes but remain controller-coupled; `compatibility hooks` are not native asset entries. The census includes secondary map hosts (public stats/preview) so they cannot be accidentally left importing a legacy controller.

### Controllers

| File | Lines |
| --- | ---: |
| `app/javascript/controllers/maps/maplibre_controller.js:1` | 2084 |
| `app/javascript/controllers/maps/maplibre_realtime_controller.js:1` | 264 |
| `app/javascript/controllers/maps/immich_enrich_controller.js:1` | 647 |
| `app/javascript/controllers/trip_maplibre_controller.js:1` | 743 |
| `app/javascript/controllers/trip_maplibre_preview_controller.js:1` | 178 |
| `app/javascript/controllers/shared_trip_map_controller.js:1` | 316 |
| `app/javascript/controllers/shared_live_map_controller.js:1` | 284 |
| `app/javascript/controllers/public_stat_map_controller.js:1` | 269 |
| `app/javascript/controllers/family_map_controller.js:1` | 194 |
| `app/javascript/controllers/timeline_feed_controller.js:1` | 1008 |
| `app/javascript/controllers/map_panel_controller.js:1` | 376 |
| `app/javascript/controllers/map_controls_controller.js:1` | 102 |
| `app/javascript/controllers/map_settings_dirty_controller.js:1` | 124 |
| `app/javascript/controllers/map_theme_editor_controller.js:1` | 178 |
| `app/javascript/controllers/area_drawer_controller.js:1` | 150 |
| `app/javascript/controllers/area_creation_v2_controller.js:1` | 113 |
| `app/javascript/controllers/place_detail_controller.js:1` | 32 |
| `app/javascript/controllers/place_creation_controller.js:1` | 182 |
| `app/javascript/controllers/visit_creation_v2_controller.js:1` | 296 |
| `app/javascript/controllers/poster_studio_editor_controller.js:1` | 923 |
| `app/javascript/controllers/poster_theme_picker_controller.js:1` | 71 |
| `app/javascript/controllers/video_studio_controller.js:1` | 826 |
| `app/javascript/controllers/onboarding_modal_controller.js:1` | 209 |
| `app/javascript/controllers/demo_banner_controller.js:1` | 33 |

24 files, 9,602 lines.

### Map modules

| File | Lines |
| --- | ---: |
| `app/javascript/maps_maplibre/channels/map_channel.js:1` | 155 |
| `app/javascript/maps_maplibre/components/photo_popup.js:1` | 114 |
| `app/javascript/maps_maplibre/components/replay_photo_stack.js:1` | 110 |
| `app/javascript/maps_maplibre/components/replay_photo_stack_offset.js:1` | 12 |
| `app/javascript/maps_maplibre/components/toast.js:1` | 215 |
| `app/javascript/maps_maplibre/components/upgrade_banner.js:1` | 83 |
| `app/javascript/maps_maplibre/components/visit_card.js:1` | 169 |
| `app/javascript/maps_maplibre/components/visit_place_search.js:1` | 285 |
| `app/javascript/maps_maplibre/editing/edit_success_indicator.js:1` | 52 |
| `app/javascript/maps_maplibre/editing/editable_track_data.js:1` | 129 |
| `app/javascript/maps_maplibre/editing/editor_history.js:1` | 123 |
| `app/javascript/maps_maplibre/editing/map_editor.js:1` | 542 |
| `app/javascript/maps_maplibre/editing/point_drag_gesture.js:1` | 216 |
| `app/javascript/maps_maplibre/editing/point_edit_history.js:1` | 112 |
| `app/javascript/maps_maplibre/editing/point_edit_history_panel.js:1` | 167 |
| `app/javascript/maps_maplibre/editing/tile_exclusions.js:1` | 63 |
| `app/javascript/maps_maplibre/layers/anomalies_layer.js:1` | 174 |
| `app/javascript/maps_maplibre/layers/areas_layer.js:1` | 67 |
| `app/javascript/maps_maplibre/layers/base_layer.js:1` | 150 |
| `app/javascript/maps_maplibre/layers/day_routes_layer.js:1` | 387 |
| `app/javascript/maps_maplibre/layers/editable_track_layer.js:1` | 80 |
| `app/javascript/maps_maplibre/layers/family_layer.js:1` | 432 |
| `app/javascript/maps_maplibre/layers/flights_layer.js:1` | 105 |
| `app/javascript/maps_maplibre/layers/fog_hexagon_source.js:1` | 87 |
| `app/javascript/maps_maplibre/layers/fog_layer.js:1` | 402 |
| `app/javascript/maps_maplibre/layers/heatmap_layer.js:1` | 105 |
| `app/javascript/maps_maplibre/layers/hexagon_layer.js:1` | 423 |
| `app/javascript/maps_maplibre/layers/photos_layer.js:1` | 656 |
| `app/javascript/maps_maplibre/layers/places_layer.js:1` | 66 |
| `app/javascript/maps_maplibre/layers/points_mvt_layer.js:1` | 292 |
| `app/javascript/maps_maplibre/layers/recent_point_layer.js:1` | 82 |
| `app/javascript/maps_maplibre/layers/replay_marker_layer.js:1` | 209 |
| `app/javascript/maps_maplibre/layers/replay_photo_layer.js:1` | 102 |
| `app/javascript/maps_maplibre/layers/scratch_layer.js:1` | 187 |
| `app/javascript/maps_maplibre/layers/selected_points_layer.js:1` | 100 |
| `app/javascript/maps_maplibre/layers/selection_layer.js:1` | 202 |
| `app/javascript/maps_maplibre/layers/tracks_layer.js:1` | 568 |
| `app/javascript/maps_maplibre/layers/tracks_mvt_layer.js:1` | 231 |
| `app/javascript/maps_maplibre/layers/trip_plan_layer.js:1` | 121 |
| `app/javascript/maps_maplibre/layers/visits_layer.js:1` | 235 |
| `app/javascript/maps_maplibre/managers/replay_day_clock.js:1` | 172 |
| `app/javascript/maps_maplibre/managers/replay_manager.js:1` | 488 |
| `app/javascript/maps_maplibre/managers/replay_panel.js:1` | 853 |
| `app/javascript/maps_maplibre/managers/replay_photo_index.js:1` | 80 |
| `app/javascript/maps_maplibre/managers/replay_point_utils.js:1` | 81 |
| `app/javascript/maps_maplibre/managers/timeline_segment_hover.js:1` | 183 |
| `app/javascript/maps_maplibre/services/api_client.js:1` | 1048 |
| `app/javascript/maps_maplibre/services/location_search_service.js:1` | 117 |
| `app/javascript/maps_maplibre/utils/basemap_fallback.js:1` | 75 |
| `app/javascript/maps_maplibre/utils/basemap_url.js:1` | 65 |
| `app/javascript/maps_maplibre/utils/cleanup_helper.js:1` | 55 |
| `app/javascript/maps_maplibre/utils/device_points.js:1` | 22 |
| `app/javascript/maps_maplibre/utils/family_member_color.js:1` | 15 |
| `app/javascript/maps_maplibre/utils/feature_to_photo.js:1` | 8 |
| `app/javascript/maps_maplibre/utils/flight_arcs.js:1` | 101 |
| `app/javascript/maps_maplibre/utils/flight_mask.js:1` | 103 |
| `app/javascript/maps_maplibre/utils/format_helpers.js:1` | 57 |
| `app/javascript/maps_maplibre/utils/fps_monitor.js:1` | 49 |
| `app/javascript/maps_maplibre/utils/geojson_transformers.js:1` | 151 |
| `app/javascript/maps_maplibre/utils/geometry.js:1` | 124 |
| `app/javascript/maps_maplibre/utils/h3_resolution.js:1` | 16 |
| `app/javascript/maps_maplibre/utils/hexagon_popup.js:1` | 66 |
| `app/javascript/maps_maplibre/utils/layer_gate.js:1` | 138 |
| `app/javascript/maps_maplibre/utils/lazy_loader.js:1` | 76 |
| `app/javascript/maps_maplibre/utils/map_padding.js:1` | 24 |
| `app/javascript/maps_maplibre/utils/map_view_store.js:1` | 73 |
| `app/javascript/maps_maplibre/utils/marker_theme.js:1` | 26 |
| `app/javascript/maps_maplibre/utils/performance_monitor.js:1` | 110 |
| `app/javascript/maps_maplibre/utils/popup_theme.js:1` | 124 |
| `app/javascript/maps_maplibre/utils/progressive_loader.js:1` | 107 |
| `app/javascript/maps_maplibre/utils/realtime_date_filter.js:1` | 47 |
| `app/javascript/maps_maplibre/utils/realtime_points.js:1` | 99 |
| `app/javascript/maps_maplibre/utils/route_segmenter.js:1` | 289 |
| `app/javascript/maps_maplibre/utils/rtl_text_plugin.js:1` | 8 |
| `app/javascript/maps_maplibre/utils/search_manager.js:1` | 790 |
| `app/javascript/maps_maplibre/utils/settings_manager.js:1` | 452 |
| `app/javascript/maps_maplibre/utils/speed_colors.js:1` | 239 |
| `app/javascript/maps_maplibre/utils/style_manager.js:1` | 496 |
| `app/javascript/maps_maplibre/utils/tile_freshness.js:1` | 18 |
| `app/javascript/maps_maplibre/utils/time_overlap.js:1` | 22 |
| `app/javascript/maps_maplibre/utils/trip_plan.js:1` | 43 |
| `app/javascript/maps_maplibre/utils/websocket_manager.js:1` | 84 |

82 files, 15,204 lines.

### MapLibre managers

| File | Lines |
| --- | ---: |
| `app/javascript/controllers/maps/maplibre/area_selection_manager.js:1` | 735 |
| `app/javascript/controllers/maps/maplibre/data_loader.js:1` | 409 |
| `app/javascript/controllers/maps/maplibre/date_manager.js:1` | 116 |
| `app/javascript/controllers/maps/maplibre/event_handlers.js:1` | 927 |
| `app/javascript/controllers/maps/maplibre/filter_manager.js:1` | 55 |
| `app/javascript/controllers/maps/maplibre/layer_manager.js:1` | 544 |
| `app/javascript/controllers/maps/maplibre/layer_visibility_manager.js:1` | 486 |
| `app/javascript/controllers/maps/maplibre/map_data_manager.js:1` | 548 |
| `app/javascript/controllers/maps/maplibre/map_initializer.js:1` | 164 |
| `app/javascript/controllers/maps/maplibre/places_manager.js:1` | 365 |
| `app/javascript/controllers/maps/maplibre/settings_manager.js:1` | 1106 |
| `app/javascript/controllers/maps/maplibre/visits_manager.js:1` | 474 |

12 files, 5,929 lines.

### Poster modules

| File | Lines |
| --- | ---: |
| `app/javascript/poster_studio/data/fonts.js:1` | 46 |
| `app/javascript/poster_studio/data/layouts.js:1` | 105 |
| `app/javascript/poster_studio/data/paper_sizes.js:1` | 72 |
| `app/javascript/poster_studio/data/print_products.js:1` | 14 |
| `app/javascript/poster_studio/data/protomaps_schema.js:1` | 71 |
| `app/javascript/poster_studio/data/providers.js:1` | 183 |
| `app/javascript/poster_studio/data/theme_loader.js:1` | 94 |
| `app/javascript/poster_studio/export/download.js:1` | 26 |
| `app/javascript/poster_studio/export/pdf_encoder.js:1` | 72 |
| `app/javascript/poster_studio/export/png_encoder.js:1` | 90 |
| `app/javascript/poster_studio/render/frame_geometry.js:1` | 52 |
| `app/javascript/poster_studio/render/offscreen_map.js:1` | 62 |
| `app/javascript/poster_studio/render/overlay.js:1` | 148 |
| `app/javascript/poster_studio/render/style_builder.js:1` | 231 |
| `app/javascript/poster_studio/render/text_layout.js:1` | 55 |
| `app/javascript/poster_studio/ui/exporter.js:1` | 61 |
| `app/javascript/poster_studio/ui/order_client.js:1` | 57 |
| `app/javascript/poster_studio/ui/preview.js:1` | 104 |

18 files, 1,543 lines.

### Video modules

| File | Lines |
| --- | ---: |
| `app/javascript/video_studio/camera_path.js:1` | 47 |
| `app/javascript/video_studio/codec_negotiation.js:1` | 47 |
| `app/javascript/video_studio/color_util.js:1` | 30 |
| `app/javascript/video_studio/date_range.js:1` | 146 |
| `app/javascript/video_studio/geo.js:1` | 21 |
| `app/javascript/video_studio/hud_fonts.js:1` | 49 |
| `app/javascript/video_studio/hud_format.js:1` | 77 |
| `app/javascript/video_studio/hud_overlay.js:1` | 405 |
| `app/javascript/video_studio/load_track.js:1` | 8 |
| `app/javascript/video_studio/map_effects.js:1` | 108 |
| `app/javascript/video_studio/mp4_encoder.js:1` | 139 |
| `app/javascript/video_studio/path_smoothing.js:1` | 54 |
| `app/javascript/video_studio/points.js:1` | 54 |
| `app/javascript/video_studio/render_plan.js:1` | 37 |
| `app/javascript/video_studio/route_clock.js:1` | 65 |
| `app/javascript/video_studio/route_timeline.js:1` | 154 |
| `app/javascript/video_studio/save_video.js:1` | 91 |
| `app/javascript/video_studio/studio_state.js:1` | 196 |
| `app/javascript/video_studio/video_renderer.js:1` | 316 |
| `app/javascript/video_studio/video_stats.js:1` | 117 |

20 files, 2,161 lines.

### Compatibility hooks

| File | Lines |
| --- | ---: |
| `app-phoenix/priv/static/js/hooks/video_studio.js:1` | 143 |
| `app-phoenix/priv/static/js/hooks/video_studio_controls.js:1` | 157 |
| `app-phoenix/priv/static/js/hooks/video_studio_dates.js:1` | 176 |
| `app-phoenix/priv/static/js/hooks/video_studio_preview.js:1` | 184 |
| `app-phoenix/priv/static/js/hooks/video_studio_render.js:1` | 129 |
| `app-phoenix/priv/static/js/hooks/video_studio_save.js:1` | 45 |

6 files, 834 lines.

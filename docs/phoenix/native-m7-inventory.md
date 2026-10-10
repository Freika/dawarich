# Native frontend milestones 7–8: removal inventory and acceptance baseline

Date: 2026-10-10. Planning only. Source snapshot: `bdaa9aa363230857b5a96fe67eb1e6d10f7390b3` (verified 3b descendant); E2E source: `ff256e6fd6a8a50f3f05a9e5a1e9656ef5a47b2d`. No production/test changes, measurements, suites or services were run for this inventory. Counts below are static search results, not runtime reachability proof.

Source scope: `docs/phoenix/native-frontend-contexts-plan-20261008.md:138` (7), `:154` (8). Accepted ADR-0017 supersedes the old exact-markup/coexistence frontend contract. The verified 3b plan and `docs/phoenix/native-m3b-inventory.md:5` supply the acceptance template and review lessons. This document deliberately distinguishes a last **feature consumer** from deletion of the **shared mechanism** in 7.

Citation roots: `W/` = `app-phoenix/lib/dawarich_web/`; `D/` = `app-phoenix/lib/dawarich/`; `T/` = `app-phoenix/test/`; `J/` = `app-phoenix/priv/static/js/`; `N/` = `app-phoenix/assets/js/`; `E/` = the E2E repository source inspected for this task. All other paths are repository-relative unless named workspace artifacts. Allocation details belong to the controller's execution configuration, never committed application/test/document defaults.

## Findings and removal rules

1. There are two client entrypoints. `N/app.js:1` imports only Phoenix, hooks and the native uploader. `J/app.js:1` starts the hybrid runtime; its imports, Turbo ownership predicate, events, method links and teardown remain live through hybrid roots (`W/layouts/root.html.heex:31`, `W/layouts/map_root.html.heex:31`). Remove the entire hybrid entrypoint in 7, not only the Stimulus import.
2. Even `W/layouts/native_root.html.heex:14` resolves six stylesheets through `W/assets.ex:80` and the Sprockets manifest. Milestone 1 removed native JS importmap use on migrated pages, not the whole native release's Rails asset resolution. Milestone 7 must inventory CSS, fonts, SVG/image references, worker URLs and renderer data before replacing this resolver.
3. The last shared bridge consumer is the map/studio batch (6), after auth (3c), Places list (3d), actions/uploads/family/sharing (4) and data pages/editor (5). Shared shell/onboarding spans 6; shared roots, loader, envelopes, route ownership dispatcher and packaging belong to 7.
4. Route gates frequently combine routing ownership with authorization, supported formats, entitlement, encryption or provider refusal. Delete ownership/handback decisions only after their real constraints have native successors. `W/standalone_routes.ex:6` serves real API URLs outside the router: move these routes before deleting Strangler's dispatch branch.
5. Do not delete Rails cookies/session salt, CSRF, ActiveRecord encryption, rich-content storage, signed blob/download URLs, API formats or independently consumed ActionCable wire contracts because of their names. A native UI with no Hotwire can still retain an explicitly documented external protocol adapter. No native browser consumer of Turbo streams remains at completion.
6. Native Cloud lifecycle admission is outside this plan. Do not change release/lifecycle/native modules, entrypoint-env-guard or their protected test. Never make native Cloud default. Whole-app fallback is a deployment choice, not a per-page proxy or same-URL retry.

## Dependency and last-consumer matrix

`7 audit` means shared deletion/retargeting after all listed feature consumers migrate; it is not permission to delete a security check. `retain` means a real contract survives, with tests retargeted where its internal caller changes.

| ID | Source / mechanism | Current consumers and obligation | Last consumer / owner | Execution status (2026-10-10 pinned branches) |
| --- | --- | --- | --- | --- |
| L01 | `J/rails_bridge.js:38,46,85,129` | Eager controller registration plus lazy loading, disabled/inert form readiness, per-island application and `StimulusIslands` registry. Family/share/imports/ordinary hybrid islands still use these | 3c/3d/4/5/6 migrate their pages; 7 deletes bridge | 3c delivered; 3d delivered; 4 partial; 5 partial; 6 partial; shared loader remains |
| L02 | `J/map_shell.js:2,12,58,73,109` | Turbo import, MapApplication subclass, cross-island controller lookup, studio body portals, map/studio disposal | 6 replaces map/replay/poster/video lifecycles; 7 removes startup/file | 6 foundation delivered; integrated map/studio hosts pending |
| L03 | `J/app.js:30,38,58,70,76,88,111,121` | Turbo ownership, LiveSocket hooks and Turbo navigation/teardown, confirmation and synthetic method-link form submission | Feature forms 3c–6; 7 deletes old entrypoint; keep native dialog/menu/navigation behavior | 3c/3d delivered; 4/5/6 partial; shared entrypoint remains |
| L04 | `J/family_page.js:1,4`; `W/families_live/show.ex:78` | `railsBridge` and family-map controller lookup, polling/location rendering | 4 owns membership/consent/update admission; 6 removes final MapLibre/controller lookup | 4c native family page delivered; 6 native family reader delivered; integrated hook replacement pending |
| L05 | `J/hooks/video_studio.js:81`; `J/hooks/video_studio_save.js:2,28`; `app/javascript/video_studio/save_video.js:82` | Stimulus-shaped targets/application, Flash controller and `Turbo.renderStreamMessage` on save | 6 replaces uploader/save acknowledgement and gallery updates; preserve download/render formats | 6d codec/render/upload context delivered; native video hook/gallery acknowledgement pending |
| L06 | `J/rails_bridge.js:57,97,204`; `J/map_shell.js:127` | Manual stream parsing/flash forwarding, before-stream handler and lazy Turbo frame startup | 4 sharing/job streams; 5 stats/digest/trip streams; 6 maps/studios; 7 removes shared handlers | 4/5/6 partial; shared stream parser remains |
| L07 | `W/auth_form.ex:26`; `W/auth_registration/form/new.html.heex:24`; `W/auth_otp/form/challenge.html.heex:14`; `W/auth_two_factor/form/show.html.heex:45`; `W/auth_account_link/form/challenge.html.heex:21` | Turbo form attributes on auth HTTP responses; cookies/remember/OTP/recovery are real contracts | 3c native templates/root; retain HTTP identity/session/CSRF behavior | 3c delivered on branch; HTTP identity/storage contracts retained |
| L08 | `W/places_live/index.ex:102`; `W/components/nearby_places.ex:22`; `W/components/place_drawer_frame.ex:16`; `W/place_actions.ex:35` | List/delete/drawer and nearby/map create streams share adapters | 3d list/context; 6 last map/drawer consumer; do not remove shared create/delete early | 3d list/detail delivered; 6b map commands delivered; shared map frame route still pending |
| L09 | `W/imports_live/new.ex:107`; `W/imports_live/index.ex:190`; `W/imports_extraction_stream.ex:12`; `W/components/import_row.ex:160`; `W/components/export_row.ex:70` | Upload controller, extraction acknowledgement, ignored rows, Turbo confirmation/links | 4 upload/progress/extraction/export events; preserve signed download HTTP | 4 imports list/show/new/upload delivered; export page and remaining actions pending |
| L10 | `W/notifications_live/index.ex:63`; `W/components/navbar_end.ex:75`; `D/cable/turbo_events.ex:59,64`; `app/javascript/channels/notifications_channel.js:1` | Turbo navbar/list/badge broadcasting and browser ActionCable subscription | 4 authorized PubSub/native shell updates; 7 orphan relay/wire audit | 4c admission scaffolding delivered; notification list/badge producer migration pending |
| L11 | `W/families_live/form.ex:60`; `W/family_sharing_actions.ex:49`; `W/share_management_document.ex:31`; `W/components/share_hub/frame.html.heex:1`; `W/share_management_streams.ex:25` | Membership/invitations/requests/consent/share dialogs and generated streams | 4 actions/shell; 6 last family/public map DOM; 7 retained external transport audit | 4c family delivered; sharing context delivered, sharing page/public hosts pending 4c/6 |
| L12 | `W/components/sharing_parts.ex:30`; `W/digest_sharing.ex:71`; `W/stats_sharing_request.ex:17` | Stats/digest sharing modal and Turbo format negotiation shared with data pages | 4 shared command/admission; 5 last stats/digest presentation | 4c command context delivered; 5 stats/digest presentations pending |
| L13 | `W/components/chartkick.ex:33`; `W/components/heatmap_parts.ex:29`; `W/components/stats_month.ex:70`; `W/insights_live/index.ex:104`; `W/digests_live/show.ex:27` | Chart/heatmap controllers, chartkick boot, `rails_flash`, stats/digest/insights fragments | 5 named library hooks, URL state, bounded queries/async results | 5 charts/heatmap/context/async delivered; stats/insights/digests pages pending |
| L14 | `W/trips_live/form.ex:23,38`; `W/components/trip_form.ex:54`; `W/trip_note_actions.ex:33`; `W/layouts/root.html.heex:53`; `config/importmap.rb:27` | Trix/@rails/actiontext, trip description/note forms and streams; form currently also uses MapShell | 5 editor/attachment and notes; 6 last map integration; retain sanitized ActionText data/ownership | 5b native forms/detail/notes/editor delivered; route integration and 6 trip-map host pending |
| L15 | `W/achievements_live.ex:88`; `W/achievement_card.ex:69`; `W/achievement_actions/response.ex:60` | Card modal/drawing/sharing/unlock attributes; some unlock behavior already native (`N/hooks/index.js:1`) | 5 achievements pages/public metadata; 6 only where shared map/studio hook is still used | 5 achievements page/public card migration pending; 6 map host pending |
| L16 | `W/layouts/map.html.heex:22,29`; `W/components/map_index.ex:33`; map/replay/settings/timeline components in Appendix A; `app/javascript/controllers/maps/maplibre/event_handlers.js:216` | MapShell/Stimulus, lazy address/calendar/feed/residency/segments frames, selection/drawing/replay, dynamic frame HTML in popup | 6 map browser modules and JSON/API/native fragment successors | 6 foundation/entities/photo/family reads and 6b tools delivered; top-level map integration pending |
| L17 | `W/posters_controller.ex:94,124`; `W/route_video_actions.ex:58`; `D/posters/progress_worker.ex:50`; `W/components/route_video_streams.ex:23` | Poster/video create/delete/progress/gallery stream responses | 6 native studio and durable progress delivery; preserve renderer payload and signed downloads | 6c poster runtime/gallery delivered; 6d video engine/upload delivered, host/gallery pending |
| L18 | `W/components/chrome.ex:100`; `W/components/settings_parts.ex:20`; `W/components/onboarding_modal.ex:34`; `W/layouts/root.html.heex:25` | Hybrid shell/form islands, legacy settings-tab branch, morph refresh metadata, onboarding demo/upload/complete | 4 upload; 6 onboarding/demo last consumer; 7 delete shared hybrid branches/defaults | 4 upload and 6b onboarding/demo delivered; integrated shell consumer sweep pending |
| L19 | `W/rails_widgets.ex:6`; map/family/stats/digest/trip LiveViews `rails_flash` handlers | Stream payload converted to arbitrary flash event | 4/5/6 replace feature acknowledgement; 7 removes orphan helper, not normal native flash | 4/5/6 partial; native flash retained; orphan helper deletion waits for S1 |
| L20 | `W/layouts.ex:22`; `W/assets.ex:4,58,87`; `W/endpoint.ex:20,30,35`; `config/importmap.rb:13,16` | Hybrid importmap, bridge script hashes/static mounts, Rails manifest/import discovery | 7 after 6; native `/native` mount stays | 6 last feature handoff pending; shared 7 A1/A3 removal pending |
| L21 | `app-phoenix/lib/mix/tasks/dawarich.build_inputs.ex:13,24`; `D/build/importmap.ex:20`; `D/build/sprockets/env.ex:22` | Parse Rails importmap and compile Sprockets load paths; export runtime data/i18n/achievements in same task | 7 splits native asset build from needed data export; preserve data and theme | 6 last feature assets pending; shared 7 A3 build split pending; data retained |
| L22 | `docker/Dockerfile:49,52,62,69,76,111,113,122,126` | Native esbuild exists but native image still copies Sprockets outputs, Rails JS/vendor source, fonts/images and Tailwind input | 7 native package/payload graph; renderer/geodata/Swagger stay; Rails build remains separately supported | 6 renderer/worker/export assets partial; shared 7 A4 packaging pending |
| L23 | `W/page_envelope.ex:11,55,160,177,296`; `W/turbo_visit.ex:25`; `W/insights_visit.ex:8`; `W/insights_frame.ex:8` | `.html`/format rewriting, XHR/Turbo minimal layouts, reload/flash handoff and special navigation endpoints | Features 3c–6 stop frame use; 7 extracts required HTML URL negotiation then deletes frame/coexistence envelope behavior | 3c documents and 3d list envelope delivered; 4/5/6 remaining frames pending; shared 7 B2 |
| L24 | `W/strangler.ex:73,113,163,214`; `W/endpoint.ex:45`; `W/slices.ex:14`; all route metadata in Appendix A | Route ownership, rails_gate/rails_key, enabled slices, constraints, proxy/standalone dispatcher, pre-effect pin handbacks | 7 preserves admission/constraint semantics as direct router/plug contracts; no native route reaches Rails | 3d ownership removed for list; 4c/5 native route groups partial; shared 7 B1–B3 pending |
| L25 | `W/rails_proxy.ex:27,47`; `W/cable_proxy.ex:1`; `D/front.ex:24,40,43`; `D/application.ex:100` | HTTP/body/socket proxy and embedded Puma routing | 7 removes request-level coexistence; do not alter protected lifecycle/defaults; document external whole-app Rails fallback | 3c–6 native feature handoffs incomplete; shared 7 B3 pending; protected operational seam retained |
| L26 | `W/standalone_routes.ex:6,53,58,66,72`; `W/api_routes.ex:36,141,249`; `W/storage_routes.ex:52` | API routes reached only through secondary dispatch; account deletion/photos/map/storage gates carry real checks | 7 explicit API routes with same method/HEAD/body/host/auth/rate/active-user policies before dispatcher removal | 6 spatial last feature owner; secondary API dispatch still live; 7 B1 promotion pending |
| L27 | `D/cable.ex:10`; `D/cable/events_relay.ex:63`; `D/cable/turbo_events.ex:5,72`; `W/cable_routes.ex:15`; `app/javascript/channels/consumer.js:4` | Native/UI and potentially independent Rails-compatible socket clients share buses/frames/events | 4 notification/import consumers, 5 recalculation, 6 realtime public/map/studio; 7 removes orphan UI Turbo serialization only after protocol consumer audit | 4c family and 5b trip invalidations delivered; 4 notifications and 6 realtime/studio partial; external audit B0 |

### Native graph is narrower than the Rails checkout

`app-phoenix/assets/package.json:4` currently contains emoji-mart/data and spark-md5, with no Hotwire. `N/hooks/map_matching_demo.js:5` lazily imports vendored MapLibre plus native demo/style code; `N/hooks/emoji_picker.js:2` lazily loads emoji dependencies. These are positive native examples, not deletion targets. Rails `package.json:7` and `config/importmap.rb:13` still serve the separately supported Rails application. Do not remove those packages globally to make a native grep green.

All controller modules are made dynamically addressable by `config/importmap.rb:16` and `J/rails_bridge.js:41`; availability does not prove a rendered consumer. Appendix C lists every controller entrypoint, including orphan candidates. Map utilities can be reused only after their import closure is plain JS: `Flash` and channel consumers are transitive dependencies, not harmless because their caller has no `@hotwired` string. A0 corrects `D/build/frontend_inventory.ex` so a direct-upload finding is an adapter, not a Hotwire runtime. Native `N/uploaders/direct.js` remains valid. The graph audit follows actual esbuild input edges including dynamic/external imports; it does not classify pinned-but-unreached modules or negative test literals as fetched.

## Test-retarget contract

B = behavior/data/privacy/external wire assertion; M = old markup/asset mechanism; C = coexistence/ownership handback. A file can contain all three. Keep B on its real boundary; retire M/C only with a named successor and recorded fixture-reader audit. Proposed names below are requirements for implementation, not claims those tests exist today. Appendix B covers every matching file, including register/source regressions that must not be discarded.

| Existing exact case or case family | Classification / milestone | Required named successor / retained behavior |
| --- | --- | --- |
| `T/dawarich_web/assets_test.exs:99` map_shell served/versioned; `:120` rails_bridge served/imported; `:136` StimulusIslands; `:153` inline family frames activate Turbo | M, 7 | `native production pages resolve all scripts and lazy chunks without legacy entrypoints`; map/consent lifecycle B in 6/4 |
| `T/dawarich/build/importmap_test.exs:14,56,71`; Sprockets tests in Appendix B; `T/dawarich/build/compare_build_inputs_test.exs:82` manifest rules | M, 7 | `native release asset build succeeds without Rails importmap or Sprockets inputs`; `missing native asset fails the production build`; keep data/timezone/gzip/Swagger invariants separately |
| `T/dawarich_web/sharing_bridge_test.exs:4,85,116` stream flash/readiness/pre-join cases | M+B, 4 then 7 | `sharing submit acknowledges once before and after reconnect`; `failed sharing leaves values editable with the translated alert`; revoke location privacy B at `:46` survives in family/map tests |
| `spec/javascript/phoenix_rails_bridge_stimulus_test.mjs:19` global controller lookup | M, 7 | `map and family hooks initialize and destroy independent instances without global registries` (6) |
| `T/client/retained_turbo_actions_test.mjs:9` join rendered Turbo destination | M+B, 4/5 then 7 | `trip and family mutations keep correct native destination and feedback after reconnect` |
| `T/client/turbo_navigation_test.mjs:17` hybrid source loader; `T/dawarich_web/turbo_handback_test.exs:30,62` native reload/handback | C, 7 | `native navigation never requests a Rails upstream`; `native rejection reaches its distinct authorized destination once` |
| `T/client/account_menu_patch_test.mjs:47,59,71,78` dialogs/account disclosure reconciliation | B, 7 retarget source import | Preserve all four semantics against `N/app.js`; browser keyboard/focus/Escape/back-forward successors |
| `T/dawarich_web/map_stimulus_test.exs:12,19`; `T/support/map_stimulus.ex:4`; parity map controller-value cases | M, 6 | `native map layers selection replay and trip camera preserve behavior after reconnect`; preserve GeoJSON/MVT/effects fixtures |
| `T/dawarich_web/layout_parity_test.exs:139,168,204,220,239,260` exact root/navbar/attributes/head/flash families | M+B, 3c/5/6 then 7 | `native shell preserves localized navigation consent theme and accessible feedback`; keep no-inline-navbar-query cases `:82,100` |
| `T/dawarich_web/page_envelopes_test.exs:65,87` `.html`/format URL behavior | B, 7 | `document HTML aliases preserve query and authorization`; same API negotiation contract where independently consumed |
| Same file `:111,143,192,223,247,271,303` fragment/frame/exact Rails HTML/coexistence families | M/C+B, 4–6 then 7 | `native documents render full accessible pages without frame envelopes`; retain public unlock/privacy and redirects in feature tests |
| Same file `:156,319,351,373,386,396,409,418` calendar/MIME/status cases | Mixed B/M, 6 then 7 | Preserve malformed-MIME fail-closed and real API formats. Retire Turbo-only calendar MIME/templates with named `native calendar rejects unsupported formats without effects`, plus ED/DRB reconciliation when preserved Rails defects change |
| `T/dawarich_web/strangler_test.exs:45,50,72,87,98` malformed gate / Puma / rails_key / slices / health replay | C+B, 7 | `native endpoint rejects unknown and retired routes locally`; retain original HEAD rate method `:65`, readiness/health semantics, constraints and admission tests |
| `T/dawarich_web/rails_proxy_test.exs:1`; cable proxy/frame tests; request replay/handback files in Appendix B | C+B, 7 | Proxy-only tests retire with whole-app fallback smoke; origin, cookie, limits, body/HEAD/API constraints retain direct native successors |
| `T/dawarich_web/native_pages_hotwire_free_test.exs:12`; `T/dawarich/build/native_assets_test.exs:31` | B+structural gate, 7/8 | Extend all routes, dialogs, auth/public/map/studio flows; emitted import graph + browser runtime/network checks, lazy demo/eager bundle cap still enforced |
| `T/dawarich_web/a12f3a_o_closure_test.exs`; `a12f3b_s02_test.exs` | B/register readers, 7/8 | Keep current ledger/data assertions; any ED/FRB/DRB changes trigger reader tests and source citations; never broadly regenerate HTML/JSON |

### Fixture and deletion audit

`T/support/parity_html.ex:5` normalizes Rails markup and `T/support/map_stimulus.ex:4` adds deliberate controller-sensitive comparison. Feature owners remove only their obsolete M cases; 7 then removes orphan comparator branches/helpers. `page_envelopes`, `standalone/html_pages`, `layouts`, map/frame/sharing fixture corpora can have mixed consumers. Resolve `T/fixtures` links first, list readers before deletion, and leave pruning to the owning E2E checkout. Preserve behavioral JSON, signed-cookie/crypto/storage protocol fixtures, synthetic import/export data and geometry. The 3b review found fourteen orphan HTML files in an external fixture checkout; they were restored rather than silently pruning another owner's files (`docs/phoenix/native-m3b-inventory.md:408`).

## Routing and feature-directory restructuring

Suggested physical grouping preserves module names initially, URLs, live_session boundaries and `Accounts.Scope` interfaces. Move only surviving code; do not rename a module and change behavior in the same task. No domain context imports a web template/Plug/socket. Infrastructure exceptions are listed, not mistaken for business modules.

| Surviving feature | Proposed web grouping | Boundary / last migration |
| --- | --- | --- |
| Auth/settings/admin/account | `W/features/accounts/`, `features/settings/`, `features/admin/` with LiveViews, HTTP adapters, components and adjacent HEEx | 3c completion; current NativeAuth/AdminLiveAuth/operator proof and per-event admission preserved |
| Tags/Places/Areas | `features/tags/`, `features/places/`, `features/areas/` | 3d Places list, 6 map forms; APIs stay under `W/api/` initially |
| Imports/exports/notifications/family/sharing | corresponding `features/<name>/` | 4 events/uploads; family/public map hooks supplied by 6 |
| Points/trips/visits/stats/insights/digests/achievements | corresponding `features/<name>/` | 5 data/editor; 6 maps/studios |
| Map/studios | `features/maps/`, `features/posters/`, `features/videos/`; native JS `features/maps/`, `features/studios/` | 6 plain browser module contracts; renderer implementation remains separate |
| Shared | `W/components/`, `W/layouts/`, `W/auth/`, `W/transport/` only for real shared responsibilities | 7 explicit route groups by feature; no new catch-all facade replacing Strangler |

Route macros currently scatter through `W/router.ex:1`, `W/rails_pages_routes.ex:84`, `W/a8_routes.ex:19`, `W/a9_routes.ex:21`, `W/a10_routes.ex:26`, `W/page_routes.ex:15` and other Appendix A rows. First record a method/path/handler/pipeline/session ledger including StandaloneRoutes, then simplify by feature. Keep HEAD normalization, host/SSL/rate/body/origin policies, anonymous vs user/admin/operator/public sessions and nonnumeric/oversized-id refusals. `rails_gate` removal is not a substitute for these controls. Gate removal must not duplicate page queries (3b fixed that exact issue).

## Benchmark tooling and baselines found

No benchmark was executed here. Original artifacts are read-only references; future runs use new owned resources and copied tooling. Workspace tooling paths below identify earlier runs, not task allocations.

| Existing evidence | What to reuse | Limits / required adaptation |
| --- | --- | --- |
| `docs/phoenix/benchmark-20261007.md:7,18,48`; workspace `benchmarks/rails-phoenix-20261007` | `setup.py`, `run.py`, `cleanup.py`, cgroup sampling, preflight and frozen provenance, Go loadgen, plots | Closed-loop three API routes, Elixir 1.18.3, points-only dataset; historical OOM evidence, not final frontend control |
| `docs/phoenix/benchmark-20261008.md:1`; same-image timezone intervention | API/DB hotspot diagnosis and effect of pool/timezone scans | Changed fixture/fixes; never attribute this gain to frontend removal |
| `docs/phoenix/benchmark-k6-20261008.md:11,13,15,17,128,145`; workspace `benchmarks/rails-phoenix-fixed-20261008` | `cases.json`, `/Users/frey/projects/dawarich/benchmarks/rails-phoenix-fixed-20261008/bench.js:10` constant-arrival-rate, `/Users/frey/projects/dawarich/benchmarks/rails-phoenix-fixed-20261008/matrix-k6.py:18` cgroup/OOM/goodput, `/Users/frey/projects/dawarich/benchmarks/rails-phoenix-fixed-20261008/run.py:33` resource sampling, `summarize-k6.py`, `make-report-k6.py`, `plot-k6.py`, `preflight.json`, control scripts | Two reps; five-second warmup; 20-second lower and 15-second higher trials; 32 VUs; HTML checks use old DOM markers. Docker helper uses implicit context (`/Users/frey/projects/dawarich/benchmarks/rails-phoenix-fixed-20261008/run.py:5,23`), hard-coded names and bulk stops (`/Users/frey/projects/dawarich/benchmarks/rails-phoenix-fixed-20261008/matrix-k6.py:53`): MUST adapt to explicit local context, ownership labels, supplied resource names and bounded cleanup |
| `docs/phoenix/native-frontend-inventory.md:266,285`; `docs/phoenix/native-m3a-inventory.md:5,29`; `docs/phoenix/native-m3b-inventory.md:5` | query counters, decoded/wire JS measures, exact SHAs and browser oracle method | Tags 5/5 list queries, forms 4/4 and 5/5; settings sparse baseline 4/4, 9/6, 6/5, 4/4; 3b admission-inclusive caps documented in verified plan, not raw earlier caps |
| `E/tags/assets-budget.spec.js:5,18`; `E/settings/assets-budget.spec.js`; `E/v2/map/performance.spec.js:6,21` | response-body JS measurement and existing MapLibre ready/data-ready waits | Existing map gate is a 15-second readiness check; it does not measure WebGL memory or connection capacity. Response listeners must be removed/drained and account for dynamic modules/worker requests |
| `app-phoenix/scripts/parity/map_shell_lifecycle.spec.js`; `spec/javascript/realtime_connection_lifecycle_test.mjs`; map realtime refresh tests | disposal/reconnect and coalescing scenarios as behavior inputs | Hybrid harness must be replaced at 6; unit counters alone do not prove real map/GPU cleanup |

### Established ten-route workload

Copy exact paths and dataset from historical `cases.json`; normalize authentication privately, not into result logs.

| Scenario | Route shape | Old lower/higher arrivals per second |
| --- | --- | ---: |
| map | `/map?start_at=2026-01-01&end_at=2026-01-02` | 10 / 100 |
| stats_page | `/stats` | 10 / 100 |
| trips | `/trips` | 10 / 100 |
| imports | `/imports` | 10 / 100 |
| points_page | `/points?start_at=2026-01-01&end_at=2026-01-02` | 10 / 100 |
| points_api | `/api/v1/points` with interval and `per_page=100` | 50 / 300 |
| tracks_api | `/api/v1/tracks` with interval and `per_page=100` | 5 / 100 |
| stats_api | `/api/v1/stats` | 20 / 200 |
| visits_api | `/api/v1/visits` with interval and `per_page=100` | 20 / 200 |
| points_tile | `/api/v1/tiles/points/10/550/335.mvt` with interval | 2 / 8 |

Historical fixture: 100,000 synthetic points, 40 simple tracks, 40 visits, 20 trips/imports and one monthly stat (`docs/phoenix/benchmark-k6-20261008.md:13`). It is not a real-user or complex-geometry population. Matched app caps 512 MiB/1 GiB, 2 CPU, no swap; separate DB 2 CPU/1 GiB, Redis 128 MiB, web pool 10 (`:11`). These are application limits, not total deployment limits. Historical small API p95 at 512 MiB was 43.2 ms Rails/21.7 ms Phoenix, yet offered 300 RPS delivered 98.8/82.2 with drops (`:33`). This is why final gates report successful goodput and dropped work rather than claiming universal speedup.

### Fresh comparison and LiveView socket additions required at 8

Freeze Rails control revision/config and a pre-removal hybrid Phoenix revision that can build on current Elixir 1.20.4/OTP 27, plus final candidate. Same CPU, app/DB/pool/job settings, dataset, warmed caches and runtime for both Phoenix variants. Keep historical numbers labeled historical. Baseline capture should occur before 7 deletes the build/bridge, even if 4–6 outcomes later require additional feature-specific controls.

Use the established arrival rates as historical profiles, recalibrate bounded passing workloads on both implementations, and retain overload rows as exploratory. Recommended fresh protocol: 30-second warmup, 60-second measured phases, at least three alternating repetitions; keep generator limits and VU exhaustion visible. Controller approves absolute SLOs and concurrency before gate execution. The [k6 executor](https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/constant-arrival-rate/) schedules iteration starts independently of response time; `dropped_iterations` is never hidden by completed-response latency.

HTTP cannot measure connected LiveView state. Add bounded socket cohorts and separately a real-browser oracle using the actual LiveSocket client. Raw [k6 WebSockets](https://grafana.com/docs/k6/latest/javascript-api/k6-websockets/) provide transport, not LiveView semantics: implement and verify signed static DOM join/session/CSRF, serializer refs, `phx_join` acknowledgement, heartbeat, event reply/diff validation, leave/rejoin, patch and reconnect against the pinned client. If that adapter cannot validate real diffs, use browser-backed LiveSocket cohorts at a controller-approved smaller ceiling; never count a successful upgrade as a mounted user.

Required socket scenarios: idle Tags/settings and populated points/stats views; filter/patch/back-forward; form validation/write; upload/progress reconnect; authorized notification/family/shared-map updates; expired/revoked session/share/consent; stale async responses and per-run timeout; map/studio enter/leave/reconnect/cancel. Use synthetic credentials and data; no state/env/Repo config dumps. Event mixes and UI names are finalized from 4–6's delivered contracts.

Required metrics: goodput/latency p50/p95/p99/errors/drops/timeouts; app process RSS and cgroup current/peak/working set/OOM/CPU; BEAM total/process/binary/ETS memory/process count/GC/message queues; DB CPU/pool queue/query time and per-static/connected-mount/params/event query counts; browser decoded and compressed JS bytes including lazy chunks/workers; ready-to-interact time/parse work; map/studio renderer RSS/heap, active MapLibre instances, canvases/WebGL contexts, workers/listeners/timers and repeated-navigation memory trend. No portable precise GPU-byte counter is promised: report instrumented lifecycle counts, renderer RSS and available browser memory APIs, with unsupported metrics explicit. Never label cgroup working set as RSS.

## Open decisions (controller)

| Decision | Recommended default | Reason |
| --- | --- | --- |
| HTML suffix / `format=html` compatibility | Keep documented/current page aliases as full native documents; isolate small HTML normalization without gate/frame replay | Preserves URLs; `T/dawarich_web/page_envelopes_test.exs:65,87` covers user-visible contract |
| Legacy frame endpoints / Turbo-only accepts | Retire after last feature consumer; no new Turbo shim. Preserve JSON/HTTP external paths; reject obsolete formats locally with explicit EDs | ADR-0017; do not accidentally discard API or malformed-input guards |
| Physical feature grouping / namespace changes | Feature directories, module names retained in 7; no broad namespace churn | Discoverability with smaller diffs and safer embed-template/test moves |
| ActionCable external clients | Retain proven independent channel/wire adapters; audit consumers before removing orphan UI Turbo paths | Source plan explicitly preserves external wire contracts; frontend removal is not wire migration approval |
| Fallback and packaging | Whole-app Rails deployment artifact only; native request routes never proxy. Guard-related packaging changes need separate explicit brief | Prevents reintroducing coexistence and preserves Cloud admission boundaries |
| Performance comparator | Rails + fresh 1.20.4 hybrid Phoenix control + final native; historical reports contextual only | Separates runtime/DB fixes from frontend gain |
| SLOs / socket cohorts / trials | Proposed 30 s warmup, 60 s trial, ≥3 repeats; start at 1/10/50 idle sockets, raise only inside capped resources after calibration | No baseline supports an invented product SLO or large socket ceiling; controller schedules shared-host load |
| Browser/map memory budget | Compare repeated-navigation plateau/slope and lifecycle counts to fresh control; fixed absolute budget decided after baseline | Existing browser gate measures readiness, not memory |

## Risks and implementation estimate

Shared CSS/asset URLs and renderer payload are the largest cleanup risk; routing refusal gates mix real authorization and compatibility; rarely compiled test helpers can break a partition. Treat deletion as a caller/behavior audit, never a grep replacement. Unknown external socket consumers and 4–6 hook/event shapes remain explicit integration inputs.

Suggested implementation tracks: A frontend/assets 20–30 implementer-agent hours; B routes/envelopes/physical moves 26–40 hours; C corpus/E2E/docs/final integration 22–34 hours; D performance harness/control/socket/resource analysis 28–44 hours. Total 96–148 hours after 3c–6 are verified, excluding new feature fixes discovered during acceptance and elapsed build/load runs. Gate integration is serial; tracks are a plan for future implementers, no agents were dispatched here.

## Results (planning)

Static source/inventory/template/AFFiNE review only. No new named tests, so RED/GREEN/mutation evidence is not applicable to this document change. The implementation plan requires that sequence for every new named test. No running services, no schema/Swagger changes and no production modifications. Runner prerequisite discovered: the controller-owned full-suite runner currently pins Elixir 1.18.3, while `app-phoenix/mix.exs:8` requires 1.20; the targeted runner uses 1.20.4. The controller must supply a corrected approved full-suite entrypoint before the planned FULL GATE; do not edit controller scripts or silently run an incompatible runtime. All source citations refer to the frozen snapshot above; rebase requires refreshing the census and last-consumer attestations.

## Rails bugs fixed (changelog)

none

## Appendix A — source census, per-file removal ownership

Reproducible static scan: `rg -n` over `app-phoenix/lib`, `assets/js`, `priv/static/js`, `config`, excluding fixtures/dependencies/generated bundles. H = bridge/runtime/asset-flag or Cable Turbo caller; M = controller/action/Turbo markup or stream format; A = Rails asset resolution; R = envelope/ownership/coexistence. The line numbers identify every category in each file (first occurrence per category); use the file to audit all clauses. Shared routing cleanup is always 7 even where feature consumers migrate earlier. `7 audit` includes retained negative gates and mixed security/data contracts: it is NOT an automatic deletion list. Table coverage includes lexical false positives such as worker handover state; their business behavior remains. Feature rows with two milestones require both owners to attest removal.

| File / category evidence | Last consumer → shared retirement |
| --- | --- |
| R `D/application.ex:100` | 7 audit |
| H `D/build/frontend_inventory.ex:11`; M `D/build/frontend_inventory.ex:8` | 7 audit |
| A `D/build/importmap.ex:1` | 7 audit |
| A `D/build/sprockets/compiler.ex:1` | 7 audit |
| A `D/build/sprockets/directives.ex:1` | 7 audit |
| A `D/build/sprockets/env.ex:1` | 7 audit |
| A `D/build/sprockets/processors.ex:1` | 7 audit |
| A `D/build/sprockets/writer.ex:1` | 7 audit |
| H `D/cable/events_relay.ex:7` | 4 → 7 |
| H `D/cable/turbo_events.ex:1` | 4 → 7 |
| M `D/cable.ex:17` | 4 → 7 |
| H `D/cache/readers.ex:87` | 7 audit |
| R `D/imports/accepted_disposition.ex:31` | 4 → 7 |
| R `D/imports/destroy_handover.ex:64` | 4 → 7 |
| R `D/imports/gpx_handover.ex:54` | 4 → 7 |
| R `D/imports/normal_handover.ex:71` | 4 → 7 |
| R `D/imports/prepare_download_worker.ex:40` | 4 → 7 |
| H `D/insights/details/digests.ex:140`; R `D/insights/details/digests.ex:10` | 5 → 7 |
| R `D/metrics.ex:35` | 7 audit |
| H `D/posters/progress_worker.ex:50` | 6 → 7 |
| H `D/rails_cache/json_order.ex:4` | 7 audit |
| H `D/rails_cache/snapshot.ex:14` | 7 audit |
| R `D/shared_api/photos.ex:10` | 7 audit |
| R `W/a10_routes.ex:26` | 7 audit |
| R `W/a8_form_decode.ex:4` | 7 audit |
| R `W/a8_gate.ex:27` | 7 audit |
| M `W/a8_request.ex:143` | 7 audit |
| R `W/a8_routes.ex:19` | 7 audit |
| R `W/a9_routes.ex:21` | 7 audit |
| M `W/achievement_actions/gate.ex:8`; R `W/achievement_actions/gate.ex:55` | 5 → 7 |
| R `W/achievement_actions/request.ex:5` | 5 → 7 |
| M `W/achievement_actions/response.ex:60`; R `W/achievement_actions/response.ex:59` | 5 → 7 |
| M `W/achievement_card.ex:69`; A `W/achievement_card.ex:156` | 5 → 7 |
| M `W/achievement_children.ex:60` | 5 → 7 |
| M `W/achievement_detail.ex:49` | 5 → 7 |
| R `W/achievement_image_routes.ex:16` | 5 → 7 |
| M `W/achievement_modal.ex:12` | 5 → 7 |
| A `W/achievement_public/document.html.heex:11` | 5 → 7 |
| M `W/achievement_public.ex:10`; R `W/achievement_public.ex:7` | 5 → 7 |
| M `W/achievement_public_html.ex:35`; A `W/achievement_public_html.ex:34` | 5 → 7 |
| R `W/achievement_routes.ex:29` | 5 → 7 |
| M `W/achievement_sharing_controls.ex:14` | 4 → 7 |
| M `W/achievement_unlock_reveal.ex:29` | 5 → 7 |
| H `W/achievements_live.ex:88`; M `W/achievements_live.ex:90` | 5 → 7 |
| M `W/admin_gate.ex:29`; R `W/admin_gate.ex:5` | 7 audit |
| R `W/admin_writes/fallback.ex:4` | 4 → 7 |
| R `W/admin_writes/request.ex:5` | 4 → 7 |
| M `W/admin_writes_gate.ex:29`; R `W/admin_writes_gate.ex:4` | 4 → 7 |
| R `W/api/auth.ex:9` | 7 audit |
| R `W/api/body.ex:9` | 7 audit |
| R `W/api/method_override.ex:13` | 7 audit |
| R `W/api/multipart_replay.ex:42` | 7 audit |
| R `W/api/request_format.ex:33` | 7 audit |
| R `W/api/shared_controller.ex:84` | 7 audit |
| R `W/api/transport.ex:12` | 7 audit |
| R `W/api_routes.ex:36` | 7 audit |
| H `W/area_actions.ex:65`; M `W/area_actions.ex:68` | 6 → 7 |
| M `W/area_request.ex:31` | 6 → 7 |
| H `W/assets.ex:18`; A `W/assets.ex:34` | 7 audit |
| M `W/auth_account/http.ex:165`; R `W/auth_account/http.ex:7` | 3c → 7 |
| M `W/auth_account_link/form/challenge.html.heex:21` | 3c → 7 |
| M `W/auth_account_link/http.ex:194`; R `W/auth_account_link/http.ex:8` | 3c → 7 |
| R `W/auth_api/http.ex:8` | 7 audit |
| M `W/auth_form.ex:26` | 3c → 7 |
| R `W/auth_gate.ex:45` | 7 audit |
| M `W/auth_handler.ex:247`; R `W/auth_handler.ex:9` | 3c → 7 |
| M `W/auth_otp/form/challenge.html.heex:14` | 3c → 7 |
| M `W/auth_otp/http.ex:231`; R `W/auth_otp/http.ex:8` | 3c → 7 |
| M `W/auth_recovery/form.ex:65` | 3c → 7 |
| R `W/auth_recovery/http.ex:7` | 3c → 7 |
| M `W/auth_registration/form/new.html.heex:24` | 3c → 7 |
| M `W/auth_two_factor/form/show.html.heex:45` | 3c → 7 |
| M `W/auth_two_factor/form/verify.html.heex:57` | 3c → 7 |
| M `W/auth_two_factor/http.ex:257`; R `W/auth_two_factor/http.ex:8` | 3c → 7 |
| R `W/cable.ex:11` | 4 → 7 |
| R `W/cable_proxy/frame.ex:1` | 7 audit |
| R `W/cable_proxy.ex:1` | 7 audit |
| H `W/cable_turbo.ex:1` | 4 → 7 |
| M `W/components/chartkick.ex:33` | 7 audit |
| H `W/components/chrome.ex:100`; M `W/components/chrome.ex:41` | 7 audit |
| M `W/components/digest_parts.ex:137` | 5 → 7 |
| M `W/components/export_row.ex:70` | 4 → 7 |
| M `W/components/family_controls.ex:9` | 4 / 6 → 7 |
| M `W/components/family_forms.ex:101` | 4 / 6 → 7 |
| M `W/components/family_invitations.ex:44` | 4 / 6 → 7 |
| M `W/components/family_members.ex:93` | 4 / 6 → 7 |
| M `W/components/head.ex:70`; A `W/components/head.ex:24` | 7 audit |
| H `W/components/heatmap_parts.ex:29`; M `W/components/heatmap_parts.ex:32` | 6 → 7 |
| M `W/components/import_row.ex:160` | 4 → 7 |
| H `W/components/imports_extraction_card.ex:63`; M `W/components/imports_extraction_card.ex:59` | 4 → 7 |
| M `W/components/imports_extraction_dialog.ex:41` | 4 → 7 |
| M `W/components/map_button_cluster.ex:16` | 6 → 7 |
| M `W/components/map_controls.ex:43` | 6 → 7 |
| M `W/components/map_gallery_cards.ex:66` | 6 → 7 |
| M `W/components/map_index.ex:33` | 6 → 7 |
| M `W/components/map_layers_places.ex:19` | 3d / 6 → 7 |
| M `W/components/map_layers_tab.ex:27` | 6 → 7 |
| M `W/components/map_modals.ex:13` | 6 → 7 |
| M `W/components/map_panel.ex:53` | 6 → 7 |
| M `W/components/map_parts.ex:53` | 6 → 7 |
| M `W/components/map_place_modal.ex:13` | 3d / 6 → 7 |
| M `W/components/map_replay.ex:19` | 6 → 7 |
| M `W/components/map_settings_appearance.ex:41`; A `W/components/map_settings_appearance.ex:69` | 6 → 7 |
| M `W/components/map_settings_more.ex:63` | 6 → 7 |
| M `W/components/map_settings_sections.ex:71` | 6 → 7 |
| M `W/components/map_timeline_tab.ex:21` | 6 → 7 |
| M `W/components/map_tools_tab.ex:20` | 6 → 7 |
| A `W/components/navbar.ex:97` | 7 audit |
| M `W/components/navbar_end.ex:75` | 7 audit |
| M `W/components/navbar_parts.ex:59` | 7 audit |
| M `W/components/nearby_places.ex:22` | 3d / 6 → 7 |
| H `W/components/onboarding_modal.ex:34`; M `W/components/onboarding_modal.ex:36` | 6 → 7 |
| M `W/components/onboarding_screens.ex:29`; A `W/components/onboarding_screens.ex:141` | 6 → 7 |
| M `W/components/place_drawer_frame.ex:16` | 3d / 6 → 7 |
| M `W/components/place_streams.ex:37` | 3d / 6 → 7 |
| M `W/components/point_address_frame.ex:13` | 6 → 7 |
| M `W/components/point_list_controls.ex:25` | 5 → 7 |
| H `W/components/point_list_table.ex:29`; M `W/components/point_list_table.ex:28` | 5 → 7 |
| M `W/components/poster_studio.ex:25`; A `W/components/poster_studio.ex:153` | 6 → 7 |
| M `W/components/poster_studio_actions.ex:29` | 6 → 7 |
| M `W/components/poster_studio_sections.ex:53`; A `W/components/poster_studio_sections.ex:72` | 6 → 7 |
| H `W/components/public_month.ex:79`; M `W/components/public_month.ex:82` | 7 audit |
| M `W/components/residency_frame.ex:70` | 6 → 7 |
| M `W/components/route_video_card.ex:47` | 6 → 7 |
| M `W/components/route_video_streams.ex:23` | 6 → 7 |
| M `W/components/segment_frame.ex:19` | 6 → 7 |
| M `W/components/segment_legs.ex:54` | 6 → 7 |
| M `W/components/segment_row.ex:18` | 6 → 7 |
| H `W/components/settings_parts.ex:20`; M `W/components/settings_parts.ex:22` | 7 audit |
| M `W/components/share_hub/body.html.heex:2` | 4 → 7 |
| H `W/components/share_hub/frame.html.heex:1`; M `W/components/share_hub/frame.html.heex:1` | 4 → 7 |
| M `W/components/share_hub/shared_list.html.heex:21` | 4 → 7 |
| M `W/components/share_link_active/active.html.heex:29` | 4 → 7 |
| M `W/components/share_link_active.ex:30` | 4 → 7 |
| M `W/components/share_link_form/create_form.html.heex:2` | 4 → 7 |
| M `W/components/shared_resource_page/track.html.heex:5` | 7 audit |
| M `W/components/shared_resource_page/trip.html.heex:60` | 5 / 6 → 7 |
| M `W/components/shared_resource_page.ex:24` | 7 audit |
| H `W/components/sharing_parts.ex:30`; M `W/components/sharing_parts.ex:39` | 4 → 7 |
| M `W/components/stats_cards.ex:14` | 5 → 7 |
| H `W/components/stats_month.ex:70`; M `W/components/stats_month.ex:64` | 5 → 7 |
| M `W/components/timeline_calendar.ex:37` | 6 → 7 |
| M `W/components/timeline_entries.ex:55` | 6 → 7 |
| M `W/components/timeline_feed.ex:25` | 6 → 7 |
| M `W/components/timeline_journey.ex:61` | 6 → 7 |
| H `W/components/trip_card.ex:28`; M `W/components/trip_card.ex:25` | 5 / 6 → 7 |
| M `W/components/trip_days_list.ex:21` | 5 / 6 → 7 |
| M `W/components/trip_form.ex:54` | 5 / 6 → 7 |
| M `W/components/trip_itinerary_day.ex:53` | 5 / 6 → 7 |
| M `W/components/trip_map_panel.ex:28` | 6 → 7 |
| M `W/components/trip_note_form.ex:60` | 5 / 6 → 7 |
| M `W/components/trip_parts.ex:35` | 5 / 6 → 7 |
| M `W/components/trip_recalculate_stream.ex:14` | 5 / 6 → 7 |
| M `W/components/video_studio.ex:32` | 6 → 7 |
| M `W/components/video_studio_more.ex:29` | 6 → 7 |
| M `W/components/video_studio_sections.ex:51`; A `W/components/video_studio_sections.ex:179` | 6 → 7 |
| M `W/components/visit_streams.ex:143` | 5 → 7 |
| M `W/components/year_cards.ex:38` | 5 → 7 |
| M `W/digest_sharing.ex:56` | 4 → 7 |
| M `W/digests_live/index.ex:41` | 5 → 7 |
| H `W/digests_live/show.ex:9` | 5 → 7 |
| H `W/endpoint.ex:38`; R `W/endpoint.ex:45` | 7 audit |
| H `W/families_live/form.ex:38`; M `W/families_live/form.ex:62` | 4 / 6 → 7 |
| H `W/families_live/invitations.ex:12`; M `W/families_live/invitations.ex:26` | 4 / 6 → 7 |
| H `W/families_live/location_request.ex:12`; M `W/families_live/location_request.ex:26` | 4 / 6 → 7 |
| H `W/families_live/show.ex:19`; M `W/families_live/show.ex:41` | 4 / 6 → 7 |
| H `W/family_actions.ex:223` | 4 / 6 → 7 |
| R `W/family_gate.ex:141` | 4 / 6 → 7 |
| H `W/family_invitation_page.ex:121`; R `W/family_invitation_page.ex:103` | 4 / 6 → 7 |
| R `W/family_request_admission.ex:5` | 4 / 6 → 7 |
| M `W/family_sharing_actions.ex:49` | 4 / 6 → 7 |
| R `W/health_routes.ex:16` | 7 audit |
| R `W/home_dispatch.ex:3` | 7 audit |
| M `W/home_gate.ex:33`; R `W/home_gate.ex:4` | 7 audit |
| M `W/imports_controller.ex:127` | 4 → 7 |
| M `W/imports_download.ex:74`; R `W/imports_download.ex:93` | 4 → 7 |
| M `W/imports_extraction_stream.ex:12` | 4 → 7 |
| M `W/imports_live/index.ex:124` | 4 → 7 |
| H `W/imports_live/new.ex:107`; M `W/imports_live/new.ex:109` | 4 → 7 |
| M `W/imports_live/show.ex:134` | 4 → 7 |
| M `W/imports_request.ex:124`; R `W/imports_request.ex:8` | 4 → 7 |
| M `W/insights_details/body.ex:36` | 5 → 7 |
| M `W/insights_frame.ex:8` | 5 → 7 |
| R `W/insights_gate.ex:4` | 5 → 7 |
| H `W/insights_live/details.ex:23` | 5 → 7 |
| H `W/insights_live/index.ex:24`; M `W/insights_live/index.ex:104` | 5 → 7 |
| M `W/insights_visit.ex:8`; R `W/insights_visit.ex:13` | 5 → 7 |
| R `W/integration_form_routes.ex:18` | 4 → 7 |
| H `W/layouts/map.html.heex:22`; M `W/layouts/map.html.heex:24` | 7 audit |
| M `W/layouts/map_root.html.heex:28`; A `W/layouts/map_root.html.heex:19` | 7 audit |
| A `W/layouts/native_root.html.heex:14` | 7 audit |
| H `W/layouts/root.html.heex:45`; M `W/layouts/root.html.heex:41`; A `W/layouts/root.html.heex:19` | 7 audit |
| H `W/layouts.ex:22`; A `W/layouts.ex:23` | 7 audit |
| R `W/map_data_headers.ex:12` | 6 → 7 |
| R `W/map_frame_routes.ex:10` | 6 → 7 |
| M `W/map_frames.ex:138`; R `W/map_frames.ex:19` | 6 → 7 |
| M `W/map_frames_gate.ex:8`; R `W/map_frames_gate.ex:6` | 6 → 7 |
| H `W/map_live.ex:28` | 6 → 7 |
| M `W/map_point_request.ex:53`; R `W/map_point_request.ex:62` | 6 → 7 |
| M `W/map_segment_request.ex:35`; R `W/map_segment_request.ex:59` | 6 → 7 |
| R `W/map_write_gate.ex:5` | 6 → 7 |
| R `W/native_admin_routes.ex:37` | 7 audit |
| R `W/notification_form_routes.ex:9` | 4 → 7 |
| M `W/notifications_live/index.ex:63` | 4 → 7 |
| M `W/notifications_live/show.ex:69` | 4 → 7 |
| R `W/onboarding_routes.ex:10` | 6 → 7 |
| M `W/page_accept.ex:4` | 7 audit |
| M `W/page_envelope.ex:6`; R `W/page_envelope.ex:1` | 7 audit |
| R `W/page_routes.ex:15` | 7 audit |
| M `W/place_actions.ex:35` | 3d / 6 → 7 |
| M `W/place_navigation.ex:20` | 3d / 6 → 7 |
| M `W/places_gate.ex:19` | 3d / 6 → 7 |
| M `W/places_live/index.ex:102` | 3d / 6 → 7 |
| M `W/point_address.ex:20` | 6 → 7 |
| M `W/posters_controller.ex:94` | 6 → 7 |
| M `W/posters_gate.ex:132`; R `W/posters_gate.ex:93` | 6 → 7 |
| R `W/rails_pages_routes.ex:84` | 7 audit |
| R `W/rails_proxy/headers.ex:1` | 7 audit |
| R `W/rails_proxy/upstream.ex:1` | 7 audit |
| R `W/rails_proxy.ex:1` | 7 audit |
| R `W/rails_remote_ip.ex:8` | 7 audit |
| H `W/rails_widgets.ex:1` | 7 audit |
| R `W/rate_limit/request.ex:8` | 7 audit |
| R `W/rate_limit.ex:11` | 7 audit |
| R `W/require_user.ex:41` | 7 audit |
| M `W/route_video_actions.ex:58` | 6 → 7 |
| R `W/router.ex:31` | 7 audit |
| M `W/segment_write_response.ex:9` | 6 → 7 |
| H `W/settings_live/integrations.ex:233` | 7 audit |
| H `W/settings_misc_actions.ex:99`; M `W/settings_misc_actions.ex:38` | 4 → 7 |
| R `W/settings_misc_routes.ex:9` | 4 → 7 |
| H `W/share_management_document.ex:31`; M `W/share_management_document.ex:31` | 4 → 7 |
| M `W/share_management_form.ex:162`; R `W/share_management_form.ex:160` | 4 → 7 |
| M `W/share_management_gate.ex:14` | 4 → 7 |
| R `W/share_management_override_routes.ex:16` | 4 → 7 |
| H `W/share_management_page.ex:82`; M `W/share_management_page.ex:70`; R `W/share_management_page.ex:71` | 4 → 7 |
| M `W/share_management_streams.ex:25` | 4 → 7 |
| H `W/shared_link_page.ex:105` | 7 audit |
| M `W/shared_pages/document.html.heex:17`; A `W/shared_pages/document.html.heex:16` | 7 audit |
| M `W/shared_pages/live.html.heex:3` | 7 audit |
| A `W/shared_pages/metadata.html.heex:8` | 7 audit |
| M `W/shared_pages/timeline.html.heex:15` | 6 → 7 |
| A `W/shared_pages.ex:59` | 7 audit |
| H `W/shared_stats_page.ex:61`; A `W/shared_stats_page.ex:101`; R `W/shared_stats_page.ex:111` | 5 → 7 |
| R `W/sharing_gate.ex:7` | 4 → 7 |
| R `W/slices.ex:14` | 7 audit |
| R `W/standalone_error.ex:8` | 7 audit |
| H `W/stats_live/index.ex:9`; M `W/stats_live/index.ex:81` | 5 → 7 |
| H `W/stats_live/month.ex:8`; A `W/stats_live/month.ex:53` | 5 → 7 |
| H `W/stats_live/year.ex:9` | 5 → 7 |
| M `W/stats_sharing_request.ex:17` | 4 → 7 |
| R `W/storage_gate.ex:5` | 7 audit |
| R `W/storage_routes.ex:51` | 7 audit |
| M `W/strangler.ex:10`; R `W/strangler.ex:1` | 7 audit |
| M `W/timeline_share_actions.ex:22` | 6 → 7 |
| R `W/timeline_share_routes.ex:9` | 6 → 7 |
| M `W/track_recalculation_actions.ex:30` | 7 audit |
| M `W/track_share_actions.ex:24` | 7 audit |
| R `W/track_share_routes.ex:9` | 7 audit |
| M `W/trial_gate.ex:49`; R `W/trial_gate.ex:4` | 7 audit |
| R `W/trial_home_routes.ex:9` | 7 audit |
| H `W/trial_live/resume.ex:16`; M `W/trial_live/resume.ex:31` | 7 audit |
| R `W/trial_welcome.ex:5` | 7 audit |
| H `W/trip_actions.ex:151`; M `W/trip_actions.ex:49` | 5 / 6 → 7 |
| M `W/trip_note_actions.ex:33` | 5 / 6 → 7 |
| R `W/trip_request.ex:53` | 5 / 6 → 7 |
| R `W/trips_gate.ex:45` | 5 / 6 → 7 |
| H `W/trips_live/form.ex:23`; M `W/trips_live/form.ex:40` | 5 / 6 → 7 |
| H `W/trips_live/index.ex:18` | 5 / 6 → 7 |
| H `W/trips_live/show.ex:29`; M `W/trips_live/show.ex:45` | 5 / 6 → 7 |
| M `W/turbo_visit.ex:28`; R `W/turbo_visit.ex:1` | 7 audit |
| M `W/visit_actions.ex:46` | 5 → 7 |
| R `W/visit_request_gate.ex:3` | 5 → 7 |
| R `W/web_form_params.ex:6` | 7 audit |
| M `W/welcome_gate.ex:47`; R `W/welcome_gate.ex:5` | 7 audit |
| A `app-phoenix/lib/mix/tasks/dawarich.build_inputs.ex:6` | 7 audit |
| M `N/hooks/achievement_unlocks.js:40` | 5 → 7 |
| H `J/app.js:9`; M `J/app.js:32` | 5 → 7 |
| H `J/family_page.js:1` | 4 / 6 → 7 |
| H `J/hooks/video_studio.js:81` | 6 → 7 |
| M `J/hooks/video_studio_controls.js:124` | 6 → 7 |
| H `J/hooks/video_studio_save.js:28` | 6 → 7 |
| H `J/map_shell.js:2`; M `J/map_shell.js:54` | 7 audit |
| H `J/rails_bridge.js:7`; M `J/rails_bridge.js:29` | 7 audit |
| R `app-phoenix/config/runtime.exs:142` | 7 audit |

## Appendix B — all affected source tests and support readers

This is a reader/retarget checklist, not a claim all listed tests assert only markup. Negative Hotwire gates stay; effects/authorization/API/crypto/query tests stay. Closure/register/lifecycle tests remain behavior gates. Before implementation each owner records exact old `file:test name` → successor mapping for its changed cases; the main table supplies the known mechanism-only cases. Support modules referenced across partitions belong under test/support, not inside one test file.

| Test or helper / category evidence | Retarget owner |
| --- | --- |
| H `T/client/a12f3a_m_test.mjs:6` | 7 audit |
| M `T/client/a12f3a_r_test.mjs:399` | 7 audit |
| H `T/client/account_menu_patch_test.mjs:14` | 7 audit |
| H `T/client/retained_turbo_actions_test.mjs:32`; M `T/client/retained_turbo_actions_test.mjs:74` | 7 audit |
| H `T/client/turbo_navigation_test.mjs:17`; M `T/client/turbo_navigation_test.mjs:37` | 7 audit |
| R `T/dawarich/a12f3b_e13_shared_purge_test.exs:31` | 7 audit |
| R `T/dawarich/a12f3b_e13_shared_variant_test.exs:28` | 7 audit |
| R `T/dawarich/a12f3b_h01_hot5_test.exs:57` | 7 audit |
| R `T/dawarich/a12f3b_h01_test.exs:12` | 7 audit |
| R `T/dawarich/a12f3b_h02_test.exs:199` | 7 audit |
| R `T/dawarich/a12f3b_m10_test.exs:63` | 7 audit |
| R `T/dawarich/after_commit_regression_test.exs:230` | 7 audit |
| M `T/dawarich/auth/http_boundary_test.exs:64`; R `T/dawarich/auth/http_boundary_test.exs:163` | 3c → 7 |
| R `T/dawarich/auth/recovery/http_test.exs:121` | 3c → 7 |
| A `T/dawarich/build/compare_build_inputs_test.exs:16` | 7 audit |
| A `T/dawarich/build/dockerfile_test.exs:4` | 7 audit |
| H `T/dawarich/build/frontend_inventory_test.exs:17`; M `T/dawarich/build/frontend_inventory_test.exs:17` | 7 audit |
| A `T/dawarich/build/importmap_test.exs:1` | 7 audit |
| H `T/dawarich/build/native_assets_test.exs:31` | 7 audit |
| A `T/dawarich/build/rails_parity_test.exs:40` | 7 audit |
| A `T/dawarich/build/served_asset_check_test.exs:58` | 7 audit |
| A `T/dawarich/build/sprockets/compiler_test.exs:1` | 7 audit |
| A `T/dawarich/build/sprockets/directives_test.exs:1` | 7 audit |
| A `T/dawarich/build/sprockets/env_test.exs:1` | 7 audit |
| A `T/dawarich/build/sprockets/processors_test.exs:1` | 7 audit |
| A `T/dawarich/build/sprockets/writer_test.exs:1` | 7 audit |
| H `T/dawarich/cable/pg_turbo_events_test.exs:1` | 4 → 7 |
| H `T/dawarich/cable/turbo_events_test.exs:1` | 4 → 7 |
| H `T/dawarich/cable_pg_test.exs:88`; M `T/dawarich/cable_pg_test.exs:78` | 4 → 7 |
| H `T/dawarich/cable_test.exs:24`; M `T/dawarich/cable_test.exs:25` | 4 → 7 |
| R `T/dawarich/exports/purge_ownership_test.exs:42` | 7 audit |
| R `T/dawarich/front_test.exs:7` | 7 audit |
| R `T/dawarich/imports/continuation_order_test.exs:13` | 4 → 7 |
| R `T/dawarich/imports/continuation_review_test.exs:130` | 4 → 7 |
| R `T/dawarich/imports/destroy_worker_test.exs:369` | 4 → 7 |
| R `T/dawarich/imports/gpx_fence_test.exs:36` | 4 → 7 |
| R `T/dawarich/imports/normal_lifecycle_test.exs:53` | 4 → 7 |
| R `T/dawarich/imports/normal_upload_test.exs:155` | 4 → 7 |
| R `T/dawarich/imports/process_gpx_worker_test.exs:90` | 4 → 7 |
| R `T/dawarich/insights_details_db_test.exs:152` | 5 → 7 |
| R `T/dawarich/jobs/release_adapters_test.exs:91` | 7 audit |
| R `T/dawarich/lite/archival_warning_worker_test.exs:183` | 7 audit |
| R `T/dawarich/mail/test_email_test.exs:87` | 7 audit |
| R `T/dawarich/maintenance_workers_test.exs:46` | 7 audit |
| R `T/dawarich/native_regression_transition_test.exs:16` | 7 audit |
| R `T/dawarich/observability_retirement_test.exs:20` | 7 audit |
| R `T/dawarich/points/anomaly_filter_effects_test.exs:147` | 7 audit |
| R `T/dawarich/rails_job_owners_test.exs:7` | 7 audit |
| A `T/dawarich/rails_root_test.exs:14` | 7 audit |
| R `T/dawarich/runtime_config_test.exs:89` | 7 audit |
| R `T/dawarich/standalone/switchover_test.exs:348` | 7 audit |
| A `T/dawarich/standalone_test.exs:191`; R `T/dawarich/standalone_test.exs:56` | 7 audit |
| R `T/dawarich/users/recalculation_corpus_test.exs:72` | 7 audit |
| R `T/dawarich/users/standalone_deletion_test.exs:264` | 7 audit |
| R `T/dawarich/visits/concurrent_suggestions_test.exs:90` | 5 → 7 |
| M `T/dawarich_web/a10b_ownership_test.exs:176`; R `T/dawarich_web/a10b_ownership_test.exs:25` | 7 audit |
| R `T/dawarich_web/a10c_ownership_test.exs:14` | 7 audit |
| R `T/dawarich_web/a10c_routes_test.exs:6` | 7 audit |
| R `T/dawarich_web/a12f2_e_closure_test.exs:730` | 7 audit |
| R `T/dawarich_web/a12f2_j_closure_test.exs:223` | 7 audit |
| R `T/dawarich_web/a12f3a_i_closure_test.exs:13` | 7 audit |
| M `T/dawarich_web/a12f3a_o_closure_test.exs:86`; R `T/dawarich_web/a12f3a_o_closure_test.exs:234` | 7 audit |
| M `T/dawarich_web/a12f3a_p_closure_test.exs:70` | 7 audit |
| M `T/dawarich_web/a12f3a_q_closure_test.exs:205` | 7 audit |
| M `T/dawarich_web/a12f3a_r_closure_test.exs:185` | 7 audit |
| M `T/dawarich_web/a12f3a_t_closure_test.exs:177` | 7 audit |
| M `T/dawarich_web/a12f3a_v_closure_test.exs:390` | 7 audit |
| M `T/dawarich_web/a12f3a_w_closure_test.exs:36`; R `T/dawarich_web/a12f3a_w_closure_test.exs:32` | 7 audit |
| R `T/dawarich_web/a12f3b_d05_test.exs:173` | 7 audit |
| R `T/dawarich_web/a12f3b_f03_test.exs:60` | 7 audit |
| M `T/dawarich_web/a12f3b_f06_test.exs:68`; R `T/dawarich_web/a12f3b_f06_test.exs:94` | 7 audit |
| H `T/dawarich_web/a12f3b_n02_test.exs:6` | 7 audit |
| M `T/dawarich_web/a12f3b_n05_test.exs:34` | 7 audit |
| M `T/dawarich_web/a12f3b_p01_test.exs:25` | 7 audit |
| M `T/dawarich_web/a12f3b_review_test.exs:148`; R `T/dawarich_web/a12f3b_review_test.exs:12` | 7 audit |
| R `T/dawarich_web/a12f3b_s02_test.exs:479` | 7 audit |
| R `T/dawarich_web/a12f3b_s04_test.exs:9` | 7 audit |
| M `T/dawarich_web/a12f3b_s07_test.exs:43`; R `T/dawarich_web/a12f3b_s07_test.exs:11` | 7 audit |
| M `T/dawarich_web/a8_gate_endpoint_test.exs:61`; R `T/dawarich_web/a8_gate_endpoint_test.exs:11` | 7 audit |
| M `T/dawarich_web/a8_remaining_parity_test.exs:310`; R `T/dawarich_web/a8_remaining_parity_test.exs:147` | 7 audit |
| M `T/dawarich_web/a8_remaining_request_test.exs:52`; R `T/dawarich_web/a8_remaining_request_test.exs:10` | 7 audit |
| M `T/dawarich_web/a8_request_test.exs:36`; R `T/dawarich_web/a8_request_test.exs:15` | 7 audit |
| R `T/dawarich_web/a8_routes_test.exs:20` | 7 audit |
| M `T/dawarich_web/a8_videos_visits_parity_test.exs:419` | 6 → 7 |
| R `T/dawarich_web/a9_routes_test.exs:100` | 7 audit |
| R `T/dawarich_web/achievement_actions_request_test.exs:7` | 5 → 7 |
| R `T/dawarich_web/achievement_auth_refusal_test.exs:12` | 3c → 7 |
| R `T/dawarich_web/achievement_public_query_test.exs:13` | 5 → 7 |
| M `T/dawarich_web/achievement_public_test.exs:75`; A `T/dawarich_web/achievement_public_test.exs:14` | 5 → 7 |
| M `T/dawarich_web/achievement_unlock_reveal_test.exs:17` | 5 → 7 |
| R `T/dawarich_web/achievements_gate_endpoint_test.exs:16` | 7 audit |
| M `T/dawarich_web/achievements_live_test.exs:75` | 5 → 7 |
| M `T/dawarich_web/achievements_parity_test.exs:11` | 5 → 7 |
| M `T/dawarich_web/admin/experimental_section_test.exs:212` | 7 audit |
| M `T/dawarich_web/admin_writes_request_test.exs:156` | 4 → 7 |
| R `T/dawarich_web/api/body_test.exs:26` | 7 audit |
| R `T/dawarich_web/api/head_golden_review_test.exs:28` | 7 audit |
| R `T/dawarich_web/api/ingest_controller_test.exs:17` | 7 audit |
| R `T/dawarich_web/api/ingest_endpoint_test.exs:11` | 7 audit |
| R `T/dawarich_web/api/ingest_golden_test.exs:10` | 7 audit |
| R `T/dawarich_web/api/photo_provider_ownership_test.exs:36` | 7 audit |
| R `T/dawarich_web/api/plan_endpoint_test.exs:143` | 7 audit |
| R `T/dawarich_web/api/plan_golden_test.exs:20` | 7 audit |
| R `T/dawarich_web/api/remaining_routes_test.exs:169` | 7 audit |
| R `T/dawarich_web/api/two_factor_endpoint_test.exs:252` | 7 audit |
| R `T/dawarich_web/api_docs_test.exs:9` | 7 audit |
| M `T/dawarich_web/area_writes_regression_test.exs:152` | 6 → 7 |
| H `T/dawarich_web/assets_test.exs:99`; M `T/dawarich_web/assets_test.exs:161`; A `T/dawarich_web/assets_test.exs:15` | 7 audit |
| M `T/dawarich_web/auth_account/http_test.exs:215` | 3c → 7 |
| M `T/dawarich_web/auth_account_link/form_test.exs:36` | 3c → 7 |
| M `T/dawarich_web/auth_account_link/http_test.exs:175` | 3c → 7 |
| R `T/dawarich_web/auth_api/http_test.exs:44` | 7 audit |
| R `T/dawarich_web/auth_gate_endpoint_test.exs:57` | 7 audit |
| R `T/dawarich_web/auth_gate_test.exs:305` | 7 audit |
| M `T/dawarich_web/auth_otp/form_test.exs:26` | 3c → 7 |
| M `T/dawarich_web/auth_otp/http_test.exs:134` | 3c → 7 |
| M `T/dawarich_web/auth_two_factor/form_test.exs:64` | 3c → 7 |
| M `T/dawarich_web/auth_two_factor/http_test.exs:276` | 3c → 7 |
| H `T/dawarich_web/cable_pg_test.exs:87` | 4 → 7 |
| R `T/dawarich_web/cable_proxy/frame_test.exs:1` | 7 audit |
| R `T/dawarich_web/cable_proxy_test.exs:1` | 7 audit |
| R `T/dawarich_web/cable_route_test.exs:12` | 4 → 7 |
| H `T/dawarich_web/digests_live_test.exs:125`; M `T/dawarich_web/digests_live_test.exs:71` | 5 → 7 |
| M `T/dawarich_web/endpoint_test.exs:288`; R `T/dawarich_web/endpoint_test.exs:13` | 7 audit |
| M `T/dawarich_web/exports_create_test.exs:25` | 4 → 7 |
| M `T/dawarich_web/exports_live_test.exs:119` | 4 → 7 |
| M `T/dawarich_web/family_browser_envelopes_test.exs:9` | 7 audit |
| M `T/dawarich_web/family_invitation_test.exs:177`; R `T/dawarich_web/family_invitation_test.exs:106` | 4 / 6 → 7 |
| M `T/dawarich_web/family_pages_parity_test.exs:70` | 4 / 6 → 7 |
| M `T/dawarich_web/family_pages_test.exs:68`; R `T/dawarich_web/family_pages_test.exs:162` | 4 / 6 → 7 |
| R `T/dawarich_web/family_session_handback_test.exs:17` | 4 / 6 → 7 |
| R `T/dawarich_web/health_endpoint_test.exs:12` | 7 audit |
| M `T/dawarich_web/home_gate_test.exs:34`; R `T/dawarich_web/home_gate_test.exs:11` | 7 audit |
| R `T/dawarich_web/host_authorization_test.exs:152` | 7 audit |
| M `T/dawarich_web/imports_browser_test.exs:48` | 4 → 7 |
| M `T/dawarich_web/imports_download_test.exs:153`; R `T/dawarich_web/imports_download_test.exs:180` | 4 → 7 |
| M `T/dawarich_web/imports_exports_parity_test.exs:41` | 4 → 7 |
| M `T/dawarich_web/imports_extraction_navigation_test.exs:25` | 4 → 7 |
| M `T/dawarich_web/imports_live_test.exs:90` | 4 → 7 |
| M `T/dawarich_web/imports_native_pages_test.exs:9` | 4 → 7 |
| M `T/dawarich_web/imports_pages_parity_test.exs:12` | 4 → 7 |
| R `T/dawarich_web/imports_remaining_pages_test.exs:141` | 4 → 7 |
| M `T/dawarich_web/imports_upload_test.exs:153` | 4 → 7 |
| H `T/dawarich_web/insights_details_parity_test.exs:60`; M `T/dawarich_web/insights_details_parity_test.exs:144`; R `T/dawarich_web/insights_details_parity_test.exs:19` | 5 → 7 |
| H `T/dawarich_web/insights_details_parts_test.exs:48` | 5 → 7 |
| M `T/dawarich_web/insights_endpoint_test.exs:75`; R `T/dawarich_web/insights_endpoint_test.exs:19` | 7 audit |
| M `T/dawarich_web/insights_frame_test.exs:11` | 5 → 7 |
| R `T/dawarich_web/insights_home_test.exs:17` | 5 → 7 |
| H `T/dawarich_web/insights_live_test.exs:55`; M `T/dawarich_web/insights_live_test.exs:55` | 5 → 7 |
| M `T/dawarich_web/layout_parity_test.exs:11` | 7 audit |
| R `T/dawarich_web/live_socket_test.exs:10` | 7 audit |
| M `T/dawarich_web/map_data_frames_test.exs:81` | 6 → 7 |
| M `T/dawarich_web/map_data_handback_test.exs:144`; R `T/dawarich_web/map_data_handback_test.exs:28` | 6 → 7 |
| H `T/dawarich_web/map_data_parity_test.exs:308`; M `T/dawarich_web/map_data_parity_test.exs:188` | 6 → 7 |
| R `T/dawarich_web/map_data_routes_test.exs:10` | 6 → 7 |
| R `T/dawarich_web/map_frames_endpoint_test.exs:15` | 7 audit |
| M `T/dawarich_web/map_frames_parity_test.exs:12` | 6 → 7 |
| M `T/dawarich_web/map_frames_test.exs:50` | 6 → 7 |
| H `T/dawarich_web/map_live_test.exs:58`; M `T/dawarich_web/map_live_test.exs:62`; A `T/dawarich_web/map_live_test.exs:76` | 6 → 7 |
| M `T/dawarich_web/map_stimulus_test.exs:7` | 6 → 7 |
| M `T/dawarich_web/map_write_request_test.exs:172`; R `T/dawarich_web/map_write_request_test.exs:17` | 6 → 7 |
| M `T/dawarich_web/map_write_routes_test.exs:47`; R `T/dawarich_web/map_write_routes_test.exs:7` | 6 → 7 |
| R `T/dawarich_web/map_writes_handback_test.exs:45` | 6 → 7 |
| H `T/dawarich_web/map_writes_parity_test.exs:451`; M `T/dawarich_web/map_writes_parity_test.exs:122` | 6 → 7 |
| M `T/dawarich_web/native_onboarding_test.exs:80` | 6 → 7 |
| H `T/dawarich_web/native_pages_hotwire_free_test.exs:17`; M `T/dawarich_web/native_pages_hotwire_free_test.exs:12` | 7 audit |
| M `T/dawarich_web/native_root_test.exs:35` | 7 audit |
| H `T/dawarich_web/native_settings_shell_test.exs:118`; M `T/dawarich_web/native_settings_shell_test.exs:117` | 7 audit |
| M `T/dawarich_web/native_shell_events_test.exs:62` | 7 audit |
| M `T/dawarich_web/native_shell_test.exs:95` | 7 audit |
| M `T/dawarich_web/notifications_live_test.exs:284` | 4 → 7 |
| H `T/dawarich_web/onboarding_modal_test.exs:12`; M `T/dawarich_web/onboarding_modal_test.exs:12` | 6 → 7 |
| R `T/dawarich_web/operator_connection_security_test.exs:23` | 7 audit |
| R `T/dawarich_web/operator_routes_test.exs:20` | 7 audit |
| M `T/dawarich_web/page_accept_test.exs:24` | 7 audit |
| M `T/dawarich_web/page_envelopes_test.exs:105`; R `T/dawarich_web/page_envelopes_test.exs:1` | 7 audit |
| R `T/dawarich_web/page_routes_test.exs:23` | 7 audit |
| M `T/dawarich_web/place_actions_test.exs:35` | 3d / 6 → 7 |
| M `T/dawarich_web/place_drawer_frame_test.exs:84` | 3d / 6 → 7 |
| M `T/dawarich_web/place_navigation_test.exs:21` | 3d / 6 → 7 |
| M `T/dawarich_web/places_gate_endpoint_test.exs:119`; R `T/dawarich_web/places_gate_endpoint_test.exs:18` | 7 audit |
| M `T/dawarich_web/places_live_test.exs:80` | 3d / 6 → 7 |
| M `T/dawarich_web/places_parity_test.exs:112` | 3d / 6 → 7 |
| R `T/dawarich_web/point_delete_tile_visibility_test.exs:31` | 7 audit |
| M `T/dawarich_web/point_list_actions_test.exs:29`; R `T/dawarich_web/point_list_actions_test.exs:14` | 5 → 7 |
| H `T/dawarich_web/points_live_test.exs:176`; M `T/dawarich_web/points_live_test.exs:175`; R `T/dawarich_web/points_live_test.exs:256` | 5 → 7 |
| M `T/dawarich_web/posters_endpoint_test.exs:39`; R `T/dawarich_web/posters_endpoint_test.exs:108` | 7 audit |
| M `T/dawarich_web/posters_parity_test.exs:70` | 6 → 7 |
| R `T/dawarich_web/public_files_test.exs:181` | 7 audit |
| R `T/dawarich_web/rails_proxy_test.exs:1` | 7 audit |
| R `T/dawarich_web/rate_limit_test.exs:274` | 7 audit |
| M `T/dawarich_web/route_video_actions_test.exs:111` | 6 → 7 |
| M `T/dawarich_web/route_video_parity_test.exs:61` | 6 → 7 |
| M `T/dawarich_web/segment_actions_test.exs:45`; R `T/dawarich_web/segment_actions_test.exs:25` | 6 → 7 |
| M `T/dawarich_web/segment_frame_test.exs:40` | 6 → 7 |
| M `T/dawarich_web/segment_write_response_test.exs:51` | 6 → 7 |
| M `T/dawarich_web/settings_consent_negotiation_test.exs:38` | 7 audit |
| M `T/dawarich_web/settings_parity_test.exs:13` | 7 audit |
| H `T/dawarich_web/settings_shared_test.exs:44`; M `T/dawarich_web/settings_shared_test.exs:44` | 7 audit |
| M `T/dawarich_web/share_management_endpoint_test.exs:38`; R `T/dawarich_web/share_management_endpoint_test.exs:111` | 7 audit |
| H `T/dawarich_web/share_management_page_test.exs:30`; M `T/dawarich_web/share_management_page_test.exs:30`; R `T/dawarich_web/share_management_page_test.exs:159` | 4 → 7 |
| M `T/dawarich_web/share_management_parity_test.exs:307` | 4 → 7 |
| H `T/dawarich_web/sharing_bridge_test.exs:14`; M `T/dawarich_web/sharing_bridge_test.exs:40` | 4 → 7 |
| R `T/dawarich_web/sharing_endpoint_test.exs:22` | 7 audit |
| R `T/dawarich_web/standalone_activation_test.exs:25` | 7 audit |
| R `T/dawarich_web/standalone_api_gaps_test.exs:187` | 7 audit |
| R `T/dawarich_web/standalone_auth_review_test.exs:25` | 3c → 7 |
| R `T/dawarich_web/standalone_credentials_otp_test.exs:24` | 7 audit |
| M `T/dawarich_web/standalone_demo_import_test.exs:37` | 6 → 7 |
| M `T/dawarich_web/standalone_html_pages_test.exs:80`; R `T/dawarich_web/standalone_html_pages_test.exs:43` | 7 audit |
| R `T/dawarich_web/standalone_map_test.exs:21` | 6 → 7 |
| M `T/dawarich_web/standalone_place_browser_test.exs:9` | 3d / 6 → 7 |
| M `T/dawarich_web/standalone_recalculation_test.exs:186`; R `T/dawarich_web/standalone_recalculation_test.exs:78` | 7 audit |
| H `T/dawarich_web/standalone_share_assets_test.exs:83`; M `T/dawarich_web/standalone_share_assets_test.exs:138`; A `T/dawarich_web/standalone_share_assets_test.exs:6`; R `T/dawarich_web/standalone_share_assets_test.exs:72` | 7 audit |
| M `T/dawarich_web/standalone_share_points_flow_test.exs:71` | 7 audit |
| H `T/dawarich_web/stats_live_test.exs:52`; M `T/dawarich_web/stats_live_test.exs:251`; A `T/dawarich_web/stats_live_test.exs:44` | 5 → 7 |
| R `T/dawarich_web/storage_routes_test.exs:139` | 7 audit |
| R `T/dawarich_web/strangler_test.exs:1` | 7 audit |
| H `T/dawarich_web/tags_live_test.exs:60`; M `T/dawarich_web/tags_live_test.exs:57` | 7 audit |
| M `T/dawarich_web/trial_resume_test.exs:43` | 7 audit |
| M `T/dawarich_web/trial_upgrade_test.exs:154` | 7 audit |
| M `T/dawarich_web/trial_welcome_test.exs:91`; R `T/dawarich_web/trial_welcome_test.exs:198` | 7 audit |
| M `T/dawarich_web/trip_form_navigation_test.exs:23` | 5 / 6 → 7 |
| M `T/dawarich_web/trip_forms_actions_test.exs:198` | 5 / 6 → 7 |
| M `T/dawarich_web/trip_note_actions_test.exs:125` | 5 / 6 → 7 |
| M `T/dawarich_web/trip_plan_hosts_test.exs:180`; R `T/dawarich_web/trip_plan_hosts_test.exs:234` | 5 / 6 → 7 |
| M `T/dawarich_web/trip_recalculate_test.exs:139` | 5 / 6 → 7 |
| M `T/dawarich_web/trip_shared_components_test.exs:12` | 5 / 6 → 7 |
| M `T/dawarich_web/trips_gate_endpoint_test.exs:154`; R `T/dawarich_web/trips_gate_endpoint_test.exs:17` | 7 audit |
| M `T/dawarich_web/trips_index_parity_test.exs:48` | 5 / 6 → 7 |
| H `T/dawarich_web/trips_live_test.exs:73`; M `T/dawarich_web/trips_live_test.exs:73` | 5 / 6 → 7 |
| M `T/dawarich_web/turbo_handback_test.exs:44`; R `T/dawarich_web/turbo_handback_test.exs:6` | 7 audit |
| M `T/dawarich_web/visit_actions_test.exs:82` | 5 → 7 |
| M `T/dawarich_web/visit_writes_regression_test.exs:964`; R `T/dawarich_web/visit_writes_regression_test.exs:62` | 5 → 7 |
| R `T/dawarich_web/web_form_params_test.exs:79` | 7 audit |
| H `T/mix/tasks/dawarich.build_inputs_test.exs:108`; A `T/mix/tasks/dawarich.build_inputs_test.exs:13` | 7 audit |
| H `T/support/a12a.ex:495`; R `T/support/a12a.ex:9` | 7 audit |
| M `T/support/a12f3b_share_case.ex:68` | 7 audit |
| R `T/support/api_endpoint_case.ex:58` | 7 audit |
| R `T/support/auth/emit_protocol.exs:173` | 7 audit |
| R `T/support/auth/http_stand.exs:39` | 7 audit |
| M `T/support/map_stimulus.ex:4` | 6 → 7 |
| M `T/support/parity_html.ex:5` | 7 audit |
| R `T/support/rails_form_requests.ex:13` | 7 audit |
| R `T/support/rails_job_owners.ex:154` | 7 audit |
| H `spec/javascript/family_subscription_ownership_test.mjs:13` | 7 audit |
| H `spec/javascript/phoenix_rails_bridge_stimulus_test.mjs:6` | 7 audit |
| M `spec/javascript/place_marker_edit_test.mjs:63` | 3d / 6 → 7 |
| H `spec/javascript/realtime_connection_lifecycle_test.mjs:42` | 6 → 7 |
| H `spec/javascript/realtime_live_refresh_coalescing_test.mjs:42` | 6 → 7 |
| H `spec/javascript/realtime_point_delivery_test.mjs:42` | 6 → 7 |
| H `spec/javascript/realtime_track_refresh_coalescing_test.mjs:42` | 6 → 7 |
| H `spec/javascript/timeline_frame_single_owner_test.mjs:15`; M `spec/javascript/timeline_frame_single_owner_test.mjs:174` | 6 → 7 |
| H `spec/javascript/timeline_track_click_camera_test.mjs:14` | 6 → 7 |

## Appendix C — dynamically available Rails controllers and transitive JS

All listed Rails files are retained for Rails. The owner column assigns removal of native reachability, not deletion of the Rails source. `7 audit` = shared helper or currently unproven consumer; prove orphan status from rendered attributes + import closure, never assume every importmap pin is fetched. Pure child modules and popup strings need closure inspection as well as controller entrypoints.

| Rails source evidence | Native consumer owner |
| --- | --- |
| `app/javascript/application.js:3` | 7 audit |
| `app/javascript/channels/consumer.js:4` | 7 audit |
| `app/javascript/controllers/achievement_card_controller.js:1` | 5 → 7 |
| `app/javascript/controllers/achievement_map_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/achievement_unlocks_controller.js:1` | 5 → 7 |
| `app/javascript/controllers/activity_heatmap_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/application.js:1` | 7 audit |
| `app/javascript/controllers/area_creation_v2_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/area_drawer_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/area_selector_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/base_controller.js:1` | 7 audit |
| `app/javascript/controllers/card_modal_controller.js:1` | 7 audit |
| `app/javascript/controllers/changelog_widget_controller.js:1` | 7 audit |
| `app/javascript/controllers/checkbox_select_all_controller.js:1` | 7 audit |
| `app/javascript/controllers/clipboard_controller.js:1` | 7 audit |
| `app/javascript/controllers/color_picker_controller.js:1` | 7 audit |
| `app/javascript/controllers/datetime_controller.js:5` | 7 audit |
| `app/javascript/controllers/demo_banner_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/dismissible_controller.js:1` | 7 audit |
| `app/javascript/controllers/emoji_picker_controller.js:1` | 7 audit |
| `app/javascript/controllers/family_map_controller.js:1` | 4 / 6 → 7 |
| `app/javascript/controllers/family_navbar_indicator_controller.js:1` | 7 audit |
| `app/javascript/controllers/flash_controller.js:1` | 7 audit |
| `app/javascript/controllers/hub_tabs_controller.js:1` | 7 audit |
| `app/javascript/controllers/import_extraction_controller.js:1` | 4 → 7 |
| `app/javascript/controllers/imports_controller.js:1` | 4 → 7 |
| `app/javascript/controllers/index.js:2` | 7 audit |
| `app/javascript/controllers/lazy_gallery_controller.js:1` | 7 audit |
| `app/javascript/controllers/location_sharing_toggle_controller.js:1` | 4 → 7 |
| `app/javascript/controllers/map_controls_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/map_matching_demo_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/map_panel_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/map_settings_dirty_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/map_theme_editor_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/map_v2_preview_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/maps/immich_enrich_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/maps/maplibre/event_handlers.js:216` | 6 → 7 |
| `app/javascript/controllers/maps/maplibre/visits_manager.js:387` | 6 → 7 |
| `app/javascript/controllers/maps/maplibre_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/maps/maplibre_realtime_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/notifications_controller.js:6` | 4 → 7 |
| `app/javascript/controllers/onboarding_modal_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/place_creation_controller.js:1` | 3d / 6 → 7 |
| `app/javascript/controllers/place_detail_controller.js:1` | 3d / 6 → 7 |
| `app/javascript/controllers/places_filter_controller.js:1` | 3d / 6 → 7 |
| `app/javascript/controllers/poster_studio_editor_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/poster_theme_picker_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/privacy_radius_controller.js:1` | 7 audit |
| `app/javascript/controllers/public_stat_map_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/range_display_controller.js:1` | 7 audit |
| `app/javascript/controllers/removals_controller.js:1` | 7 audit |
| `app/javascript/controllers/scroll_into_view_controller.js:1` | 7 audit |
| `app/javascript/controllers/segment_mode_editor_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/share_link_modal_controller.js:1` | 4 → 7 |
| `app/javascript/controllers/shared_live_map_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/shared_trip_map_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/sharing_modal_controller.js:1` | 4 → 7 |
| `app/javascript/controllers/speed_color_editor_controller.js:1` | 7 audit |
| `app/javascript/controllers/stat_page_controller.js:1` | 5 → 7 |
| `app/javascript/controllers/studio_launcher_controller.js:1` | 7 audit |
| `app/javascript/controllers/timeline_feed_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/trip_map_controller.js:4` | 6 → 7 |
| `app/javascript/controllers/trip_maplibre_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/trip_maplibre_preview_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/trip_plan_focus_controller.js:1` | 5 / 6 → 7 |
| `app/javascript/controllers/upload_controller.js:1` | 7 audit |
| `app/javascript/controllers/video_studio_controller.js:1` | 6 → 7 |
| `app/javascript/controllers/visit_creation_v2_controller.js:1` | 5 → 7 |
| `app/javascript/controllers/visit_editor_controller.js:18` | 5 → 7 |
| `app/javascript/controllers/visit_modal_places_controller.js:1` | 3d / 6 → 7 |
| `app/javascript/controllers/visit_place_search_controller.js:1` | 3d / 6 → 7 |
| `app/javascript/poster_studio/data/providers.js:15` | 6 → 7 |
| `app/javascript/video_studio/save_video.js:1` | 6 → 7 |

## Census totals and coverage limits

285 native source/config/client files and 254 source test/support files match the declared categories; 73 Rails controller/transitive JS entries are listed. Counts include detectors/negative assertions, retained protocols and mixed behavior tests. Third-party vendored files are accounted for by importmap/build closure rather than dumping minified source. Runtime fetch/emitted-bundle proof is a milestone 7/8 gate, not a static-search claim.

## Appendix D — A0 execution handoff and positive asset ledger

Prepared 2026-10-10 against the inventory base `bdaa9aa36` plus D0. This is a preparation snapshot, not S1 approval. No production browser or route was removed. Branch references below are pinned to avoid mistaking ongoing work for an integrated result. `delivered` means source and named successor exist at that revision; their tests were inspected, not run on this branch. `partial` means a context/library/adapter exists but a last rendered/routed consumer remains. `pending` means no delivered successor was found. All rows have an owner; none permits deletion before integrated attestations. Shared 7 work depends on the named final feature owner, never on a renamed bridge.

### D1. Pinned feature handoffs

| Handoff | Branch revision | Delivered source / exact successor evidence | Status and outstanding last consumer |
| --- | --- | --- | --- |
| H3C | `feat/native-m3c` @ `441e531b19c35738567ffbd6764b48fbbc7fbe82` | W/layouts/auth_root.html.heex; N/auth_http.js; T/dawarich_web/native_auth_integration_test.exs: `every auth document and error response is Hotwire free with exactly one accessible label`; `native auth refusal never calls Rails and retained API/mobile responses stay unchanged` | delivered: auth HTTP roots/forms; integrated 7 CSS/static root audit remains |
| H3D | `feat/native-m3d` @ `63a252961e8ec9a16e93666ea26fd399d1db6ec7` | W/places_live/index.ex + detail.ex; W/native_places_envelope.ex; T/dawarich_web/native_places_routes_test.exs: `native Places unsupported formats refuse locally with no fragment`; D/places/commands.ex | delivered list/detail: map member frames remain 6; list handback configuration is ignored |
| H4 | `feat/native-m4` @ `274c8817115cfa187418e47436cb49f6a2d38eef` | W/imports_live/{index,new,show,edit}.ex; W/native_upload_target.ex; T/dawarich_web/imports_native_events_test.exs: `committed import progress survives missed delivery reconnect and duplicate wakeups`; T/dawarich_web/native_upload_target_test.exs: `external upload metadata and crashed handlers contain no target capability` | partial: imports upload/read/events delivered; export UI, remaining import commands, notification UI/badge streams pending 4 |
| H4C | `feat/native-m4c` @ `c0aba1f7b79a5ade9d2e61f674c86e4583c9940a` | W/families_live/*.ex; W/family_native_routes.ex; D/sharing.ex; T/dawarich_web/family_native_delivery_test.exs: `withdrawn consent or removed membership discards queued coordinates before rendering`; T/dawarich/sharing_scope_test.exs: `URL and phrase rotation preserve expiry semantics and invalidate old public admission` | partial: native family pages/delivery delivered; sharing context delivered, share hub/modal/public document migration pending; family map module has its own MapLibre instance, final 6 integration pending |
| H5 | `feat/native-m5` @ `140b1a2371e5c05a3fa476ac3ab5ba5ab6bb5090` | W/native_data_routes.ex; W/points_live/index.ex; N/hooks/{chart,heatmap}.js; T/dawarich_web/points_native_live_test.exs: `older point query cannot replace a new filter`; T/dawarich_web/data_async_test.exs: `an old timeout cannot stop a replacement read` | partial: points native; analytics/cache/refresh/chart foundations delivered; stats/insights/digests/visits/achievements page handoffs pending 5 |
| H5B | `feat/native-m5b` @ `21666881dc42b6293a1046ad1555ac8e88af431e` | W/native_trips_live/{index,form,show,notes}.ex; W/trips_native_routes.ex; N/hooks/rich_text.js; T/dawarich_web/trips_native_show_test.exs: `late day data and old timeout cannot replace the selected trip`; T/dawarich_web/trip_rich_text_test.exs: `a reserved upload claims only the actor's own fresh blob, once` | partial: library/editor and trip/note pages delivered; route macro defined but router integration pending; map hosts remain 6 |
| H6 | `feat/native-m6` @ `f395b43f86c8815372d7483143b74bb2c330217b` | N/map/runtime/{create_map,host,lifecycle,operation}.js; N/map/data/reader.js; W/browser_map_routes.ex; T/dawarich_web/native_family_map_test.exs: `native family reads recheck membership and withdrawn sharing`; T/dawarich_web/native_map_host_test.exs: `native host configuration never exposes credentials supplied outside its scalar contract` | partial: bounded cookie readers, disposable hosts, entity/photo/family layers delivered; top-level map/public/trip/achievement host migration pending 6 |
| H6B | `feat/native-m6b` @ `cb3945ce3a904f9b5e00ddf54febeaff5935ee4e` | N/map/{edit,replay,selection,ui}/*; W/map_live/*.ex; W/onboarding_live_component.ex; T/dawarich_web/native_demo_live_test.exs: `earlier timeout cannot cancel retry`; T/dawarich_web/native_timeline_filters_test.exs: `calendar response timeout belongs only to that run` | partial: map tools/timeline/Areas/onboarding/Immich delivered; final top-level map route/host handoff pending 6 |
| H6C | `feat/native-m6c` @ `3a94c230ec68494dae0c177b1b1eedd72a7f255f` | N/hooks/poster_studio.js; N/poster/{runtime,lifecycle,export/*}.js; W/native_poster_gallery.ex; T/dawarich_web/native_poster_gallery_test.exs: `gallery progress after revoke is dropped`; T/dawarich_web/native_poster_studio_test.exs: `studio config carries localized strings and digested font URLs only` | partial: poster studio/gallery/scoped commands delivered; integrated parent map/trip hosts and production fonts serving pending 6/7 |
| H6D | `feat/native-m6d` @ `39c67ffaf59f1a806772d43d3d15dafb99c1f30d` | N/video/{mp4_encoder,render/engine,upload}.js; D/route_videos/scoped.ex; W/route_video_upload.ex; T/dawarich/route_videos/scoped_test.exs: `foreign upload reference cannot attach` | partial: video timing/codec/engine/upload commands delivered; native video hook, visible save acknowledgement/gallery and host integration pending 6 |

Read-only evidence: `git show <revision>:<path>` and `git diff bdaa9aa36...<revision> -- app-phoenix docs/phoenix`. Baseline Appendices A–C remain the historical census; L01–L27 above and D/E are the execution ledgers. A route macro or module existing on a branch does not prove it has a live caller. Branch tests are named successors, not substituted acceptance evidence. Mixed L04/L08/L11/L12/L14/L15 rows require both listed feature handoffs at S1. No dependency adapters are needed for preparation-only ledgers.

### D2. Positive native asset/build/serve contract

`native-build` = esbuild ESM/splitting → `priv/static/native` → `phx.digest` → Endpoint `/native`; `public-copy` = explicit public payload → PublicFiles with host/path/MIME/HEAD/cache controls. `planned A3` means the replacement path is specified but is not yet implemented or verified. Such rows are a deletion hold, not an assertion of existing Rails-independent output. Every retained class has a concrete output/serve target; A3/A4 must verify existence and URL closure before release. Rails sources remain separately supported.

| Asset / request | Import parent and page/hook/worker consumer | Positive output / serve path | Owner / delivered successor / tests | Disposition and status |
| --- | --- | --- | --- | --- |
| Phoenix/LiveView client; N/app.js | native_root → native hooks; ordinary/admin/settings pages | native-build `/native/app.js` + split chunks | 3c–6 feature consumers; 7 A2; T/dawarich/build/native_assets_test.exs `the native bundle includes LiveView and no Hotwire module` | retain; current emitted graph reviewed, feature graph refresh at S1 |
| N/auth_http.js + http/auth_forms.js + auth_chrome.js | 3c auth_root; sign-in/signup/OTP/recovery/account/2FA HTTP | native-build `/native/auth_http.js`; no socket bootstrap | H3C; `HTTP auth eager graph fits 20 KiB without a socket or legacy runtime` | retain; delivered branch; absent from current build until integration |
| @emoji-mart/data + emoji-mart | N/hooks/emoji_picker.js dynamic library; form emoji controls | native-build lazy chunks | 3d/5/6 forms; native_assets `emoji-mart is a separate lazily loaded chunk` | retain; current lazy closure |
| spark-md5 + archive preparation | N/hooks/archive_checksum.js; N/uploads/prepare_file.js on H4; uploads | native-build; no upload capability in assigns | 4; native upload target/event tests H4 | retain; native checksum exists, new multi-file preparation delivered branch |
| Direct uploader + signed upload target | N/uploaders/direct.js; H4 upload target; H5B editor attachment | native-build; target URI obtained by admitted HTTP, storage URLs unchanged | 4/5/6; `native graph distinguishes direct-upload adapters from Hotwire runtime` | retain storage protocol and adapter; no blanket direct_upload ban |
| Chartkick/Chart.js | old J chartkick loader → chart controls; H5 N/hooks/chart.js + charts/library.js and public_charts.js | native-build lazy chart library + `/native/public_charts.js` for public documents | 5; native_chart `native chart carries localized single and multiple series without executable scripts` | retain plain library, retire old controller boot; hook/library delivered, page consumers pending |
| Trix plain editor + attachments | H5B N/hooks/rich_text.js dynamically imports `trix` and editor/attachments.js; trip rich description | native-build lazy editor; scoped native upload reservation; sanitized ActionText storage retained | 5b; trip_rich_text reserved upload test + trips_native_form validation case | retain Trix library; retire @rails/actiontext frontend integration, Turbo/Stimulus boot; delivered branch, integrated closure pending |
| MapLibre ESM + shared module + worker | native demo; H4C family; H6 map; H6C poster; H6D video; `/maplibre/6.4.1/maplibre-gl.mjs` imports shared and worker module | public-copy `public/maplibre/6.4.1/{maplibre-gl,maplibre-gl-shared,maplibre-gl-worker}.mjs`; `/maplibre/6.4.1/*` | 6 last host; native_assets vendored module test; H6 lifecycle | retain external URL import; current copy exists; worker closure separate from esbuild metafile |
| MapLibre RTL | Rails map runtime conditional RTL plugin request | pin/copy declared RTL payload only if final H6 runtime requests it; external endpoint must be explicitly documented | 6 last consumer; 7 A2/A4 verify final request graph | pending H6 decision: no native RTL request found in inspected foundation; never infer from importmap pin |
| Basemap styles, glyphs, sprites | N/demo/map_style.js → `/maps_maplibre/styles/{light,dark}.json`; H6 style loaders; style JSON URLs | public-copy `public/maps_maplibre/styles/*.json`; glyph/sprite URLs declared in style JSON (Protomaps HTTPS) | 6; native_assets vendored styles test; H6/H6B | retain local styles + explicitly external glyph/sprite data; network not exercised here |
| Offline tiles/map archives and geodata | public/maps; runtime `/maps`; countries/admin1 data readers; no JS boot ownership | public-copy `public/maps/*`; release priv countries.geojson.gz/admin1_world.geojson | 6; 7 A4 positive package + X4 actual offline data serve | retain; copied current payload; exact used archives refresh at S1 |
| tailwind.css / DaisyUI theme | native_root + all feature roots; application.tailwind.css + config/tailwind.config.js | planned A3 native CSS build from explicit input/classes → native digest; no importmap discovery | 3c–6 last classes; 7 A3; `native assets build with Rails frontend configuration absent` successor pending | retain theme/toolchain; current path still `/assets` Sprockets |
| application.css + achievement CSS trio | native_root; achievements/cards/unlocks; SVG/data URI meshes | planned A3 explicit CSS entries → native digest; embedded data SVG has no fetch | 5/6 achievements last consumer; 7 A3 | retain used CSS; current stylesheet resolver remains Rails manifest |
| inter-font.css and font files | native_root; `vendor/assets/stylesheets/inter-font.css` → `vendor/assets/fonts/Inter-*.woff2` URL closure | planned A3 copy fonts preserving CSS relative URLs or digest rewrite under `/native`; W/PublicFiles MIME/cache/HEAD | 3c–6; 7 A3 served-font test pending | retain fonts; current resolver still Rails manifest |
| Brand fonts; poster WOFF2 fonts | brand_fonts.css.erb asset_path; H6C poster_fonts.ex and poster/data/fonts.js; H6D HUD | planned A3 explicit native font manifest from `app/assets/fonts/{brand,poster}/*`; `/native/fonts/...` digested URLs; no ERB/importmap compile | 6c/6d last export consumers; 7 A3/A4 | retain exact fonts; H6C digested URL contract delivered; actual native copy pending |
| Lucide SVG icons + logos/images | W/Icon embeds SVG; favicon/PWA/chrome/achievement images; SVG/PNG/WebP asset references | embedded icon SVG needs no request; planned A3 explicit used image manifest → native digest; public icons via public-copy | 3c–6 last chrome/card consumers; 7 A3/A4 | retain used media; transitive image closure refreshed after feature integration |
| Achievements definitions/i18n/metadata | Build.Achievements/Build.I18n → tmp/phoenix JSON; card labels/layouts | independent data export task planned A3; `tmp/phoenix/{i18n,achievements}.json` without frontend import discovery | 5; 7 A3; compare_build_inputs data/gzip/timezone invariants | retain data; current mixed BuildInputs also compiles importmap/Sprockets |
| Poster PNG/PDF dependencies | H6C N/poster/export/{png_encoder,pdf_encoder,capture,download}.js; browser preview/print | native-build lazy `pdf-lib` and native export modules; MapLibre/public fonts separate | 6c; poster studio/gallery tests H6C | retain browser encoder/library + cancellation; delivered branch, parent hosts pending |
| Video MP4/WebCodecs dependencies | H6D N/video/mp4_encoder.js → `mp4-muxer`; render/engine.js → map capture/HUD | native-build lazy studio chunks; browser codec feature detection, no polyfill legacy loader | 6d; scoped route video/upload tests H6D | retain engine/library; visible native studio/hook not yet delivered |
| Poster server renderer/ABI/fonts/themes | D/posters generation/progress; vendor/poster_renderer/render.mjs; public/poster_themes | explicit renderer stage/copy + fonts/node ABI/native runtime libs; public-copy themes | 6c; 7 A4 payload + X4 render test pending | retain server artifact; distinct from browser importmap graph |
| PWA/favicon/manifest | W/Pwa + W/layouts/native_root; public/site.webmanifest and named icons | public-copy `.webmanifest/.ico/.png/.svg`; declared manifest icons served directly | all page owners; 7 A4/X4 | retain; current payload copied, no new offline service worker claimed |
| Swagger/OpenAPI UI + specification | W/api docs HTTP, `/api-docs`; swagger-ui-dist; swagger/v1/swagger.yaml | explicit API docs copy + specification/data export, independent of native app JS/importmap | 7 B1/A4; API docs and dockerfile retained tests | retain public API contract; current explicit COPY |
| Legacy J/app.js, rails_bridge/map_shell/family_page/hooks | hybrid roots/importmap → 3c–6 feature islands | no final native output/serve path; Rails whole-app artifact owns its own source | H3C/H3D/H4/H4C/H5/H5B/H6/H6B/H6C/H6D; A1/A2 successors in main retarget table | retire native reachability at S1, partial handoffs; retain Rails source |

The esbuild input graph records direct, dynamic and external module edges with their parent and kind. Public-copy workers, CSS URLs, remote style payloads and browser-created blobs require the positive rows above and A2 runtime validation; a zero-forbidden esbuild graph alone does not close them. Current native app graph has no Rails JS imports; availability in Rails importmap is not evidence of fetching. The graph must include all new entrypoints and worker entrypoints after S1. Trix is a browser editor library here; the banned mechanism is @rails/actiontext integration and Hotwire boot, not sanitized stored rich text.

### D3. Context-to-web dependency audit

Source audit uses `rg -n 'DawarichWeb|Plug\.|Phoenix\.' app-phoenix/lib/dawarich --glob '*.ex'`. The following file-level ledger accounts for every match, including infrastructure exceptions. Business/web coupling is assigned for feature-owner follow-up rather than rewritten in 7. `retain infrastructure` preserves real protocol/security/crypto/supervision; `audit business` requires typed values/presenters/adapters on the owning feature, not a forwarding facade. A branch replacement does not authorize deleting the old module while other HTTP/API callers remain.

| Domain source | Classification / owner | Pinned branch status |
| --- | --- | --- |
| `D/account_api/exist.ex:14` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/accounts.ex:83` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/achievements/collection.ex:230` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/achievements/og_image.ex:148` | retain infrastructure/security; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/achievements/public_card.ex:4` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/admin/access.ex:44` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/admin/operator_grant.ex:22` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/after_commit/worker.ex:70` | retain infrastructure/security; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/application.ex:101` | retain infrastructure/security; shared 7 (operational seam preserved) | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/account_changes.ex:105` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/account_closure.ex:21` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/account_link/closure.ex:3` | audit business/presentation; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/action_csrf.ex:3` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/admission.ex:12` | audit business/presentation; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/api/challenge_token.ex:46` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/apple/callback.ex:5` | audit business/presentation; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/apple/cookies.ex:3` | audit business/presentation; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/apple/verify.ex:31` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/credentials_closure.ex:68` | audit business/presentation; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/destroy_token.ex:37` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/mobile/payload.ex:4` | audit business/presentation; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/mobile/registration.ex:5` | audit business/presentation; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/providers/completion.ex:13` | audit business/presentation; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/providers/failure.ex:3` | audit business/presentation; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/providers/google.ex:122` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/providers/oidc_claims.ex:31` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/providers/state.ex:18` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/recovery/closure.ex:151` | audit business/presentation; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/recovery/lifecycle.ex:203` | audit business/presentation; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/registration_setup.ex:136` | audit business/presentation; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/session_cookie.ex:5` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/two_factor/secret.ex:63` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/auth/two_factor/totp.ex:58` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/cable.ex:33` | retain infrastructure/security; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/cable/pg_bus.ex:53` | retain infrastructure/security; shared 7 (operational seam preserved) | edge remains in inspected branches; retained callers require follow-up |
| `D/cable/turbo_events.ex:5` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/demo_data/derivatives.ex:137` | retain infrastructure/security; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/digests.ex:11` | audit business/presentation; milestone 5 / H5 | 5: web edge removed |
| `D/digests/context.ex:34` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/digests/http_writes.ex:30` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/digests/read_closure.ex:5` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/digests/sharing.ex:4` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/digests/web_commands.ex:5` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/error_reporting.ex:138` | retain infrastructure/security; shared 7 (operational seam preserved) | edge remains in inspected branches; retained callers require follow-up |
| `D/families/auto_create.ex:9` | audit business/presentation; milestone 4 / H4C | edge remains in inspected branches; retained callers require follow-up |
| `D/families/history.ex:7` | audit business/presentation; milestone 4 / H4C | edge remains in inspected branches; retained callers require follow-up |
| `D/families/member_sync.ex:6` | audit business/presentation; milestone 4 / H4C | edge remains in inspected branches; retained callers require follow-up |
| `D/families/sharing_update/web.ex:16` | audit business/presentation; milestone 4 / H4C | edge remains in inspected branches; retained callers require follow-up |
| `D/family_api/closure.ex:6` | audit business/presentation; milestone 4 / H4C | edge remains in inspected branches; retained callers require follow-up |
| `D/front.ex:38` | retain infrastructure/security; shared 7 (operational seam preserved) | edge remains in inspected branches; retained callers require follow-up |
| `D/front/drainer.ex:13` | retain infrastructure/security; shared 7 (operational seam preserved) | edge remains in inspected branches; retained callers require follow-up |
| `D/imports/api.ex:48` | audit business/presentation; milestone 4 / H4 | edge remains in inspected branches; retained callers require follow-up |
| `D/imports/events.ex:3` | retain infrastructure/security; milestone 4 / H4 | edge remains in inspected branches; retained callers require follow-up |
| `D/imports/integrations/photo_import_record.ex:7` | audit business/presentation; milestone 4 / H4 | edge remains in inspected branches; retained callers require follow-up |
| `D/imports/postprocessing/native.ex:50` | audit business/presentation; milestone 4 / H4 | edge remains in inspected branches; retained callers require follow-up |
| `D/imports/rails_blob_reference.ex:8` | retain infrastructure/security; milestone 4 / H4 | edge remains in inspected branches; retained callers require follow-up |
| `D/imports/stale_recovery.ex:6` | audit business/presentation; milestone 4 / H4 | edge remains in inspected branches; retained callers require follow-up |
| `D/imports/teslamate/effects.ex:100` | audit business/presentation; milestone 4 / H4 | edge remains in inspected branches; retained callers require follow-up |
| `D/imports/trek/endpoint.ex:76` | audit business/presentation; milestone 4 / H4 | edge remains in inspected branches; retained callers require follow-up |
| `D/insights.ex:7` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/insights/details.ex:7` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/insights/details/totals.ex:5` | audit business/presentation; milestone 5 / H5 | 5: web edge removed |
| `D/insights/fragments.ex:5` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/insights/heatmap.ex:5` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/integrations.ex:6` | audit business/presentation; milestone 4 / H4 | edge remains in inspected branches; retained callers require follow-up |
| `D/integrations/sync_scheduling.ex:8` | audit business/presentation; milestone 4 / H4 | edge remains in inspected branches; retained callers require follow-up |
| `D/mail/digests/render.ex:9` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/mail/residual.ex:7` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/map_api/params.ex:6` | audit business/presentation; milestone 6 / H6 | edge remains in inspected branches; retained callers require follow-up |
| `D/map_gallery.ex:92` | audit business/presentation; milestone 6 / H6 | edge remains in inspected branches; retained callers require follow-up |
| `D/map_page.ex:88` | audit business/presentation; milestone 6 / H6 | edge remains in inspected branches; retained callers require follow-up |
| `D/metrics/web.ex:134` | retain infrastructure/security; shared 7 (operational seam preserved) | edge remains in inspected branches; retained callers require follow-up |
| `D/pending_imports/intake.ex:38` | audit business/presentation; milestone 4 / H4 | edge remains in inspected branches; retained callers require follow-up |
| `D/places/web_write.ex:15` | audit business/presentation; milestone 3 / H3D | edge remains in inspected branches; retained callers require follow-up |
| `D/point_list.ex:6` | audit business/presentation; milestone 5 / H5 | 5: web edge removed |
| `D/points/live_broadcast_worker.ex:91` | audit business/presentation; milestone 6 / H6 | edge remains in inspected branches; retained callers require follow-up |
| `D/posters/generation.ex:7` | audit business/presentation; milestone 6 / H6C | edge remains in inspected branches; retained callers require follow-up |
| `D/posters/geometry.ex:5` | audit business/presentation; milestone 6 / H6C | edge remains in inspected branches; retained callers require follow-up |
| `D/posters/persistence.ex:56` | audit business/presentation; milestone 6 / H6C | edge remains in inspected branches; retained callers require follow-up |
| `D/posters/progress_worker.ex:5` | audit business/presentation; milestone 6 / H6C | edge remains in inspected branches; retained callers require follow-up |
| `D/rails_cookies.ex:50` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/rails_messages.ex:111` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/rails_secret.ex:31` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/route_videos/writes.ex:35` | audit business/presentation; milestone 6 / H6D | edge remains in inspected branches; retained callers require follow-up |
| `D/settings/api.ex:5` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/settings/general.ex:44` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/settings/integrations.ex:5` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/settings/integrations/connection.ex:3` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/share_management/read.ex:75` | audit business/presentation; milestone 4 / H4C | edge remains in inspected branches; retained callers require follow-up |
| `D/spatial/calendar_window.ex:9` | audit business/presentation; milestone 6 / H6 | edge remains in inspected branches; retained callers require follow-up |
| `D/stats/api_closure.ex:19` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/stats/web_commands.ex:4` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/storage/variation.ex:38` | retain infrastructure/security; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/subscriptions/cache.ex:36` | audit business/presentation; milestone 4 / H4 | edge remains in inspected branches; retained callers require follow-up |
| `D/subscriptions/callback.ex:20` | retain infrastructure/security; milestone 4 / H4 | edge remains in inspected branches; retained callers require follow-up |
| `D/tiles/http.ex:3` | audit business/presentation; milestone 6 / H6 | edge remains in inspected branches; retained callers require follow-up |
| `D/tracks/daily_worker.ex:13` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/trial/welcome.ex:8` | audit business/presentation; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/trial/welcome_session.ex:5` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/trial/welcome_token.ex:14` | retain infrastructure/security; milestone 3 / H3C | edge remains in inspected branches; retained callers require follow-up |
| `D/trip_page.ex:100` | audit business/presentation; milestone 5 / H5B | edge remains in inspected branches; retained callers require follow-up |
| `D/trips/attachments.ex:5` | audit business/presentation; milestone 5 / H5B | edge remains in inspected branches; retained callers require follow-up |
| `D/trips/rich_content.ex:282` | retain infrastructure/security; milestone 5 / H5B | edge remains in inspected branches; retained callers require follow-up |
| `D/trips/web_export.ex:44` | audit business/presentation; milestone 5 / H5B | edge remains in inspected branches; retained callers require follow-up |
| `D/trips/web_form.ex:81` | audit business/presentation; milestone 5 / H5B | edge remains in inspected branches; retained callers require follow-up |
| `D/trips/web_notes.ex:119` | audit business/presentation; milestone 5 / H5B | edge remains in inspected branches; retained callers require follow-up |
| `D/visits/bulk_sweep.ex:58` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/visits/history_redetect.ex:38` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/visits/realtime_debouncer.ex:61` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/visits/user_redetect_worker.ex:121` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/visits/web_settings.ex:82` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/visits_api/create.ex:7` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/visits_api/read.ex:6` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |
| `D/visits_api/update.ex:7` | audit business/presentation; milestone 5 / H5 | edge remains in inspected branches; retained callers require follow-up |

### D4. Preparation verification and remaining deletion holds

A0's two graph contracts are named in `T/dawarich/build/frontend_inventory_test.exs`. Production esbuild input/output metafile was reviewed after a minified build; results and RED/GREEN/mutations are recorded in the implementation report. No emitted asset/runtime proof is claimed for unmerged feature branches. Zero unowned L rows and zero unowned positive asset rows are required; pending rows are deliberately owned. S1 owner attestations, complete CSS/font/media/dynamic worker serving and integrated context-boundary closure remain A1–A4/B2/C1 acceptance work. The A0 checkbox means the preparation ledger is complete, not those future deletions.

### D5. Current minified production import closure

Built with the configured esbuild native profile plus `--minify` and `--metafile`; 0 forbidden reachable edges. Snapshot applies to the current entrypoint only, not unmerged feature entrypoints. Worker/CSS/public payloads are covered separately in D2. Module parent/edge rows below are all `retain; current`, except public MapLibre resolution which additionally needs A2 runtime closure.

| Import parent | Requested module | Edge kind | Last feature owner / output / status |
| --- | --- | --- | --- |
| `<entry>` | `js/app.js` | entry-point | 3c–6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/app.js` | `../deps/phoenix/priv/static/phoenix.mjs` | import-statement | 3c–6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/app.js` | `../deps/phoenix_html/priv/static/phoenix_html.js` | import-statement | 3c–6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/app.js` | `../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js` | import-statement | 3c–6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/app.js` | `js/hooks/index.js` | import-statement | 3c–6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/app.js` | `js/uploaders/direct.js` | import-statement | 4; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/hooks/archive_checksum.js` | `node_modules/spark-md5/spark-md5.js` | import-statement | 4; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/hooks/emoji_picker.js` | `node_modules/@emoji-mart/data/sets/15/native.json` | dynamic-import | 3d/5/6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/hooks/emoji_picker.js` | `node_modules/emoji-mart/dist/module.js` | dynamic-import | 3d/5/6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/hooks/index.js` | `js/hooks/achievement_unlocks.js` | import-statement | 3c–6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/hooks/index.js` | `js/hooks/archive_checksum.js` | import-statement | 4; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/hooks/index.js` | `js/hooks/changelog_widget.js` | import-statement | 3c–6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/hooks/index.js` | `js/hooks/clipboard.js` | import-statement | 3c–6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/hooks/index.js` | `js/hooks/dismissible.js` | import-statement | 3c–6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/hooks/index.js` | `js/hooks/emoji_picker.js` | import-statement | 3d/5/6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/hooks/index.js` | `js/hooks/map_matching_demo.js` | import-statement | 6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/hooks/index.js` | `js/hooks/scroll_into_view.js` | import-statement | 3c–6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/hooks/map_matching_demo.js` | `/maplibre/6.4.1/maplibre-gl.mjs` | dynamic-import | 6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/hooks/map_matching_demo.js` | `js/demo/map_matching_demo.js` | dynamic-import | 6; native ESM chunks or explicit MapLibre public copy; retain/current |
| `js/hooks/map_matching_demo.js` | `js/demo/map_style.js` | dynamic-import | 6; native ESM chunks or explicit MapLibre public copy; retain/current |

Emitted outputs (minified, decoded bytes): `app.js` 166694, `chunk-EK7ODJWE.js` 544, `map_matching_demo-RKNGY2XH.js` 3694, `map_style-WJPVUPX6.js` 616, `module-PDNVUU6P.js` 77332, `native-HK3EVIFZ.js` 434064. Content hashes/commands are in the report; generated artifacts are untracked.

A0 verification: scanner/assets/direct caller batch 17 passed, seed 404, warnings-as-errors, exit 0. Named direct-upload and dynamic-import mutations each fail their owning test; restored batch passes. No routes/code consumers were deleted.

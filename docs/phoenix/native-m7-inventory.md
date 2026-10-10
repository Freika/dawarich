# Native frontend milestones 7–8: removal inventory and acceptance baseline

Date: 2026-10-10. Planning only. Source snapshot: `bdaa9aa363230857b5a96fe67eb1e6d10f7390b3` (verified 3b descendant); E2E source: `ff256e6fd6a8a50f3f05a9e5a1e9656ef5a47b2d`. No production/test changes, measurements, suites or services were run for this inventory. Counts below are static search results, not runtime reachability proof.

Source scope: `docs/phoenix/native-frontend-contexts-plan-20261008.md:138` (7), `:154` (8). Accepted ADR-0017 supersedes the old exact-markup/coexistence frontend contract. The verified 3b plan and `docs/phoenix/native-m3b-inventory.md:5` supply the acceptance template and review lessons. This document deliberately distinguishes a last **feature consumer** from deletion of the **shared mechanism** in 7.

Citation roots: `W/` = `app-phoenix/lib/dawarich_web/`; `D/` = `app-phoenix/lib/dawarich/`; `T/` = `app-phoenix/test/`; `J/` = `app-phoenix/priv/static/js/`; `N/` = `app-phoenix/assets/js/`; `E/` = the E2E repository source inspected for this task. All other paths are repository-relative unless named workspace artifacts. Allocation details belong to the controller's execution configuration, never committed application/test/document defaults.

Execution update (2026-10-10): A0/B0 preparation is complete in Appendices D/E. The source census and planning statements above remain historical. No frontend code or routes were removed; feature integration, S1 attestations and native runtime acceptance remain pending.

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

## Appendix E — B0 route, admission and external-client execution ledger

Snapshot: current compiled Router at `264ce4aad` (same production sources as A0 `201ff3aae`). This is preparation, with no route/code removal. R rows are exact compiled routes, including pipeline order, LiveView action/session and ownership metadata. P rows below bind every pipeline to its ordered source plugs. G rows split old ownership/envelope decisions from retained admission; C/U rows cover constraints and URL negotiation. Authentication before Router, static mounts and the standalone dispatcher are separately enumerated, so the Router alone is not the entire HTTP contract. Refusal/error/status contracts stay local in the final native endpoint; current coexistence handback is recorded for retirement, never recommended as a native successor.

### E1. Refreshed parallel branch evidence

A0 D1 revisions are the first snapshot, retained as history. The following read-only refresh pins the resumed branches; no branch was merged. WIP means committed interrupted implementation, not verification or owner attestation. The exact source/test successor references in D1 still apply; new source evidence supplements them here.

| Handoff | Refreshed branch revision | Change since D1 / remaining final consumer |
| --- | --- | --- |
| H3C | `feat/native-m3c` @ `0e30b65f1292e9b0d0c4bd9c9da5c540022162c3` | auth source unchanged; inventory acceptance recorded; delivered HTTP roots/forms |
| H3D | `feat/native-m3d` @ `63a252961e8ec9a16e93666ea26fd399d1db6ec7` | unchanged; delivered list/detail, map drawer remains 6 |
| H4 | `feat/native-m4` @ `ff1080888ed15de215fd7f6efa83a32d12388f4c` | W/imports_live/index.ex adds delete events; interrupted batch unverified; export/notification final consumers remain 4 |
| H4C | `feat/native-m4c` @ `30420b1d4ad6aeee02fc3bb7a01c83a83466b68c` | W/native_sharing_routes.ex and SharingLive.Index now replace hub/live/timeline/trip/track read modals; native secret reveal is admitted HTTP; interrupted source, public hosts remain 6; signed/wire consumers require audit |
| H5 | `feat/native-m5` @ `770ee5ba173dbf7f63e2e771c74e306d16d0236b` | W/native_data_routes.ex now routes /stats and /stats/:year to StatsLive.NativePage; NativeMonthParts scaffolding, month route/page still pending; insights/digests/visits/achievements remain 5 |
| H5B | `feat/native-m5b` @ `21666881dc42b6293a1046ad1555ac8e88af431e` | unchanged; native trip/editor/note interfaces delivered, integrated map host remains 6 |
| H6 | `feat/native-m6` @ `8b5dfd0de703dce71d648c5df2f0d5240c2b8286` | N/hooks/family.js + trip.js and native trip/family MapLibre runtimes/components added; final parent mounts/routes still require integrated handoff; interrupted batch unverified |
| H6B | `feat/native-m6b` @ `bf485814b1b0267146135ffe0e2524c4d30080d6` | native map visit/place/address components and VisitCommands added; interrupted batch unverified; top-level map host remains 6 |
| H6C | `feat/native-m6c` @ `3a94c230ec68494dae0c177b1b1eedd72a7f255f` | unchanged; poster runtime/gallery delivered, parent hosts/fonts serving remain 6/7 |
| H6D | `feat/native-m6d` @ `ecd54d391a12b7a088a39359846d64252fa77a98` | N/hooks/video_studio.js and video/studio*.js plus NativeVideoStudio/Playback/Sections and VideoStudioLiveComponent added; hook not registered in N/hooks/index.js at this revision; parent/gallery handoff remains 6 |

Status refresh for L rows: L05/L17 now have a video studio hook/component implementation but pending registration/host consumers; L11 has native share hub/modal routes on 4c; L13 has stats index/year on 5 while month and the other analytics pages remain pending; L04/L14 have delivered family/trip browser runtimes on 6, with integrated parent proof pending. Other L01–L27 dispositions stand. A pending consumer always has a named 3c/3d/4/5/6 owner and a shared 7 deletion task; no source-presence claim substitutes for S1 attestation.

### E2. Compiled method/path/handler/pipeline/session/metadata matrix

Policy references are cumulative: `P:<pipeline>` ordered admission below, `G:<module.function>` below when present, `C` path constraints, `U` aliases/format/HEAD. `rails_key` and `slice` are routing ownership only: retire in B3 after B1 direct API promotion and B2 admission; `native_api` preserves transport semantics rather than granting authorization; `retired` records intentionally local rejection. Existing routes without a gate still require their pipeline, handler and LiveView context admission. Each row's owner identifies its last feature handoff, followed by shared cleanup task. APIs/health/storage/operator/wire are retained protocols, not removable UI.

| ID | Method | Path | Current handler/action | Ordered pipelines | LiveView action/session | Ownership metadata | Constraint/format/refusal policy | Last feature / cleanup owner | Branch status / disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| R001 | `GET` | `/metrics` | `DawarichWeb.Metrics :scrape` | `metrics` | `-` | `%{}` | P:metrics; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R002 | `DELETE` | `/api/v1/users/me` | `DawarichWeb.Api.AccountDestroyController :destroy` | `api_account_destroy` | `-` | `%{slice: :api_account, rails_gate: {DawarichWeb.Api.AccountDestroyController, :enabled?}}` | P:api_account_destroy; G:DawarichWeb.Api.AccountDestroyController.enabled?; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R003 | `POST` | `/api/v1/users/exist` | `DawarichWeb.Api.UsersController :exist` | `api_manager` | `-` | `%{slice: :api_account}` | P:api_manager; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R004 | `GET` | `/api/v1/users/me` | `DawarichWeb.Api.UsersController :me` | `api_account` | `-` | `%{slice: :api_account}` | P:api_account; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R005 | `POST` | `/api/v1/users/me/two_factor/setup` | `DawarichWeb.Api.TwoFactorController :setup` | `api_account` | `-` | `%{slice: :api_account}` | P:api_account; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R006 | `POST` | `/api/v1/users/me/two_factor/confirm` | `DawarichWeb.Api.TwoFactorController :confirm` | `api_account` | `-` | `%{slice: :api_account}` | P:api_account; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R007 | `POST` | `/api/v1/users/me/two_factor/backup_codes` | `DawarichWeb.Api.TwoFactorController :backup_codes` | `api_account` | `-` | `%{slice: :api_account}` | P:api_account; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R008 | `DELETE` | `/api/v1/users/me/two_factor` | `DawarichWeb.Api.TwoFactorController :destroy` | `api_account` | `-` | `%{slice: :api_account}` | P:api_account; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R009 | `POST` | `/api/v1/visits/merge` | `DawarichWeb.Api.VisitsController :merge` | `api_visits` | `-` | `%{slice: :api_visits}` | P:api_visits; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R010 | `POST` | `/api/v1/visits/bulk_update` | `DawarichWeb.Api.VisitsController :bulk_update` | `api_visits` | `-` | `%{slice: :api_visits}` | P:api_visits; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R011 | `POST` | `/api/v1/visits/batch` | `DawarichWeb.Api.VisitsController :batch` | `api_visits` | `-` | `%{slice: :api_visits}` | P:api_visits; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R012 | `GET` | `/api/v1/visits` | `DawarichWeb.Api.VisitsController :index` | `api_visits` | `-` | `%{slice: :api_visits}` | P:api_visits; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R013 | `POST` | `/api/v1/visits` | `DawarichWeb.Api.VisitsController :create` | `api_visits` | `-` | `%{slice: :api_visits}` | P:api_visits; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R014 | `GET` | `/api/v1/visits/:id` | `DawarichWeb.Api.VisitsController :show` | `api_visits` | `-` | `%{slice: :api_visits}` | P:api_visits; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R015 | `PATCH` | `/api/v1/visits/:id` | `DawarichWeb.Api.VisitsController :update` | `api_visits` | `-` | `%{slice: :api_visits}` | P:api_visits; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R016 | `PUT` | `/api/v1/visits/:id` | `DawarichWeb.Api.VisitsController :update` | `api_visits` | `-` | `%{slice: :api_visits}` | P:api_visits; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R017 | `DELETE` | `/api/v1/visits/:id` | `DawarichWeb.Api.VisitsController :destroy` | `api_visits` | `-` | `%{slice: :api_visits}` | P:api_visits; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R018 | `GET` | `/api/v1/visits/:id/possible_places` | `DawarichWeb.Api.VisitsController :possible_places` | `api_visits` | `-` | `%{slice: :api_visits}` | P:api_visits; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R019 | `POST` | `/api/v1/visits/:id/select_place` | `DawarichWeb.Api.VisitsController :select_place` | `api_visits` | `-` | `%{slice: :api_visits}` | P:api_visits; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R020 | `GET` | `/api/v1/notes` | `DawarichWeb.Api.NotesController :index` | `api_notes` | `-` | `%{slice: :api_notes}` | P:api_notes; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R021 | `POST` | `/api/v1/notes` | `DawarichWeb.Api.NotesController :create` | `api_notes` | `-` | `%{slice: :api_notes}` | P:api_notes; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R022 | `GET` | `/api/v1/notes/:id` | `DawarichWeb.Api.NotesController :show` | `api_notes` | `-` | `%{slice: :api_notes}` | P:api_notes; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R023 | `PATCH` | `/api/v1/notes/:id` | `DawarichWeb.Api.NotesController :update` | `api_notes` | `-` | `%{slice: :api_notes}` | P:api_notes; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R024 | `PUT` | `/api/v1/notes/:id` | `DawarichWeb.Api.NotesController :update` | `api_notes` | `-` | `%{slice: :api_notes}` | P:api_notes; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R025 | `DELETE` | `/api/v1/notes/:id` | `DawarichWeb.Api.NotesController :destroy` | `api_notes` | `-` | `%{slice: :api_notes}` | P:api_notes; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R026 | `GET` | `/api/v1/shared/:id/trip` | `DawarichWeb.Api.SharedController :trip` | `api_shared` | `-` | `%{slice: :api_shared}` | P:api_shared; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R027 | `GET` | `/api/v1/shared/:id/points` | `DawarichWeb.Api.SharedController :points` | `api_shared` | `-` | `%{slice: :api_shared}` | P:api_shared; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R028 | `GET` | `/api/v1/shared/:id/route` | `DawarichWeb.Api.SharedController :route` | `api_shared` | `-` | `%{slice: :api_shared}` | P:api_shared; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R029 | `GET` | `/api/v1/shared/:id/photos` | `DawarichWeb.Api.SharedController :photos` | `api_shared` | `-` | `%{slice: :api_shared, rails_gate: {DawarichWeb.Api.SharedController, :photos_owned?}}` | P:api_shared; G:DawarichWeb.Api.SharedController.photos_owned?; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R030 | `GET` | `/api/v1/shared/:id/photos/:photo_id/thumbnail` | `DawarichWeb.Api.SharedController :thumbnail` | `api_shared` | `-` | `%{slice: :api_shared, rails_gate: {DawarichWeb.Api.SharedController, :photos_owned?}}` | P:api_shared; G:DawarichWeb.Api.SharedController.photos_owned?; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R031 | `POST` | `/api/v1/points` | `DawarichWeb.Api.IngestController {:native, :points}` | `api_ingest` | `-` | `%{slice: :ingest}` | P:api_ingest; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R032 | `POST` | `/api/v1/overland/batches` | `DawarichWeb.Api.IngestController {:native, :overland}` | `api_ingest` | `-` | `%{slice: :ingest}` | P:api_ingest; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R033 | `POST` | `/api/v1/owntracks/points` | `DawarichWeb.Api.IngestController {:native, :owntracks}` | `api_ingest` | `-` | `%{slice: :ingest}` | P:api_ingest; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R034 | `POST` | `/api/v1/traccar/points` | `DawarichWeb.Api.IngestController {:native, :traccar}` | `api_ingest` | `-` | `%{slice: :ingest}` | P:api_ingest; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R035 | `GET` | `/api/v1/imports` | `DawarichWeb.Api.ImportsController :index` | `api_stats` | `-` | `%{slice: :ingest, native_api: true}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R036 | `GET` | `/api/v1/imports/:id` | `DawarichWeb.Api.ImportsController :show` | `api_stats` | `-` | `%{slice: :ingest, native_api: true}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R037 | `POST` | `/api/v1/imports/pending` | `DawarichWeb.Api.PendingImportsController :create` | `api_pending` | `-` | `%{slice: :ingest, native_api: true}` | P:api_pending; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R038 | `POST` | `/api/v1/imports` | `DawarichWeb.Api.ImportsController :create` | `api_ingest` | `-` | `%{slice: :ingest, native_api: true}` | P:api_ingest; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R039 | `DELETE` | `/api/v1/points/bulk_destroy` | `DawarichWeb.Api.PointWritesController :bulk_destroy` | `api_ingest` | `-` | `%{slice: :ingest, native_api: true}` | P:api_ingest; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R040 | `POST` | `/api/v1/points/reapply_anomaly_filter` | `DawarichWeb.Api.AnomalyController :create` | `api_ingest` | `-` | `%{slice: :ingest, native_api: true}` | P:api_ingest; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R041 | `PATCH` | `/api/v1/points/:point_id/position` | `DawarichWeb.Api.PointPositionsController :update` | `api_ingest` | `-` | `%{slice: :ingest, native_api: true}` | P:api_ingest; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R042 | `PUT` | `/api/v1/points/:point_id/position` | `DawarichWeb.Api.PointPositionsController :update` | `api_ingest` | `-` | `%{slice: :ingest, native_api: true}` | P:api_ingest; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R043 | `PATCH` | `/api/v1/points/:id` | `DawarichWeb.Api.PointWritesController :update` | `api_ingest` | `-` | `%{slice: :ingest, native_api: true}` | P:api_ingest; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R044 | `PUT` | `/api/v1/points/:id` | `DawarichWeb.Api.PointWritesController :update` | `api_ingest` | `-` | `%{slice: :ingest, native_api: true}` | P:api_ingest; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R045 | `DELETE` | `/api/v1/points/:id` | `DawarichWeb.Api.PointWritesController :destroy` | `api_ingest` | `-` | `%{slice: :ingest, native_api: true}` | P:api_ingest; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R046 | `GET` | `/api/v1/plan` | `DawarichWeb.Api.PlanController :show` | `api_foundation` | `-` | `%{slice: :api_foundation}` | P:api_foundation; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R047 | `GET` | `/api/v1/timeline` | `DawarichWeb.Api.TimelineController :index` | `api_stats` | `-` | `%{slice: :api_map_reads, native_api: true}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R048 | `GET` | `/api/v1/tags/privacy_zones` | `DawarichWeb.Api.PrivacyZonesController :index` | `api_stats` | `-` | `%{slice: :api_map_reads, native_api: true}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R049 | `GET` | `/api/v1/countries/borders` | `DawarichWeb.Api.SpatialController :borders` | `api_stats` | `-` | `%{slice: :api_map_reads, native_api: true}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R050 | `GET` | `/api/v1/countries/visited` | `DawarichWeb.Api.SpatialController :visited` | `api_stats` | `-` | `%{slice: :api_map_reads, native_api: true}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R051 | `GET` | `/api/v1/points/tracked_months` | `DawarichWeb.Api.SpatialController :tracked_months` | `api_stats` | `-` | `%{slice: :api_map_reads, native_api: true}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R052 | `GET` | `/api/v1/maps/hexagons/fog` | `DawarichWeb.Api.HexagonsController :fog` | `api_stats` | `-` | `%{slice: :api_map_reads, native_api: true}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R053 | `GET` | `/api/v1/maps/hexagons/bounds` | `DawarichWeb.Api.HexagonsController :bounds` | `api_spatial_grants` | `-` | `%{slice: :api_map_reads, native_api: true}` | P:api_spatial_grants; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R054 | `GET` | `/api/v1/maps/hexagons` | `DawarichWeb.Api.HexagonsController :index` | `api_spatial_grants` | `-` | `%{slice: :api_map_reads, native_api: true}` | P:api_spatial_grants; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R055 | `GET` | `/api/v1/tiles/points/:z/:x/:y` | `DawarichWeb.Api.PointTilesController :show` | `api_tiles` | `-` | `%{slice: :api_map_reads, native_api: true}` | P:api_tiles; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R056 | `GET` | `/api/v1/tiles/tracks/:z/:x/:y` | `DawarichWeb.Api.TrackTilesController :show` | `api_tiles` | `-` | `%{slice: :api_map_reads, native_api: true}` | P:api_tiles; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R057 | `GET` | `/api/v1/mcp` | `DawarichWeb.Api.McpController :handle` | `api_transport` | `-` | `%{slice: :api_map_reads, native_api: true}` | P:api_transport; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R058 | `POST` | `/api/v1/mcp` | `DawarichWeb.Api.McpController :handle` | `api_transport` | `-` | `%{slice: :api_map_reads, native_api: true}` | P:api_transport; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R059 | `DELETE` | `/api/v1/mcp` | `DawarichWeb.Api.McpController :handle` | `api_transport` | `-` | `%{slice: :api_map_reads, native_api: true}` | P:api_transport; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R060 | `GET` | `/api/v1/stats` | `DawarichWeb.Api.StatsController :index` | `api_stats` | `-` | `%{slice: :api_stats}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R061 | `GET` | `/api/v1/insights` | `DawarichWeb.Api.StatsController :insights` | `api_stats` | `-` | `%{slice: :api_stats}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R062 | `GET` | `/api/v1/insights/details` | `DawarichWeb.Api.StatsController :details` | `api_stats` | `-` | `%{slice: :api_stats}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R063 | `GET` | `/api/v1/residency` | `DawarichWeb.Api.StatsController :residency` | `api_stats` | `-` | `%{slice: :api_stats}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R064 | `GET` | `/api/v1/digests` | `DawarichWeb.Api.DigestsController :closure_index` | `api_stats` | `-` | `%{slice: :api_stats}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R065 | `GET` | `/api/v1/digests/:year` | `DawarichWeb.Api.DigestsController :closure_show` | `api_stats` | `-` | `%{slice: :api_stats}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R066 | `GET` | `/api/v1/countries/visited_cities` | `DawarichWeb.Api.GeoController :visited_cities` | `api_stats` | `-` | `%{slice: :api_stats}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R067 | `GET` | `/api/v1/flights` | `DawarichWeb.Api.GeoController :flights` | `api_stats` | `-` | `%{slice: :api_stats}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R068 | `GET` | `/api/v1/points` | `DawarichWeb.Api.MapController :points` | `api_stats` | `-` | `%{slice: :api_map_reads}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R069 | `GET` | `/api/v1/tracks` | `DawarichWeb.Api.MapController :tracks` | `api_stats` | `-` | `%{slice: :api_map_reads}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R070 | `GET` | `/api/v1/tracks/:id` | `DawarichWeb.Api.MapController :track` | `api_stats` | `-` | `%{slice: :api_map_reads}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R071 | `GET` | `/api/v1/tracks/:track_id/points` | `DawarichWeb.Api.MapController :track_points` | `api_stats` | `-` | `%{slice: :api_map_reads}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R072 | `GET` | `/api/v1/settings` | `DawarichWeb.Api.StandaloneMap :settings` | `api_stats` | `-` | `%{slice: :api_map_reads, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:api_stats; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R073 | `GET` | `/api/v1/settings/transportation_recalculation_status` | `DawarichWeb.Api.StandaloneMap :progress` | `api_stats` | `-` | `%{slice: :api_map_reads, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:api_stats; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R074 | `GET` | `/api/v1/places/nearby` | `DawarichWeb.Api.PlacesController :nearby` | `api_places` | `-` | `%{slice: :api_places, native_api: true}` | P:api_places; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R075 | `GET` | `/api/v1/places/search` | `DawarichWeb.Api.PlacesController :search` | `api_places` | `-` | `%{slice: :api_places, native_api: true}` | P:api_places; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R076 | `GET` | `/api/v1/places` | `DawarichWeb.Api.PlacesController {:closure, :index}` | `api_places` | `-` | `%{slice: :api_places}` | P:api_places; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R077 | `POST` | `/api/v1/places` | `DawarichWeb.Api.PlacesController {:closure, :create}` | `api_places` | `-` | `%{slice: :api_places}` | P:api_places; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R078 | `GET` | `/api/v1/places/:id` | `DawarichWeb.Api.PlacesController {:closure, :show}` | `api_places` | `-` | `%{slice: :api_places}` | P:api_places; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R079 | `PATCH` | `/api/v1/places/:id` | `DawarichWeb.Api.PlacesController {:closure, :update}` | `api_places` | `-` | `%{slice: :api_places}` | P:api_places; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R080 | `PUT` | `/api/v1/places/:id` | `DawarichWeb.Api.PlacesController {:closure, :update}` | `api_places` | `-` | `%{slice: :api_places}` | P:api_places; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R081 | `DELETE` | `/api/v1/places/:id` | `DawarichWeb.Api.PlacesController {:closure, :destroy}` | `api_places` | `-` | `%{slice: :api_places}` | P:api_places; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R082 | `GET` | `/api/v1/families/locations` | `DawarichWeb.Api.FamilyController :locations` | `api_stats` | `-` | `%{slice: :api_family}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R083 | `GET` | `/api/v1/families/locations/history` | `DawarichWeb.Api.FamilyController :history` | `api_stats` | `-` | `%{slice: :api_family}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R084 | `GET` | `/api/v1/families/mine` | `DawarichWeb.Api.FamilyController :mine` | `api_stats` | `-` | `%{slice: :api_family}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R085 | `PATCH` | `/api/v1/families/sharing` | `DawarichWeb.Api.FamilyController :sharing` | `api_stats` | `-` | `%{slice: :api_family}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R086 | `PUT` | `/api/v1/families/sharing` | `DawarichWeb.Api.FamilyController :sharing` | `api_stats` | `-` | `%{slice: :api_family}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R087 | `POST` | `/api/v1/families/location_requests` | `DawarichWeb.Api.FamilyController :create` | `api_stats` | `-` | `%{slice: :api_family}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R088 | `POST` | `/api/v1/families/location_requests/:id/accept` | `DawarichWeb.Api.FamilyController :accept` | `api_stats` | `-` | `%{slice: :api_family}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R089 | `POST` | `/api/v1/families/location_requests/:id/decline` | `DawarichWeb.Api.FamilyController :decline` | `api_stats` | `-` | `%{slice: :api_family}` | P:api_stats; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R090 | `GET` | `/api/v1/photos` | `DawarichWeb.Api.PhotosController :index` | `api_locations_photos` | `-` | `%{slice: :api_locations_photos, native_api: true}` | P:api_locations_photos; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R091 | `GET` | `/api/v1/locations` | `DawarichWeb.Api.LocationsController :index_closure` | `api_locations_photos` | `-` | `%{slice: :api_locations_photos}` | P:api_locations_photos; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R092 | `GET` | `/api/v1/locations/suggestions` | `DawarichWeb.Api.LocationsController :suggestions` | `api_locations_photos` | `-` | `%{slice: :api_locations_photos, native_api: true}` | P:api_locations_photos; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R093 | `GET` | `/api/v1/photos/:id/thumbnail` | `DawarichWeb.Api.PhotosController :thumbnail_closure` | `api_locations_photos` | `-` | `%{slice: :api_locations_photos}` | P:api_locations_photos; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R094 | `GET` | `/api/v1/photos/:id/thumbnail.jpg` | `DawarichWeb.Api.PhotosController :thumbnail_closure` | `api_locations_photos` | `-` | `%{slice: :api_locations_photos}` | P:api_locations_photos; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R095 | `POST` | `/api/v1/immich/enrich/scan` | `DawarichWeb.Api.ImmichController :scan` | `api_locations_photos` | `-` | `%{slice: :api_locations_photos, native_api: true}` | P:api_locations_photos; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R096 | `POST` | `/api/v1/immich/enrich` | `DawarichWeb.Api.ImmichController :create` | `api_locations_photos` | `-` | `%{slice: :api_locations_photos, native_api: true}` | P:api_locations_photos; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R097 | `GET` | `/api/v1/health` | `DawarichWeb.Api.HealthController :index` | `health` | `-` | `%{rails_key: "health"}` | P:health; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R098 | `GET` | `/api/v1/ready` | `DawarichWeb.Api.HealthController :ready` | `health` | `-` | `%{rails_key: "ready"}` | P:health; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R099 | `GET` | `/ready` | `DawarichWeb.Api.HealthController :ready` | `health` | `-` | `%{rails_key: "ready"}` | P:health; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R100 | `GET` | `/sidekiq` | `DawarichWeb.OperatorRedirect []` | `operator,operator_session` | `-` | `%{}` | P:operator; P:operator_session; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R101 | `GET` | `/api-docs` | `DawarichWeb.ApiDocs []` | `operator` | `-` | `%{}` | P:operator; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R102 | `GET` | `/api-docs/index.html` | `DawarichWeb.ApiDocs []` | `operator` | `-` | `%{}` | P:operator; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R103 | `GET` | `/api-docs/v1/swagger.yaml` | `DawarichWeb.ApiDocs []` | `operator` | `-` | `%{}` | P:operator; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R104 | `*` | `/api-docs` | `DawarichWeb.ApiDocs []` | `operator` | `-` | `%{}` | P:operator; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R105 | `*` | `/api-docs/*path` | `DawarichWeb.ApiDocs []` | `operator` | `-` | `%{}` | P:operator; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R106 | `*` | `/admin/flipper` | `DawarichWeb.OperatorRedirect [retired: true]` | `operator` | `-` | `%{retired: true}` | P:operator; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R107 | `*` | `/admin/flipper/*path` | `DawarichWeb.OperatorRedirect [retired: true]` | `operator` | `-` | `%{retired: true}` | P:operator; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R108 | `GET` | `/family/locations.json` | `DawarichWeb.FamilyLocations :show` | `family_data` | `-` | `%{rails_gate: {DawarichWeb.FamilyLocations, :native?}}` | P:family_data; G:DawarichWeb.FamilyLocations.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R109 | `GET` | `/cable` | `DawarichWeb.Cable :upgrade` | `cable` | `-` | `%{slice: :cable}` | P:cable; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R110 | `GET` | `/s/:id` | `DawarichWeb.SharedLinkPage :show` | `sharing` | `-` | `%{rails_gate: {DawarichWeb.SharingGate, :show?}}` | P:sharing; G:DawarichWeb.SharingGate.show?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R111 | `POST` | `/s/:id/unlock` | `DawarichWeb.SharedLinkPage :unlock` | `sharing_unlock` | `-` | `%{rails_gate: {DawarichWeb.SharingGate, :unlock?}}` | P:sharing_unlock; G:DawarichWeb.SharingGate.unlock?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R112 | `PATCH` | `/achievements/:key/toggle_sharing` | `DawarichWeb.AchievementActions.Sharing [action: :sharing]` | `achievement_action` | `-` | `%{rails_gate: {DawarichWeb.AchievementActions.Gate, :sharing?}}` | P:achievement_action; G:DawarichWeb.AchievementActions.Gate.sharing?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R113 | `POST` | `/achievements/:key/toggle_sharing` | `DawarichWeb.AchievementActions.Sharing [action: :sharing]` | `achievement_action` | `-` | `%{rails_gate: {DawarichWeb.AchievementActions.Gate, :sharing?}}` | P:achievement_action; G:DawarichWeb.AchievementActions.Gate.sharing?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R114 | `POST` | `/achievements/unlocks/next` | `DawarichWeb.AchievementActions.Unlocks [action: :next]` | `achievement_action` | `-` | `%{rails_gate: {DawarichWeb.AchievementActions.Gate, :next?}}` | P:achievement_action; G:DawarichWeb.AchievementActions.Gate.next?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R115 | `POST` | `/achievements/unlocks/:id/seen` | `DawarichWeb.AchievementActions.Unlocks [action: :seen]` | `achievement_action` | `-` | `%{rails_gate: {DawarichWeb.AchievementActions.Gate, :seen?}}` | P:achievement_action; G:DawarichWeb.AchievementActions.Gate.seen?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R116 | `POST` | `/achievements/unlocks/dismiss` | `DawarichWeb.AchievementActions.Unlocks [action: :dismiss]` | `achievement_action` | `-` | `%{rails_gate: {DawarichWeb.AchievementActions.Gate, :dismiss?}}` | P:achievement_action; G:DawarichWeb.AchievementActions.Gate.dismiss?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R117 | `GET` | `/shared/achievements/:uuid` | `DawarichWeb.AchievementPublicPage []` | `achievement_public` | `-` | `%{rails_gate: {DawarichWeb.AchievementPublic, :open?}, rails_key: "achievements"}` | P:achievement_public; G:DawarichWeb.AchievementPublic.open?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R118 | `GET` | `/achievements` | `Phoenix.LiveView.Plug :index` | `browser,rails_user,achievement_initial` | `DawarichWeb.AchievementsLive:index@achievement_pages` | `%{rails_gate: {DawarichWeb.AchievementPageGate, :open?}}` | P:browser; P:rails_user; P:achievement_initial; G:DawarichWeb.AchievementPageGate.open?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R119 | `GET` | `/achievements/:key` | `Phoenix.LiveView.Plug :show` | `browser,rails_user,achievement_initial` | `DawarichWeb.AchievementsLive:show@achievement_pages` | `%{rails_gate: {DawarichWeb.AchievementPageGate, :open?}}` | P:browser; P:rails_user; P:achievement_initial; G:DawarichWeb.AchievementPageGate.open?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R120 | `GET` | `/shared/achievements/:uuid/og.png` | `DawarichWeb.AchievementPublicImage []` | `achievement_image` | `-` | `%{rails_key: "achievements"}` | P:achievement_image; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R121 | `POST` | `/imports` | `DawarichWeb.ImportsController :create` | `imports_request` | `-` | `%{}` | P:imports_request; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R122 | `POST` | `/imports/:id` | `DawarichWeb.ImportsController :update` | `imports_request` | `-` | `%{rails_gate: {DawarichWeb.ImportsGate, :native?}}` | P:imports_request; G:DawarichWeb.ImportsGate.native?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R123 | `PATCH` | `/imports/:id` | `DawarichWeb.ImportsController :update` | `imports_request` | `-` | `%{rails_gate: {DawarichWeb.ImportsGate, :native?}}` | P:imports_request; G:DawarichWeb.ImportsGate.native?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R124 | `PUT` | `/imports/:id` | `DawarichWeb.ImportsController :update` | `imports_request` | `-` | `%{rails_gate: {DawarichWeb.ImportsGate, :native?}}` | P:imports_request; G:DawarichWeb.ImportsGate.native?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R125 | `DELETE` | `/imports/:id` | `DawarichWeb.ImportsController :delete` | `imports_request` | `-` | `%{rails_gate: {DawarichWeb.ImportsGate, :native?}}` | P:imports_request; G:DawarichWeb.ImportsGate.native?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R126 | `POST` | `/imports/:id/extraction` | `DawarichWeb.ImportsController :extract` | `imports_request` | `-` | `%{rails_gate: {DawarichWeb.ImportsGate, :native?}}` | P:imports_request; G:DawarichWeb.ImportsGate.native?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R127 | `DELETE` | `/imports/:id/extraction` | `DawarichWeb.ImportsController :remove_extraction` | `imports_request` | `-` | `%{rails_gate: {DawarichWeb.ImportsGate, :native?}}` | P:imports_request; G:DawarichWeb.ImportsGate.native?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R128 | `DELETE` | `/exports/:id` | `DawarichWeb.ExportsDelete :delete` | `exports_delete` | `-` | `%{}` | P:exports_delete; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R129 | `POST` | `/exports/:id` | `DawarichWeb.ExportsDelete :delete` | `exports_delete` | `-` | `%{}` | P:exports_delete; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R130 | `POST` | `/exports` | `DawarichWeb.ExportsCreate :create` | `exports_create` | `-` | `%{}` | P:exports_create; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R131 | `POST` | `/tracks/recalculation` | `DawarichWeb.TrackRecalculationActions :create` | `map_write` | `-` | `%{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}` | P:map_write; G:DawarichWeb.MapWriteGate.owned?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R132 | `POST` | `/areas` | `DawarichWeb.AreaActions :create` | `map_write` | `-` | `%{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}` | P:map_write; G:DawarichWeb.MapWriteGate.owned?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R133 | `PATCH` | `/areas/:id` | `DawarichWeb.AreaActions :update` | `map_write` | `-` | `%{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}` | P:map_write; G:DawarichWeb.MapWriteGate.owned?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R134 | `PUT` | `/areas/:id` | `DawarichWeb.AreaActions :update` | `map_write` | `-` | `%{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}` | P:map_write; G:DawarichWeb.MapWriteGate.owned?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R135 | `POST` | `/areas/:id` | `DawarichWeb.AreaActions :update` | `map_write` | `-` | `%{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}` | P:map_write; G:DawarichWeb.MapWriteGate.owned?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R136 | `DELETE` | `/points/bulk_destroy` | `DawarichWeb.PointListActions :destroy` | `map_write` | `-` | `%{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}` | P:map_write; G:DawarichWeb.MapWriteGate.owned?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R137 | `POST` | `/points/bulk_destroy` | `DawarichWeb.PointListActions :destroy` | `map_write` | `-` | `%{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}` | P:map_write; G:DawarichWeb.MapWriteGate.owned?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R138 | `GET` | `/insights/details` | `Phoenix.LiveView.Plug :index` | `insights` | `DawarichWeb.InsightsLive.Details:index@insights_details` | `%{rails_gate: {DawarichWeb.InsightsGate, :owned?}}` | P:insights; G:DawarichWeb.InsightsGate.owned?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R139 | `GET` | `/recede_historical_location` | `DawarichWeb.PageEnvelope :navigation` | `native_navigation` | `-` | `%{rails_gate: {DawarichWeb.PageEnvelope, :navigation?}}` | P:native_navigation; G:DawarichWeb.PageEnvelope.navigation?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R140 | `GET` | `/resume_historical_location` | `DawarichWeb.PageEnvelope :navigation` | `native_navigation` | `-` | `%{rails_gate: {DawarichWeb.PageEnvelope, :navigation?}}` | P:native_navigation; G:DawarichWeb.PageEnvelope.navigation?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R141 | `GET` | `/refresh_historical_location` | `DawarichWeb.PageEnvelope :navigation` | `native_navigation` | `-` | `%{rails_gate: {DawarichWeb.PageEnvelope, :navigation?}}` | P:native_navigation; G:DawarichWeb.PageEnvelope.navigation?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R142 | `GET` | `/imports/:id/download` | `DawarichWeb.ImportsDownload :show` | `browser,rails_user` | `-` | `%{rails_gate: {DawarichWeb.ImportsGate, :native?}}` | P:browser; P:rails_user; G:DawarichWeb.ImportsGate.native?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R143 | `GET` | `/tags` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.TagsLive.Index:index@native_pages` | `%{}` | P:browser; P:rails_user; C/U | 3a native delivered; 7 shared cleanup | native delivered in current tree; retained behavior; shared cleanup pending |
| R144 | `GET` | `/tags/new` | `Phoenix.LiveView.Plug :new` | `browser,rails_user` | `DawarichWeb.TagsLive.Form:new@native_pages` | `%{}` | P:browser; P:rails_user; C/U | 3a native delivered; 7 shared cleanup | native delivered in current tree; retained behavior; shared cleanup pending |
| R145 | `GET` | `/tags/:id/edit` | `Phoenix.LiveView.Plug :edit` | `browser,rails_user` | `DawarichWeb.TagsLive.Form:edit@native_pages` | `%{}` | P:browser; P:rails_user; C/U | 3a native delivered; 7 shared cleanup | native delivered in current tree; retained behavior; shared cleanup pending |
| R146 | `GET` | `/settings/general` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.SettingsLive.General:index@native_pages` | `%{}` | P:browser; P:rails_user; C/U | 3a native delivered; 7 shared cleanup | native delivered in current tree; retained behavior; shared cleanup pending |
| R147 | `GET` | `/settings/visits` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.SettingsLive.Visits:index@native_pages` | `%{}` | P:browser; P:rails_user; C/U | 3a native delivered; 7 shared cleanup | native delivered in current tree; retained behavior; shared cleanup pending |
| R148 | `GET` | `/settings/integrations` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.SettingsLive.Integrations:index@native_pages` | `%{}` | P:browser; P:rails_user; C/U | 3a native delivered; 7 shared cleanup | native delivered in current tree; retained behavior; shared cleanup pending |
| R149 | `GET` | `/settings/trek_sources/:id/select_trips` | `Phoenix.LiveView.Plug :select_trips` | `browser,rails_user` | `DawarichWeb.SettingsLive.TrekTrips:select_trips@native_pages` | `%{}` | P:browser; P:rails_user; C/U | 3a native delivered; 7 shared cleanup | native delivered in current tree; retained behavior; shared cleanup pending |
| R150 | `GET` | `/users/edit` | `Phoenix.LiveView.Plug :edit` | `browser,rails_user` | `DawarichWeb.AccountLive.Edit:edit@native_pages` | `%{}` | P:browser; P:rails_user; C/U | 3a native delivered; 7 shared cleanup | native delivered in current tree; retained behavior; shared cleanup pending |
| R151 | `GET` | `/notifications` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.NotificationsLive.Index:index@rails_pages` | `%{}` | P:browser; P:rails_user; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R152 | `GET` | `/notifications/:id` | `Phoenix.LiveView.Plug :show` | `browser,rails_user` | `DawarichWeb.NotificationsLive.Show:show@rails_pages` | `%{}` | P:browser; P:rails_user; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R153 | `GET` | `/imports/new` | `Phoenix.LiveView.Plug :new` | `browser,rails_user` | `DawarichWeb.ImportsLive.New:new@rails_pages` | `%{}` | P:browser; P:rails_user; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R154 | `GET` | `/imports/:id` | `Phoenix.LiveView.Plug :show` | `browser,rails_user` | `DawarichWeb.ImportsLive.Show:show@rails_pages` | `%{rails_gate: {DawarichWeb.ImportsGate, :native?}}` | P:browser; P:rails_user; G:DawarichWeb.ImportsGate.native?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R155 | `GET` | `/imports/:id/edit` | `Phoenix.LiveView.Plug :edit` | `browser,rails_user` | `DawarichWeb.ImportsLive.Edit:edit@rails_pages` | `%{rails_gate: {DawarichWeb.ImportsGate, :native?}}` | P:browser; P:rails_user; G:DawarichWeb.ImportsGate.native?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R156 | `GET` | `/imports` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.ImportsLive.Index:index@rails_pages` | `%{}` | P:browser; P:rails_user; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R157 | `GET` | `/exports` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.ExportsLive.Index:index@rails_pages` | `%{}` | P:browser; P:rails_user; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R158 | `GET` | `/stats` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.StatsLive.Index:index@rails_pages` | `%{}` | P:browser; P:rails_user; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R159 | `GET` | `/stats/:year` | `Phoenix.LiveView.Plug :show` | `browser,rails_user` | `DawarichWeb.StatsLive.Year:show@rails_pages` | `%{}` | P:browser; P:rails_user; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R160 | `GET` | `/stats/:year/:month` | `Phoenix.LiveView.Plug :month` | `browser,rails_user` | `DawarichWeb.StatsLive.Month:month@rails_pages` | `%{}` | P:browser; P:rails_user; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R161 | `GET` | `/digests` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.DigestsLive.Index:index@rails_pages` | `%{}` | P:browser; P:rails_user; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R162 | `GET` | `/digests/:year` | `Phoenix.LiveView.Plug :show` | `browser,rails_user` | `DawarichWeb.DigestsLive.Show:show@rails_pages` | `%{}` | P:browser; P:rails_user; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R163 | `GET` | `/trips` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.TripsLive.Index:index@rails_pages` | `%{rails_gate: {DawarichWeb.TripsGate, :index?}}` | P:browser; P:rails_user; G:DawarichWeb.TripsGate.index?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R164 | `GET` | `/trips/new` | `Phoenix.LiveView.Plug :new` | `browser,rails_user` | `DawarichWeb.TripsLive.Form:new@rails_pages` | `%{rails_gate: {DawarichWeb.TripsGate, :form?}}` | P:browser; P:rails_user; G:DawarichWeb.TripsGate.form?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R165 | `GET` | `/trips/:id/edit` | `Phoenix.LiveView.Plug :edit` | `browser,rails_user` | `DawarichWeb.TripsLive.Form:edit@rails_pages` | `%{rails_gate: {DawarichWeb.TripsGate, :form?}}` | P:browser; P:rails_user; G:DawarichWeb.TripsGate.form?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R166 | `GET` | `/trips/:id` | `Phoenix.LiveView.Plug :show` | `browser,rails_user` | `DawarichWeb.TripsLive.Show:show@rails_pages` | `%{rails_gate: {DawarichWeb.TripsGate, :show?}}` | P:browser; P:rails_user; G:DawarichWeb.TripsGate.show?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R167 | `GET` | `/places` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.PlacesLive.Index:index@rails_pages` | `%{rails_gate: {DawarichWeb.PlacesGate, :index?}}` | P:browser; P:rails_user; G:DawarichWeb.PlacesGate.index?; C/U | 3d/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R168 | `GET` | `/points` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.PointsLive.Index:index@rails_pages` | `%{rails_gate: {DawarichWeb.MapDataGate, :points?}}` | P:browser; P:rails_user; G:DawarichWeb.MapDataGate.points?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R169 | `GET` | `/insights` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.InsightsLive.Index:index@rails_pages` | `%{}` | P:browser; P:rails_user; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R170 | `GET` | `/map/v1` | `DawarichWeb.MapRedirects :legacy` | `map_redirect` | `-` | `%{rails_key: "map"}` | P:map_redirect; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R171 | `GET` | `/map/v1.:format` | `DawarichWeb.MapRedirects :legacy` | `map_redirect` | `-` | `%{rails_key: "map"}` | P:map_redirect; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R172 | `GET` | `/maps/v2` | `DawarichWeb.MapRedirects :plural` | `map_redirect` | `-` | `%{rails_key: "map"}` | P:map_redirect; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R173 | `GET` | `/maps/v2.:format` | `DawarichWeb.MapRedirects :plural` | `map_redirect` | `-` | `%{rails_key: "map"}` | P:map_redirect; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R174 | `GET` | `/map` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.MapLive:index@rails_map` | `%{}` | P:browser; P:rails_user; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R175 | `GET` | `/map/v2` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.MapLive:index@rails_map` | `%{}` | P:browser; P:rails_user; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R176 | `PUT` | `/stats/:year/:month/update` | `DawarichWeb.StatsActions :update` | `stats_request` | `-` | `%{}` | P:stats_request; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R177 | `PUT` | `/stats/update_all` | `DawarichWeb.StatsActions :update_all` | `stats_request` | `-` | `%{}` | P:stats_request; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R178 | `POST` | `/stats/:year/:month/update` | `DawarichWeb.StatsActions :update` | `stats_request` | `-` | `%{}` | P:stats_request; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R179 | `POST` | `/stats/update_all` | `DawarichWeb.StatsActions :update_all` | `stats_request` | `-` | `%{}` | P:stats_request; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R180 | `GET` | `/family/invitations/new` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R181 | `GET` | `/family/invitations/new.:format` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R182 | `POST` | `/family/invitations` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R183 | `POST` | `/family/invitations.:format` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R184 | `POST` | `/family/invitations/:id` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R185 | `DELETE` | `/family/invitations/:id` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R186 | `POST` | `/family/memberships` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R187 | `POST` | `/family/memberships.:format` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R188 | `POST` | `/family/location_requests` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R189 | `POST` | `/family/location_requests.:format` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R190 | `POST` | `/family/location_requests/:id/accept` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R191 | `POST` | `/family/location_requests/:id/accept.:format` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R192 | `PATCH` | `/family/location_requests/:id/accept` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R193 | `PATCH` | `/family/location_requests/:id/accept.:format` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R194 | `POST` | `/family/location_requests/:id/decline` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R195 | `POST` | `/family/location_requests/:id/decline.:format` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R196 | `PATCH` | `/family/location_requests/:id/decline` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R197 | `PATCH` | `/family/location_requests/:id/decline.:format` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R198 | `POST` | `/family/location_sharing` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R199 | `POST` | `/family/location_sharing.:format` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R200 | `PATCH` | `/family/location_sharing` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R201 | `PATCH` | `/family/location_sharing.:format` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R202 | `POST` | `/family` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R203 | `POST` | `/family.:format` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R204 | `PATCH` | `/family` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R205 | `PATCH` | `/family.:format` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R206 | `PUT` | `/family` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R207 | `PUT` | `/family.:format` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R208 | `DELETE` | `/family` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R209 | `DELETE` | `/family.:format` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R210 | `POST` | `/family/members/:id` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R211 | `DELETE` | `/family/members/:id` | `DawarichWeb.FamilyFormRoutes :dispatch` | `family_form` | `-` | `%{}` | P:family_form; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R212 | `GET` | `/family` | `Phoenix.LiveView.Plug :show` | `browser,rails_user` | `DawarichWeb.FamiliesLive.Show:show@family_pages` | `%{rails_gate: {DawarichWeb.FamilyGate, :show?}}` | P:browser; P:rails_user; G:DawarichWeb.FamilyGate.show?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R213 | `GET` | `/family/new` | `Phoenix.LiveView.Plug :new` | `browser,rails_user` | `DawarichWeb.FamiliesLive.Form:new@family_pages` | `%{rails_gate: {DawarichWeb.FamilyGate, :new?}}` | P:browser; P:rails_user; G:DawarichWeb.FamilyGate.new?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R214 | `GET` | `/family/edit` | `Phoenix.LiveView.Plug :edit` | `browser,rails_user` | `DawarichWeb.FamiliesLive.Form:edit@family_pages` | `%{rails_gate: {DawarichWeb.FamilyGate, :edit?}}` | P:browser; P:rails_user; G:DawarichWeb.FamilyGate.edit?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R215 | `GET` | `/family/invitations` | `Phoenix.LiveView.Plug :index` | `browser,rails_user` | `DawarichWeb.FamiliesLive.Invitations:index@family_pages` | `%{rails_gate: {DawarichWeb.FamilyGate, :invitations?}}` | P:browser; P:rails_user; G:DawarichWeb.FamilyGate.invitations?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R216 | `GET` | `/family/location_requests/:id` | `Phoenix.LiveView.Plug :show` | `browser,rails_user` | `DawarichWeb.FamiliesLive.LocationRequest:show@family_pages` | `%{rails_gate: {DawarichWeb.FamilyGate, :request?}}` | P:browser; P:rails_user; G:DawarichWeb.FamilyGate.request?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R217 | `GET` | `/invitations/:token` | `DawarichWeb.FamilyInvitationPage :show` | `sharing` | `-` | `%{rails_gate: {DawarichWeb.FamilyInvitationPage, :native?}}` | P:sharing; G:DawarichWeb.FamilyInvitationPage.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R218 | `GET` | `/family/invitations/:token` | `DawarichWeb.FamilyInvitationPage :show` | `sharing` | `-` | `%{rails_gate: {DawarichWeb.FamilyInvitationPage, :native?}}` | P:sharing; G:DawarichWeb.FamilyInvitationPage.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R219 | `POST` | `/rails/active_storage/direct_uploads` | `DawarichWeb.StorageRoutes :direct_upload` | `storage_upload` | `-` | `%{rails_gate: {DawarichWeb.StorageGate, :native?}, rails_key: "active_storage"}` | P:storage_upload; G:DawarichWeb.StorageGate.native?; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R220 | `PUT` | `/rails/active_storage/disk/:encoded_token` | `DawarichWeb.StorageRoutes :disk_update` | `storage_public` | `-` | `%{rails_gate: {DawarichWeb.StorageGate, :native?}, rails_key: "active_storage"}` | P:storage_public; G:DawarichWeb.StorageGate.native?; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R221 | `GET` | `/rails/active_storage/disk/:encoded_key/*filename` | `DawarichWeb.StorageRoutes :disk` | `storage_public` | `-` | `%{rails_gate: {DawarichWeb.StorageGate, :native?}, rails_key: "active_storage"}` | P:storage_public; G:DawarichWeb.StorageGate.native?; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R222 | `GET` | `/rails/active_storage/blobs/proxy/:signed_id/*filename` | `DawarichWeb.StorageRoutes :proxy` | `storage_public` | `-` | `%{rails_gate: {DawarichWeb.StorageGate, :native?}, rails_key: "active_storage"}` | P:storage_public; G:DawarichWeb.StorageGate.native?; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R223 | `GET` | `/rails/active_storage/representations/proxy/:signed_blob_id/:variation_key/*filename` | `DawarichWeb.StorageRoutes {:representation, :proxy}` | `storage_public` | `-` | `%{rails_gate: {DawarichWeb.StorageGate, :native?}, rails_key: "active_storage"}` | P:storage_public; G:DawarichWeb.StorageGate.native?; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R224 | `GET` | `/rails/active_storage/representations/redirect/:signed_blob_id/:variation_key/*filename` | `DawarichWeb.StorageRoutes {:representation, :redirect}` | `storage_public` | `-` | `%{rails_gate: {DawarichWeb.StorageGate, :native?}, rails_key: "active_storage"}` | P:storage_public; G:DawarichWeb.StorageGate.native?; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R225 | `GET` | `/rails/active_storage/representations/:signed_blob_id/:variation_key/*filename` | `DawarichWeb.StorageRoutes {:representation, :redirect}` | `storage_public` | `-` | `%{rails_gate: {DawarichWeb.StorageGate, :native?}, rails_key: "active_storage"}` | P:storage_public; G:DawarichWeb.StorageGate.native?; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R226 | `GET` | `/rails/active_storage/blobs/redirect/:signed_id/*filename` | `DawarichWeb.StorageRoutes :redirect` | `storage_public` | `-` | `%{rails_gate: {DawarichWeb.StorageGate, :native?}, rails_key: "active_storage"}` | P:storage_public; G:DawarichWeb.StorageGate.native?; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R227 | `GET` | `/rails/active_storage/blobs/:signed_id/*filename` | `DawarichWeb.StorageRoutes :redirect` | `storage_public` | `-` | `%{rails_gate: {DawarichWeb.StorageGate, :native?}, rails_key: "active_storage"}` | P:storage_public; G:DawarichWeb.StorageGate.native?; C/U | retain protocol; 7 B1/B2/B3 | retained protocol; ownership removal pending |
| R228 | `POST` | `/digests` | `DawarichWeb.DigestActions :create` | `digest_request` | `-` | `%{}` | P:digest_request; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R229 | `DELETE` | `/digests/:year` | `DawarichWeb.DigestActions :destroy` | `digest_request` | `-` | `%{}` | P:digest_request; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R230 | `POST` | `/digests/:year` | `DawarichWeb.DigestActions :destroy` | `digest_request` | `-` | `%{}` | P:digest_request; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R231 | `POST` | `/settings/background_jobs` | `DawarichWeb.IntegrationJobActions :create` | `integration_jobs` | `-` | `%{rails_gate: {DawarichWeb.IntegrationJobActions, :enabled?}}` | P:integration_jobs; G:DawarichWeb.IntegrationJobActions.enabled?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R232 | `GET` | `/admin/settings` | `Phoenix.LiveView.Plug :show` | `browser,rails_user,admin_page` | `DawarichWeb.AdminLive.Instance:show@native_admin` | `%{}` | P:browser; P:rails_user; P:admin_page; C/U | 3b native delivered; 7 B2/B3 | native delivered in current tree; retained behavior; shared cleanup pending |
| R233 | `GET` | `/settings/users/:id/edit` | `Phoenix.LiveView.Plug :edit` | `browser,rails_user,admin_page` | `DawarichWeb.SettingsLive.UserEdit:edit@native_admin` | `%{}` | P:browser; P:rails_user; P:admin_page; C/U | 3b native delivered; 7 B2/B3 | native delivered in current tree; retained behavior; shared cleanup pending |
| R234 | `GET` | `/settings/users/:id` | `Phoenix.LiveView.Plug :show` | `browser,rails_user,admin_page` | `DawarichWeb.SettingsLive.UserShow:show@native_admin` | `%{}` | P:browser; P:rails_user; P:admin_page; C/U | 3b native delivered; 7 B2/B3 | native delivered in current tree; retained behavior; shared cleanup pending |
| R235 | `GET` | `/settings/users` | `Phoenix.LiveView.Plug :index` | `browser,rails_user,admin_page` | `DawarichWeb.SettingsLive.UsersIndex:index@native_admin` | `%{}` | P:browser; P:rails_user; P:admin_page; C/U | 3b native delivered; 7 B2/B3 | native delivered in current tree; retained behavior; shared cleanup pending |
| R236 | `GET` | `/settings/background_jobs` | `Phoenix.LiveView.Plug :index` | `browser,rails_user,background_operator` | `DawarichWeb.SettingsLive.BackgroundJobs:index@native_background` | `%{rails_gate: {DawarichWeb.AdminGate, :background_route?}}` | P:browser; P:rails_user; P:background_operator; G:DawarichWeb.AdminGate.background_route?; C/U | 3b native delivered / 4 shared HTTP; 7 B2/B3 | native delivered in current tree; retained behavior; shared cleanup pending |
| R237 | `GET` | `/` | `DawarichWeb.HomeDispatch []` | `public_home` | `-` | `%{rails_gate: {DawarichWeb.HomeGate, :owned?}}` | P:public_home; G:DawarichWeb.HomeGate.owned?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R238 | `GET` | `/trial/welcome` | `DawarichWeb.TrialWelcome []` | `trial_welcome` | `-` | `%{rails_gate: {DawarichWeb.WelcomeGate, :owned?}}` | P:trial_welcome; G:DawarichWeb.WelcomeGate.owned?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R239 | `GET` | `/trial/upgrade` | `DawarichWeb.TrialUpgrade []` | `rails_frame` | `-` | `%{rails_gate: {DawarichWeb.TrialGate, :upgrade?}}` | P:rails_frame; G:DawarichWeb.TrialGate.upgrade?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R240 | `GET` | `/trial/resume` | `Phoenix.LiveView.Plug :show` | `trial_resume` | `DawarichWeb.TrialLive.Resume:show@trial_resume` | `%{rails_gate: {DawarichWeb.TrialGate, :resume?}}` | P:trial_resume; G:DawarichWeb.TrialGate.resume?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R241 | `GET` | `/settings/theme` | `DawarichWeb.SettingsMiscActions :theme` | `standalone_settings` | `-` | `%{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}` | P:standalone_settings; G:DawarichWeb.SettingsActions.enabled?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R242 | `PATCH` | `/settings/changelog_consent` | `DawarichWeb.SettingsMiscActions :changelog_consent` | `standalone_settings` | `-` | `%{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}` | P:standalone_settings; G:DawarichWeb.SettingsActions.enabled?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R243 | `POST` | `/settings/changelog_consent` | `DawarichWeb.SettingsMiscActions :changelog_consent` | `standalone_settings` | `-` | `%{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}` | P:standalone_settings; G:DawarichWeb.SettingsActions.enabled?; C/U | 3c–6 shell; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R244 | `POST` | `/settings/onboarding` | `DawarichWeb.OnboardingActions :update` | `standalone_settings` | `-` | `%{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}` | P:standalone_settings; G:DawarichWeb.SettingsActions.enabled?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R245 | `PATCH` | `/settings/onboarding` | `DawarichWeb.OnboardingActions :update` | `standalone_settings` | `-` | `%{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}` | P:standalone_settings; G:DawarichWeb.SettingsActions.enabled?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R246 | `PUT` | `/settings/onboarding` | `DawarichWeb.OnboardingActions :update` | `standalone_settings` | `-` | `%{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}` | P:standalone_settings; G:DawarichWeb.SettingsActions.enabled?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R247 | `POST` | `/settings/onboarding/demo_data` | `DawarichWeb.DemoDataActions :demo_data` | `standalone_settings` | `-` | `%{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}` | P:standalone_settings; G:DawarichWeb.SettingsActions.enabled?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R248 | `DELETE` | `/settings/onboarding/demo_data` | `DawarichWeb.DemoDataActions :demo_data` | `standalone_settings` | `-` | `%{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}` | P:standalone_settings; G:DawarichWeb.SettingsActions.enabled?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R249 | `POST` | `/notifications/mark_as_read` | `DawarichWeb.NotificationActions :mark_as_read` | `standalone_settings` | `-` | `%{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}` | P:standalone_settings; G:DawarichWeb.SettingsActions.enabled?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R250 | `POST` | `/notifications/destroy_all` | `DawarichWeb.NotificationActions :destroy_all` | `standalone_settings` | `-` | `%{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}` | P:standalone_settings; G:DawarichWeb.SettingsActions.enabled?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R251 | `DELETE` | `/notifications/:id` | `DawarichWeb.NotificationActions :destroy` | `standalone_settings` | `-` | `%{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}` | P:standalone_settings; G:DawarichWeb.SettingsActions.enabled?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R252 | `POST` | `/notifications/:id` | `DawarichWeb.NotificationActions :destroy` | `standalone_settings` | `-` | `%{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}` | P:standalone_settings; G:DawarichWeb.SettingsActions.enabled?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R253 | `PATCH` | `/digests/:year/sharing` | `DawarichWeb.DigestSharing :update` | `stats_sharing` | `-` | `%{}` | P:stats_sharing; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R254 | `PATCH` | `/stats/:year/:month/sharing` | `DawarichWeb.StatSharing :update` | `stats_sharing` | `-` | `%{}` | P:stats_sharing; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R255 | `POST` | `/digests/:year/sharing` | `DawarichWeb.DigestSharing :update` | `stats_sharing` | `-` | `%{}` | P:stats_sharing; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R256 | `POST` | `/stats/:year/:month/sharing` | `DawarichWeb.StatSharing :update` | `stats_sharing` | `-` | `%{}` | P:stats_sharing; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R257 | `GET` | `/shared/digest/:uuid` | `DawarichWeb.SharedStatsPage :digest` | `sharing` | `-` | `%{rails_key: "shared"}` | P:sharing; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R258 | `GET` | `/shared/month/:uuid` | `DawarichWeb.SharedStatsPage :month` | `sharing` | `-` | `%{rails_key: "shared"}` | P:sharing; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R259 | `PATCH` | `/tracks/:track_id/segments/:id` | `DawarichWeb.SegmentActions :update` | `map_write` | `-` | `%{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}` | P:map_write; G:DawarichWeb.MapWriteGate.owned?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R260 | `PUT` | `/tracks/:track_id/segments/:id` | `DawarichWeb.SegmentActions :update` | `map_write` | `-` | `%{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}` | P:map_write; G:DawarichWeb.MapWriteGate.owned?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R261 | `POST` | `/tracks/:track_id/segments/:id` | `DawarichWeb.SegmentActions :update` | `map_write` | `-` | `%{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}` | P:map_write; G:DawarichWeb.MapWriteGate.owned?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R262 | `GET` | `/map/timeline_feeds` | `DawarichWeb.MapFrames :index` | `rails_frame` | `-` | `%{rails_gate: {DawarichWeb.MapFramesGate, :feed?}}` | P:rails_frame; G:DawarichWeb.MapFramesGate.feed?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R263 | `GET` | `/map/timeline_feeds/calendar` | `DawarichWeb.MapFrames :calendar` | `rails_frame` | `-` | `%{rails_gate: {DawarichWeb.MapFramesGate, :calendar?}}` | P:rails_frame; G:DawarichWeb.MapFramesGate.calendar?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R264 | `GET` | `/map/residency` | `DawarichWeb.MapFrames :residency` | `rails_frame` | `-` | `%{rails_gate: {DawarichWeb.MapFramesGate, :residency?}}` | P:rails_frame; G:DawarichWeb.MapFramesGate.residency?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R265 | `GET` | `/map/timeline_feeds/:id/track_info` | `DawarichWeb.MapFrames :track_info` | `rails_frame` | `-` | `%{rails_gate: {DawarichWeb.MapFramesGate, :track?}}` | P:rails_frame; G:DawarichWeb.MapFramesGate.track?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R266 | `GET` | `/places/nearby` | `DawarichWeb.PlaceNavigation :nearby` | `rails_frame` | `-` | `%{rails_gate: {DawarichWeb.PlacesGate, :nearby?}}` | P:rails_frame; G:DawarichWeb.PlacesGate.nearby?; C/U | 3d/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R267 | `GET` | `/places/:id` | `DawarichWeb.PlaceNavigation :show` | `rails_frame` | `-` | `%{rails_gate: {DawarichWeb.PlacesGate, :navigation?}}` | P:rails_frame; G:DawarichWeb.PlacesGate.navigation?; C/U | 3d/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R268 | `GET` | `/tracks/:track_id/segments` | `DawarichWeb.MapFrames :segments` | `rails_frame` | `-` | `%{rails_gate: {DawarichWeb.MapDataGate, :segments?}}` | P:rails_frame; G:DawarichWeb.MapDataGate.segments?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R269 | `GET` | `/points/:id/address` | `DawarichWeb.PointAddress :address` | `rails_frame` | `-` | `%{rails_gate: {DawarichWeb.MapDataGate, :point_address?}}` | P:rails_frame; G:DawarichWeb.MapDataGate.point_address?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R270 | `POST` | `/trips/:trip_id/notes` | `DawarichWeb.TripNoteActions :create` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R271 | `PATCH` | `/trips/:trip_id/notes/:id` | `DawarichWeb.TripNoteActions :update` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R272 | `PUT` | `/trips/:trip_id/notes/:id` | `DawarichWeb.TripNoteActions :update` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R273 | `DELETE` | `/trips/:trip_id/notes/:id` | `DawarichWeb.TripNoteActions :destroy` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R274 | `POST` | `/trips/:trip_id/notes/:id` | `DawarichWeb.TripNoteActions :member` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R275 | `POST` | `/trips` | `DawarichWeb.TripActions :create` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R276 | `POST` | `/trips/:id/recalculate` | `DawarichWeb.TripActions :recalculate` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R277 | `POST` | `/trips/:id/export` | `DawarichWeb.TripActions :export` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 4; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R278 | `PATCH` | `/trips/:id` | `DawarichWeb.TripActions :update` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R279 | `PUT` | `/trips/:id` | `DawarichWeb.TripActions :update` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R280 | `DELETE` | `/trips/:id` | `DawarichWeb.TripActions :destroy` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R281 | `POST` | `/trips/:id` | `DawarichWeb.TripActions :member` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R282 | `POST` | `/places` | `DawarichWeb.PlaceActions :create` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 3d/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R283 | `PATCH` | `/places/:id` | `DawarichWeb.PlaceActions :update` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 3d/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R284 | `PUT` | `/places/:id` | `DawarichWeb.PlaceActions :update` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 3d/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R285 | `DELETE` | `/places/:id` | `DawarichWeb.PlaceActions :destroy` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 3d/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R286 | `POST` | `/places/:id` | `DawarichWeb.PlaceActions :member` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 3d/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R287 | `POST` | `/route_videos` | `DawarichWeb.RouteVideoActions :create` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R288 | `DELETE` | `/route_videos/:id` | `DawarichWeb.RouteVideoActions :destroy` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R289 | `POST` | `/route_videos/:id` | `DawarichWeb.RouteVideoActions :destroy` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R290 | `PATCH` | `/visits/bulk_update` | `DawarichWeb.VisitActions :bulk_update` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R291 | `POST` | `/visits/bulk_update` | `DawarichWeb.VisitActions :bulk_update` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R292 | `DELETE` | `/visits/bulk_destroy` | `DawarichWeb.VisitActions :bulk_destroy` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R293 | `POST` | `/visits/bulk_destroy` | `DawarichWeb.VisitActions :bulk_destroy` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R294 | `POST` | `/visits/merge` | `DawarichWeb.VisitActions :merge` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R295 | `PATCH` | `/visits/:id` | `DawarichWeb.VisitActions :update` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R296 | `PUT` | `/visits/:id` | `DawarichWeb.VisitActions :update` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R297 | `DELETE` | `/visits/:id` | `DawarichWeb.VisitActions :destroy` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R298 | `POST` | `/visits/:id` | `DawarichWeb.VisitActions :member` | `a8_action` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :actions?}}` | P:a8_action; G:DawarichWeb.A8Gate.actions?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R299 | `GET` | `/visits` | `DawarichWeb.VisitsNavigation :index` | `a8_public` | `-` | `%{rails_gate: {DawarichWeb.A8Gate, :navigation?}}` | P:a8_public; G:DawarichWeb.A8Gate.navigation?; C/U | 5/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R300 | `GET` | `/share_links/hub` | `DawarichWeb.ShareManagementPage :hub` | `rails_frame` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :native?}}` | P:rails_frame; G:DawarichWeb.ShareManagementGate.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R301 | `GET` | `/share_links/live/new` | `DawarichWeb.ShareManagementPage :live` | `rails_frame` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :native?}}` | P:rails_frame; G:DawarichWeb.ShareManagementGate.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R302 | `GET` | `/trips/:trip_id/share_link/new` | `DawarichWeb.ShareManagementPage :trip` | `rails_frame` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :native?}, rails_key: "trip_shares"}` | P:rails_frame; G:DawarichWeb.ShareManagementGate.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R303 | `POST` | `/share_links/live` | `DawarichWeb.ShareManagementForm {"live", :create}` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}, rails_key: nil}` | P:share_form; G:DawarichWeb.ShareManagementGate.mutation?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R304 | `DELETE` | `/share_links/live` | `DawarichWeb.ShareManagementForm {"live", :destroy}` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}, rails_key: nil}` | P:share_form; G:DawarichWeb.ShareManagementGate.mutation?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R305 | `PATCH` | `/share_links/live/revoke` | `DawarichWeb.ShareManagementForm {"live", :revoke}` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}, rails_key: nil}` | P:share_form; G:DawarichWeb.ShareManagementGate.mutation?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R306 | `POST` | `/share_links/live/regenerate` | `DawarichWeb.ShareManagementForm {"live", :regenerate}` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}, rails_key: nil}` | P:share_form; G:DawarichWeb.ShareManagementGate.mutation?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R307 | `POST` | `/share_links/live/regenerate_phrase` | `DawarichWeb.ShareManagementForm {"live", :regenerate_phrase}` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}, rails_key: nil}` | P:share_form; G:DawarichWeb.ShareManagementGate.mutation?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R308 | `POST` | `/trips/:trip_id/share_link` | `DawarichWeb.ShareManagementForm {"trip", :create}` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}, rails_key: "trip_shares"}` | P:share_form; G:DawarichWeb.ShareManagementGate.mutation?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R309 | `DELETE` | `/trips/:trip_id/share_link` | `DawarichWeb.ShareManagementForm {"trip", :destroy}` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}, rails_key: "trip_shares"}` | P:share_form; G:DawarichWeb.ShareManagementGate.mutation?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R310 | `PATCH` | `/trips/:trip_id/share_link/revoke` | `DawarichWeb.ShareManagementForm {"trip", :revoke}` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}, rails_key: "trip_shares"}` | P:share_form; G:DawarichWeb.ShareManagementGate.mutation?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R311 | `POST` | `/trips/:trip_id/share_link/regenerate` | `DawarichWeb.ShareManagementForm {"trip", :regenerate}` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}, rails_key: "trip_shares"}` | P:share_form; G:DawarichWeb.ShareManagementGate.mutation?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R312 | `POST` | `/trips/:trip_id/share_link/regenerate_phrase` | `DawarichWeb.ShareManagementForm {"trip", :regenerate_phrase}` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}, rails_key: "trip_shares"}` | P:share_form; G:DawarichWeb.ShareManagementGate.mutation?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R313 | `PATCH` | `/share_links/shares/:id/revoke` | `DawarichWeb.ShareManagementForm {"shared", :revoke}` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}}` | P:share_form; G:DawarichWeb.ShareManagementGate.mutation?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R314 | `GET` | `/tracks/:track_id/share_link/new` | `DawarichWeb.TrackShareActions :new` | `rails_frame` | `-` | `%{rails_gate: {DawarichWeb.TrackShareActions, :native?}}` | P:rails_frame; G:DawarichWeb.TrackShareActions.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R315 | `POST` | `/tracks/:track_id/share_link` | `DawarichWeb.TrackShareActions :create` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.TrackShareActions, :native?}}` | P:share_form; G:DawarichWeb.TrackShareActions.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R316 | `DELETE` | `/tracks/:track_id/share_link` | `DawarichWeb.TrackShareActions :destroy` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.TrackShareActions, :native?}}` | P:share_form; G:DawarichWeb.TrackShareActions.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R317 | `PATCH` | `/tracks/:track_id/share_link/revoke` | `DawarichWeb.TrackShareActions :revoke` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.TrackShareActions, :native?}}` | P:share_form; G:DawarichWeb.TrackShareActions.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R318 | `POST` | `/tracks/:track_id/share_link/revoke` | `DawarichWeb.TrackShareActions :revoke` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.TrackShareActions, :native?}}` | P:share_form; G:DawarichWeb.TrackShareActions.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R319 | `POST` | `/tracks/:track_id/share_link/regenerate` | `DawarichWeb.TrackShareActions :regenerate` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.TrackShareActions, :native?}}` | P:share_form; G:DawarichWeb.TrackShareActions.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R320 | `POST` | `/tracks/:track_id/share_link/regenerate_phrase` | `DawarichWeb.TrackShareActions :regenerate_phrase` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.TrackShareActions, :native?}}` | P:share_form; G:DawarichWeb.TrackShareActions.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R321 | `GET` | `/share_links/timeline/new` | `DawarichWeb.TimelineShareActions :new` | `rails_frame` | `-` | `%{rails_gate: {DawarichWeb.TimelineShareActions, :native?}}` | P:rails_frame; G:DawarichWeb.TimelineShareActions.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R322 | `POST` | `/share_links/timeline` | `DawarichWeb.TimelineShareActions :create` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.TimelineShareActions, :native?}}` | P:share_form; G:DawarichWeb.TimelineShareActions.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R323 | `DELETE` | `/share_links/timeline` | `DawarichWeb.TimelineShareActions :destroy` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.TimelineShareActions, :native?}}` | P:share_form; G:DawarichWeb.TimelineShareActions.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R324 | `PATCH` | `/share_links/timeline/revoke` | `DawarichWeb.TimelineShareActions :revoke` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.TimelineShareActions, :native?}}` | P:share_form; G:DawarichWeb.TimelineShareActions.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R325 | `POST` | `/share_links/timeline/revoke` | `DawarichWeb.TimelineShareActions :revoke` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.TimelineShareActions, :native?}}` | P:share_form; G:DawarichWeb.TimelineShareActions.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R326 | `POST` | `/share_links/timeline/regenerate` | `DawarichWeb.TimelineShareActions :regenerate` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.TimelineShareActions, :native?}}` | P:share_form; G:DawarichWeb.TimelineShareActions.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R327 | `POST` | `/share_links/timeline/regenerate_phrase` | `DawarichWeb.TimelineShareActions :regenerate_phrase` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.TimelineShareActions, :native?}}` | P:share_form; G:DawarichWeb.TimelineShareActions.native?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R328 | `POST` | `/share_links/live/revoke` | `DawarichWeb.ShareManagementForm {"live", :revoke}` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}, rails_key: nil}` | P:share_form; G:DawarichWeb.ShareManagementGate.mutation?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R329 | `POST` | `/trips/:trip_id/share_link/revoke` | `DawarichWeb.ShareManagementForm {"trip", :revoke}` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}, rails_key: "trip_shares"}` | P:share_form; G:DawarichWeb.ShareManagementGate.mutation?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R330 | `POST` | `/share_links/shares/:id/revoke` | `DawarichWeb.ShareManagementForm {"shared", :revoke}` | `share_form` | `-` | `%{rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}, rails_key: nil}` | P:share_form; G:DawarichWeb.ShareManagementGate.mutation?; C/U | 4/6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R331 | `POST` | `/posters` | `DawarichWeb.PostersController :create` | `poster_form` | `-` | `%{rails_gate: {DawarichWeb.PostersGate, :native?}}` | P:poster_form; G:DawarichWeb.PostersGate.native?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R332 | `DELETE` | `/posters/:id` | `DawarichWeb.PostersController :destroy` | `poster_form` | `-` | `%{rails_gate: {DawarichWeb.PostersGate, :native?}}` | P:poster_form; G:DawarichWeb.PostersGate.native?; C/U | 6; 7 B2/B3 | unmerged feature handoff; see D1/E1; no removal |
| R333 | `GET` | `/api/v1/settings/mobile` | `DawarichWeb.Api.MobileSettingsController :show` | `standalone_api` | `-` | `%{slice: :api_standalone, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 3c; 7 B2/B3 | B1 promoted from StandaloneRoutes S02; gate/slice ownership removal pending B3 |
| R334 | `GET` | `/api/v1/areas` | `DawarichWeb.Api.AreasController :index` | `standalone_api` | `-` | `%{slice: :api_standalone, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 6; 7 B2/B3 | B1 promoted from StandaloneRoutes S04; gate/slice ownership removal pending B3 |
| R335 | `POST` | `/api/v1/areas` | `DawarichWeb.Api.AreasController :create` | `standalone_api` | `-` | `%{slice: :api_standalone, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 6; 7 B2/B3 | B1 promoted from StandaloneRoutes S05; gate/slice ownership removal pending B3 |
| R336 | `GET` | `/api/v1/areas/:id` | `DawarichWeb.Api.AreasController :show` | `standalone_api` | `-` | `%{slice: :api_standalone, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 6; 7 B2/B3 | B1 promoted from StandaloneRoutes S10; gate/slice ownership removal pending B3 |
| R337 | `PATCH` | `/api/v1/areas/:id` | `DawarichWeb.Api.AreasController :update` | `standalone_api` | `-` | `%{slice: :api_standalone, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 6; 7 B2/B3 | B1 promoted from StandaloneRoutes S11; gate/slice ownership removal pending B3 |
| R338 | `PUT` | `/api/v1/areas/:id` | `DawarichWeb.Api.AreasController :update` | `standalone_api` | `-` | `%{slice: :api_standalone, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 6; 7 B2/B3 | B1 promoted from StandaloneRoutes S12; gate/slice ownership removal pending B3 |
| R339 | `DELETE` | `/api/v1/areas/:id` | `DawarichWeb.Api.AreasController :destroy` | `standalone_api` | `-` | `%{slice: :api_standalone, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 6; 7 B2/B3 | B1 promoted from StandaloneRoutes S13; gate/slice ownership removal pending B3 |
| R340 | `POST` | `/api/v1/recalculations` | `DawarichWeb.Api.RecalculationsController :create` | `standalone_api_active` | `-` | `%{slice: :api_standalone, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api_active; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 6; 7 B2/B3 | B1 promoted from StandaloneRoutes S01; gate/slice ownership removal pending B3 |
| R341 | `PATCH` | `/api/v1/settings/mobile` | `DawarichWeb.Api.MobileSettingsController :update` | `standalone_api_active` | `-` | `%{slice: :api_standalone, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api_active; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 3c; 7 B2/B3 | B1 promoted from StandaloneRoutes S03; gate/slice ownership removal pending B3 |
| R342 | `PATCH` | `/api/v1/settings` | `DawarichWeb.Api.SettingsController :update` | `standalone_api_active` | `-` | `%{slice: :api_standalone, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api_active; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 3a/6; 7 B2/B3 | B1 promoted from StandaloneRoutes S06; gate/slice ownership removal pending B3 |
| R343 | `GET` | `/api/v1/demo_data` | `DawarichWeb.Api.DemoDataController :show` | `standalone_api_active` | `-` | `%{slice: :api_foundation, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api_active; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 6; 7 B2/B3 | B1 promoted from StandaloneRoutes S14/S15; gate/slice ownership removal pending B3 |
| R344 | `POST` | `/api/v1/demo_data` | `DawarichWeb.Api.DemoDataController :create` | `standalone_api_active` | `-` | `%{slice: :api_foundation, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api_active; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 6; 7 B2/B3 | B1 promoted from StandaloneRoutes S16; gate/slice ownership removal pending B3 |
| R345 | `DELETE` | `/api/v1/demo_data` | `DawarichWeb.Api.DemoDataController :destroy` | `standalone_api_active` | `-` | `%{slice: :api_foundation, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api_active; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 6; 7 B2/B3 | B1 promoted from StandaloneRoutes S17; gate/slice ownership removal pending B3 |
| R346 | `POST` | `/api/v1/digests` | `DawarichWeb.Api.DigestWritesController :create` | `standalone_api_active` | `-` | `%{slice: :api_standalone, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api_active; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 5; 7 B2/B3 | B1 promoted from StandaloneRoutes S18; gate/slice ownership removal pending B3 |
| R347 | `DELETE` | `/api/v1/digests/:year` | `DawarichWeb.Api.DigestWritesController :destroy` | `standalone_api_active` | `-` | `%{slice: :api_standalone, rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}}` | P:standalone_api_active; G:DawarichWeb.Api.StandaloneMap.enabled?; C/U | 5; 7 B2/B3 | B1 promoted from StandaloneRoutes S19; gate/slice ownership removal pending B3 |

### E3. Ordered pipeline sources and real transport rules

Common retained rules: HostAuthorization → local forbidden host; ForceSSL → canonical HTTPS redirect; RateLimit → local 429 with original method/rate buckets; Api.Body → bounded bytes/depth/form/JSON/chunk handling before effects. RailsAuth/RailsSession preserve cookie/remember/salt/CSRF semantics (names do not imply frontend dependency). RequireUser redirects to sign-in, respecting lock/session clearing. RailsHeaders preserves cache/content/security headers. OperatorRedirect requires operator proof independent of admin role. `RailsForm` and feature request parsers retain method/origin/CSRF/body/scalar constraints while replay becomes local refusal. Browser/live sessions retain static and connected actor identity and re-admit on events/params/info/async/reconnect through their feature auth/context; no scope/key in client payload can grant access.

Remove only TurboVisit/InsightsVisit/InsightsFrame and PageEnvelope's frame/minimal-layout/handback branches in B2; retain full-document alias normalization and ordinary flash. `method_override_to_rails` becomes direct local handling/refusal in B1, preserving original method. `put_path_format`/`put_tile_format` and `spatial_grant_auth` remain explicit API MIME/public-or-private auth rules. `rails_user`/`rails_frame` names may change; their auth checks do not disappear.

| Pipeline reference | Definition | Ordered plugs (options retained verbatim) | Disposition / refusal successor |
| --- | --- | --- | --- |
| P:browser | `W/router.ex:25` | `DawarichWeb.HostAuthorization → :accepts, ["html"] → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → :fetch_query_params → DawarichWeb.TurboVisit → DawarichWeb.RailsAuth → DawarichWeb.TripDocument → DawarichWeb.ImportsHeaders → DawarichWeb.MapDataHeaders → :phoenix_session → :fetch_session → :fetch_live_flash → DawarichWeb.Locale → DawarichWeb.LayoutAssigns → :put_root_layout, html: {DawarichWeb.Layouts, :root} → DawarichWeb.PageEnvelope, :layout → :protect_from_forgery → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:insights | `W/router.ex:47` | `DawarichWeb.HostAuthorization → :accepts, ["html"] → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → :fetch_query_params → DawarichWeb.InsightsVisit → DawarichWeb.RailsAuth → :phoenix_session → :fetch_session → :fetch_live_flash → DawarichWeb.Locale → DawarichWeb.LayoutAssigns → :put_root_layout, html: {DawarichWeb.Layouts, :root} → DawarichWeb.PageEnvelope, :layout → :protect_from_forgery → DawarichWeb.RailsHeaders → DawarichWeb.InsightsFrame → DawarichWeb.RequireUser` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:family_data | `W/router.ex:73` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsAuth` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:sharing | `W/router.ex:84` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → :fetch_query_params → DawarichWeb.TurboVisit → DawarichWeb.RailsAuth → DawarichWeb.Locale → DawarichWeb.LayoutAssigns → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:sharing_unlock | `W/router.ex:96` | `:put_api_tag, "sharing" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body → DawarichWeb.UnlockAdmission → :fetch_query_params → DawarichWeb.RailsAuth → DawarichWeb.Locale → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:rails_user | `W/router.ex:123` | `DawarichWeb.RequireUser → DawarichWeb.FamilyGate` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:rails_frame | `W/router.ex:128` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → :fetch_query_params → DawarichWeb.RailsAuth → DawarichWeb.Locale → DawarichWeb.RailsHeaders → DawarichWeb.RequireUser` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:rails_form | `W/router.ex:139` | `:put_api_tag, "form" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body → DawarichWeb.RailsAuth → DawarichWeb.RailsForm → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:imports_request | `W/router.ex:153` | `:put_api_tag, "imports" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsAuth → DawarichWeb.ImportsRequest → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:map_write | `W/router.ex:165` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsAuth → DawarichWeb.MapWriteRequest → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:stats_request | `W/router.ex:176` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsAuth → DawarichWeb.StatsRequest → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:digest_request | `W/router.ex:198` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsAuth → DawarichWeb.DigestRequest → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:stats_sharing | `W/router.ex:222` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsAuth → DawarichWeb.StatsSharingRequest → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:standalone_settings | `W/a10_routes.ex:5` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsAuth → DawarichWeb.Api.Body → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:trial_welcome | `W/a10_routes.ex:14` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:public_home | `W/a10_routes.ex:20` | `DawarichWeb.HostAuthorization → :accepts, ["html"] → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → :fetch_query_params → DawarichWeb.TurboVisit → DawarichWeb.RailsAuth → :phoenix_session → :fetch_session → :fetch_live_flash → DawarichWeb.Locale → DawarichWeb.LayoutAssigns → :put_root_layout, html: {DawarichWeb.Layouts, :root} → DawarichWeb.PageEnvelope, :layout → :protect_from_forgery → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:trial_resume | `W/a10_routes.ex:39` | `DawarichWeb.HostAuthorization → :accepts, ["html"] → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → :fetch_query_params → DawarichWeb.TurboVisit → DawarichWeb.RailsAuth → DawarichWeb.TrialResumeHeaders → :phoenix_session → :fetch_session → :fetch_live_flash → DawarichWeb.Locale → DawarichWeb.LayoutAssigns → :put_root_layout, html: {DawarichWeb.Layouts, :root} → DawarichWeb.PageEnvelope, :layout → :protect_from_forgery → DawarichWeb.RailsHeaders → DawarichWeb.RequireUser → DawarichWeb.TrialResumeStatus` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:background_operator | `W/a10_routes.ex:61` | `DawarichWeb.OperatorRedirect, background: true` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:admin_page | `W/a10_routes.ex:65` | `DawarichWeb.AuthenticatedPageGate` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:a8_action | `W/a8_routes.ex:5` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsAuth → DawarichWeb.A8Request → DawarichWeb.Locale → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:a8_public | `W/a8_routes.ex:106` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:poster_form | `W/a9_routes.ex:6` | `:put_api_tag, "form" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body, nested_form: "poster" → DawarichWeb.RailsAuth → DawarichWeb.PostersGate → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:share_form | `W/a9_routes.ex:31` | `:put_api_tag, "form" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body, nested_form: "shared_link" → DawarichWeb.RailsAuth → :share_form_admission → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:achievement_image | `W/achievement_image_routes.ex:5` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsAuth` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:achievement_action | `W/achievement_routes.ex:5` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsAuth → DawarichWeb.AchievementActions.Request → DawarichWeb.Locale → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:achievement_public | `W/achievement_routes.ex:15` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsAuth → DawarichWeb.AchievementPublic` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:achievement_initial | `W/achievement_routes.ex:62` | `DawarichWeb.AchievementInitial` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_account | `W/api_routes.ex:10` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → :method_override_to_rails → DawarichWeb.Api.Body → DawarichWeb.Api.Auth, require_active: false` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_account_destroy | `W/api_routes.ex:20` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → :method_override_to_rails → DawarichWeb.Api.Body → DawarichWeb.Api.Auth, require_active: false, reject_pending: false` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_manager | `W/api_routes.ex:40` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → :method_override_to_rails → DawarichWeb.Api.Body` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_visits | `W/api_routes.ex:71` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → :method_override_to_rails → DawarichWeb.Api.Body → DawarichWeb.Api.Auth, require_active: false` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_notes | `W/api_routes.ex:103` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → :method_override_to_rails → DawarichWeb.Api.Body → DawarichWeb.Api.Auth, require_active: false` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_shared | `W/api_routes.ex:123` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_ingest | `W/api_routes.ex:151` | `:put_api_tag, "ingest" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body → DawarichWeb.Api.Auth` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_pending | `W/api_routes.ex:174` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body → DawarichWeb.Api.Respond, :prepare` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_foundation | `W/api_routes.ex:185` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body → DawarichWeb.Api.Auth, reject_pending: false, require_active: false` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_stats | `W/api_routes.ex:200` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body → DawarichWeb.Api.Auth, require_active: false` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_tiles | `W/api_routes.ex:209` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body → :put_tile_format → DawarichWeb.Api.Auth, require_active: false` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_spatial_grants | `W/api_routes.ex:219` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body → :spatial_grant_auth` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_transport | `W/api_routes.ex:228` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Respond, :prepare` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_places | `W/api_routes.ex:254` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → :method_override_to_rails → DawarichWeb.Api.Body → DawarichWeb.Api.Auth, require_active: false` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:api_locations_photos | `W/api_routes.ex:267` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body → :put_path_format → DawarichWeb.Api.Auth, require_active: false` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:cable | `W/cable_routes.ex:6` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:family_form | `W/domain_routes.ex:8` | `:put_api_tag, "family" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.FamilyDeliveryAdmission → DawarichWeb.FamilyRequestAdmission → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:exports_delete | `W/export_routes.ex:5` | `:put_api_tag, "exports" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body → DawarichWeb.RailsAuth → DawarichWeb.ExportsDeleteForm → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:exports_create | `W/export_routes.ex:16` | `:put_api_tag, "form" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.ExportsCreate, :decode → DawarichWeb.RailsAuth → DawarichWeb.RailsForm → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:health | `W/health_routes.ex:6` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization, health: true → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:integration_jobs | `W/integration_form_routes.ex:5` | `:put_api_tag, "integrations" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsAuth → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:metrics | `W/metrics_routes.ex:6` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:operator | `W/operator_routes.ex:6` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:operator_session | `W/operator_routes.ex:13` | `DawarichWeb.RailsAuth` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:native_navigation | `W/page_routes.ex:44` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:map_redirect | `W/page_routes.ex:63` | `DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:storage_public | `W/storage_routes.ex:29` | `:put_api_tag, "active_storage" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:storage_upload | `W/storage_routes.ex:37` | `:put_api_tag, "active_storage" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.RailsAuth → DawarichWeb.RailsHeaders` | retain admission/MIME/body/session; B2 local refusal, B3 remove ownership only |
| P:standalone_api | `W/standalone_api_routes.ex:6` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body → DawarichWeb.Api.Auth, require_active: false` | B1 direct API admission (former StandaloneRoutes active=false); B3 remove gate/slice only |
| P:standalone_api_active | `W/standalone_api_routes.ex:15` | `:put_api_tag, "api" → DawarichWeb.HostAuthorization → DawarichWeb.ForceSSL → DawarichWeb.RateLimit → DawarichWeb.Api.Body → DawarichWeb.Api.Auth, require_active: true` | B1 direct API admission (former StandaloneRoutes active=true); B3 remove gate/slice only |

### E4. Gate semantics and query-cost obligations

Numbers below are static query-producing calls in the gate, not fresh SQL measurements. `0` means no direct domain read in that gate, never zero total admission cost: RailsAuth can reload the actor. B2/D3 must attach positive-observation telemetry to static/connected/params/events, count admission and context reads, and measure sparse/populated cases before choosing caps. Never subtract auth reads or claim a source count is a runtime budget. Refusals delegated today to replay/Strangler become local 4xx/typed page destinations; no same-URL fallback. Fields and predicates cited here remain source contracts until the feature's named behavior successors in D1 and the main retarget table are verified.

| Gate reference | Source | Ownership/envelope retired | Retained constraint/admission and local successor | Current extra domain-read sites to measure | Last feature / cleanup / status |
| --- | --- | --- | --- | --- | --- |
| G:DawarichWeb.A8Gate.actions? | `W/a8_gate.ex:4` | transport ownership/content-envelope selection | feature RequestGate scalar query/ID, bounded multipart/form/bytes, origin/CSRF/salt in handler; events 3d/5/6 | 0 | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.A8Gate.navigation? | `W/a8_gate.ex:44` | transport ownership/content-envelope selection | feature RequestGate scalar query/ID, bounded multipart/form/bytes, origin/CSRF/salt in handler; events 3d/5/6 | 0 | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.AchievementActions.Gate.dismiss? | `W/achievement_actions/gate.ex:15` | eligible route handoff / Turbo responses | fresh actor/salt, registry/claim-token/settings and locked scope commands; 401/422 locally; 5 achievement events | snapshot pending/state SQL (2 sites) plus actor refresh | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.AchievementActions.Gate.next? | `W/achievement_actions/gate.ex:13` | eligible route handoff / Turbo responses | fresh actor/salt, registry/claim-token/settings and locked scope commands; 401/422 locally; 5 achievement events | snapshot pending/state SQL (2 sites) plus actor refresh | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.AchievementActions.Gate.seen? | `W/achievement_actions/gate.ex:14` | eligible route handoff / Turbo responses | fresh actor/salt, registry/claim-token/settings and locked scope commands; 401/422 locally; 5 achievement events | snapshot pending/state SQL (2 sites) plus actor refresh | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.AchievementActions.Gate.sharing? | `W/achievement_actions/gate.ex:12` | eligible route handoff / Turbo responses | fresh actor/salt, registry/claim-token/settings and locked scope commands; 401/422 locally; 5 achievement events | snapshot pending/state SQL (2 sites) plus actor refresh | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.AchievementPageGate.open? | `W/achievement_page_gate.ex:6` | collection renderability gate | scalar q/status/page/locale/commit + page bound + auth; native 5 context handles unknown collection locally | 0 | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.AchievementPublic.open? | `W/achievement_public.ex:14` | coexistence session/renderable envelope | public UUID/card state/settings/query, privacy and rate; 5 public context, local unavailable | PublicCard read/representability | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.AdminGate.background_route? | `W/admin_gate.ex:12` | supported page ownership/header/marker envelope | hosting/operator grant distinct from admin, supported settings and fresh salt/actor; AdminLiveAuth + Admin.Access, sign-in/home/settings destination | actor auth; supported settings | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.Api.AccountDestroyController.enabled? | `W/api/account_destroy_controller.ex:9` | Standalone enabled gate | confirmation, active/pending exceptions, self-hosted/Cloud deletion policy and jobs transaction; direct API 7 B1 | 0 in enabled?; downstream delete context | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.Api.SharedController.photos_owned? | `W/api/shared_controller.ex:12` | photos_owned coexistence transport gate | canonical grant/expiry/phrase/family consent/private projection; JSON/image/HEAD status/headers; 6/B1 direct API | SharedLinks/API read and family/private option checks | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.Api.StandaloneMap.enabled? | `W/api/standalone_map.ex:8` | Standalone enabled gate | Cloud fail-closed policy, timezone/ranges/bounds/speed/id checks; JSON/MVT public/private auth; 6/B1 direct API | 0 in enabled?; downstream spatial reads | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.FamilyGate.edit? | `W/family_gate.ex:116` | client markers/body ownership and same-URL refresh fallback | membership/entitlement/request target/consent via 4c scoped Families and native auth; clear content on revocation; 302 sign-in/family, 303 access/plan refusal | FamilyPage.read in HTTP plug and refresh | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.FamilyGate.invitations? | `W/family_gate.ex:117` | client markers/body ownership and same-URL refresh fallback | membership/entitlement/request target/consent via 4c scoped Families and native auth; clear content on revocation; 302 sign-in/family, 303 access/plan refusal | FamilyPage.read in HTTP plug and refresh | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.FamilyGate.new? | `W/family_gate.ex:115` | client markers/body ownership and same-URL refresh fallback | membership/entitlement/request target/consent via 4c scoped Families and native auth; clear content on revocation; 302 sign-in/family, 303 access/plan refusal | FamilyPage.read in HTTP plug and refresh | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.FamilyGate.request? | `W/family_gate.ex:118` | client markers/body ownership and same-URL refresh fallback | membership/entitlement/request target/consent via 4c scoped Families and native auth; clear content on revocation; 302 sign-in/family, 303 access/plan refusal | FamilyPage.read in HTTP plug and refresh | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.FamilyGate.show? | `W/family_gate.ex:114` | client markers/body ownership and same-URL refresh fallback | membership/entitlement/request target/consent via 4c scoped Families and native auth; clear content on revocation; 302 sign-in/family, 303 access/plan refusal | FamilyPage.read in HTTP plug and refresh | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.FamilyInvitationPage.native? | `W/family_invitation_page.ex:17` | renderability :rails | token expiry, target/actor/entitlement/settings in 4c scoped invitation; retained anonymous HTTP token operation | invitation/token/member reads in read | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.FamilyLocations.native? | `W/family_locations.ex:12` | format/session envelope | fresh actor/membership/entitlement/consent; native 6 cookie reader; retained JSON 401/403/404/500 with private no-store | actor get + FamilyPage.read + Locations.read | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.HomeGate.owned? | `W/home_gate.ex:7` | rails_routes ownership and hybrid envelope | lock/salt/registration policy, scalar unique query, safe method/header; native shell public/auth context | RailsAuth + registration policy (hybrid branch) | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.ImportsGate.native? | `W/imports_gate.ex:6` | UiRecords renderability :rails | actor-owned record, source/status/data shape validated once by 4 context; local missing/invalid refusal | UiRecords.get 1 site before page load | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.InsightsGate.owned? | `W/insights_gate.ex:6` | Strangler ownership/envelope | Admission.headers + actor lock/salt; 5 scoped Insights/native data auth | RailsAuth | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.IntegrationJobActions.enabled? | `W/integration_job_actions.ex:9` | normal/legacy HTTP ownership | six job names, Cloud/OIDC/operator/origin/CSRF/query/body handling; 4 events, retain HTTP only until final consumer; 303 destinations, 422/500/503 errors | IntegrationActions admission or AdminWritesGate + enqueue | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.MapDataGate.point_address? | `W/map_data_gate.ex:23` | list/segment renderability query in gate | filters, bounds/scalar shape and owner; 5 points/6 map context local invalid/not found | PointList.load / TrackSegmentPage.load before mount | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.MapDataGate.points? | `W/map_data_gate.ex:7` | list/segment renderability query in gate | filters, bounds/scalar shape and owner; 5 points/6 map context local invalid/not found | PointList.load / TrackSegmentPage.load before mount | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.MapDataGate.segments? | `W/map_data_gate.ex:18` | list/segment renderability query in gate | filters, bounds/scalar shape and owner; 5 points/6 map context local invalid/not found | PointList.load / TrackSegmentPage.load before mount | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.MapFramesGate.calendar? | `W/map_frames_gate.ex:23` | Turbo/HTML fragment acceptance | calendar/feed/residency/track query shapes delegated to 6 native timeline/read context; frame-only routes retire | 0 | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.MapFramesGate.feed? | `W/map_frames_gate.ex:12` | Turbo/HTML fragment acceptance | calendar/feed/residency/track query shapes delegated to 6 native timeline/read context; frame-only routes retire | 0 | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.MapFramesGate.residency? | `W/map_frames_gate.ex:28` | Turbo/HTML fragment acceptance | calendar/feed/residency/track query shapes delegated to 6 native timeline/read context; frame-only routes retire | 0 | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.MapFramesGate.track? | `W/map_frames_gate.ex:10` | Turbo/HTML fragment acceptance | calendar/feed/residency/track query shapes delegated to 6 native timeline/read context; frame-only routes retire | 0 | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.MapWriteGate.owned? | `W/map_write_gate.ex:8` | hybrid cookie/header/XHR ownership envelope | one authenticated session, method/body/CSRF/origin/size, deliberate anonymous recalculation refusal contract; 6 scoped events | RailsAuth.session_user | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.PageEnvelope.navigation? | `W/page_envelope.ex:184` | navigation/frame/reload/minimal layout ownership | .html and format=html full documents preserving filters/locale/privacy; local malformed MIME/query and HEAD semantics B2 | feature gates may repeat page reads | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.PlacesGate.index? | `W/places_gate.ex:7` | list/drawer/nearby renderability + turbo-frame selector | 3d scoped list/detail filters/pagination/owner; 6 nearby/drawer native commands/reader; local refusal | PlaceList.load / PlaceDrawer.load + missing-place SQL before render | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.PlacesGate.navigation? | `W/places_gate.ex:33` | list/drawer/nearby renderability + turbo-frame selector | 3d scoped list/detail filters/pagination/owner; 6 nearby/drawer native commands/reader; local refusal | PlaceList.load / PlaceDrawer.load + missing-place SQL before render | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.PlacesGate.nearby? | `W/places_gate.ex:47` | list/drawer/nearby renderability + turbo-frame selector | 3d scoped list/detail filters/pagination/owner; 6 nearby/drawer native commands/reader; local refusal | PlaceList.load / PlaceDrawer.load + missing-place SQL before render | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.PostersGate.native? | `W/posters_gate.ex:9` | POST/DELETE ownership and Turbo negotiation | JSON unauthenticated 401 vs HTML sign-in, RailsForm CSRF/origin/body; 6c scoped command/gallery/download | actor admission only; command reads later | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.SettingsActions.enabled? | `W/settings_actions.ex:7` | Standalone.enabled ownership | settings command actor/salt/OIDC/encryption/validation; 3a native settings and 4 integrations/6 onboarding; local failure | 0 in enabled?; downstream command reads | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.ShareManagementGate.mutation? | `W/share_management_gate.ex:9` | frame/self-hosted envelope + read-for-render gate | canonical share/trip IDs, timezone/date/query bounds, scoped owner/expiry/consent via 4c Sharing; unlock/public 6, no secret state | Read.hub/trip/live before page mount | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.ShareManagementGate.native? | `W/share_management_gate.ex:31` | frame/self-hosted envelope + read-for-render gate | canonical share/trip IDs, timezone/date/query bounds, scoped owner/expiry/consent via 4c Sharing; unlock/public 6, no secret state | Read.hub/trip/live before page mount | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.SharingGate.show? | `W/sharing_gate.ex:11` | anonymous/self-hosted/forwarded/client envelope ownership | canonical id, signed unlock/body/rate, family audience/expiry/consent; 4c command + 6 public native root local refusal | SharedLinks.active + SharedLinks.page; family_only active read | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.SharingGate.unlock? | `W/sharing_gate.ex:14` | anonymous/self-hosted/forwarded/client envelope ownership | canonical id, signed unlock/body/rate, family audience/expiry/consent; 4c command + 6 public native root local refusal | SharedLinks.active + SharedLinks.page; family_only active read | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.StorageGate.native? | `W/storage_gate.ex:4` | rails_routes active_storage ownership only | signature/checksum/content type/byte limits/owner in HTTP storage handlers; keep signed public URLs and no Hotwire | 0 | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.TimelineShareActions.native? | `W/timeline_share_actions.ex:19` | frame/self-hosted transport ownership | actor/salt/origin/CSRF, timeline interval/owner/expiry; 4c scoped Sharing, public map 6 | Read.timeline | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.TrackShareActions.native? | `W/track_share_actions.ex:20` | frame/self-hosted transport ownership | numeric track ID, actor/origin/CSRF, track owner/expiry; 4c scoped Sharing, public map 6 | Read.track | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.TrialGate.resume? | `W/trial_gate.ex:19` | hybrid status/render envelope | fresh actor, entitlement/payment/JWT/registration policies in 3c/6 shell; local sign-in/upgrade/unavailable | RailsAuth + plan/paid policy | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.TrialGate.upgrade? | `W/trial_gate.ex:7` | hybrid status/render envelope | fresh actor, entitlement/payment/JWT/registration policies in 3c/6 shell; local sign-in/upgrade/unavailable | RailsAuth + plan/paid policy | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.TripsGate.form? | `W/trips_gate.ex:32` | renderability/rails_upstream branch ownership | page/family-page shape/cap, actor/owner/plan/settings via 5b Trips context; 6 map host | TripList.gate / ShowCalculation.admitted? / WebForm.load/active? before mount | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.TripsGate.index? | `W/trips_gate.ex:6` | renderability/rails_upstream branch ownership | page/family-page shape/cap, actor/owner/plan/settings via 5b Trips context; 6 map host | TripList.gate / ShowCalculation.admitted? / WebForm.load/active? before mount | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.TripsGate.show? | `W/trips_gate.ex:20` | renderability/rails_upstream branch ownership | page/family-page shape/cap, actor/owner/plan/settings via 5b Trips context; 6 map host | TripList.gate / ShowCalculation.admitted? / WebForm.load/active? before mount | feature owner above; shared 7 B2; pending integration |
| G:DawarichWeb.WelcomeGate.owned? | `W/welcome_gate.ex:16` | hybrid welcome envelope ownership | token signature/expiry/OIDC/registration, bounded scalar query/header/body; 3c trial HTTP + 6 shell | Welcome.prepare + secret/config lookup | feature owner above; shared 7 B2; pending integration |


Nested gate readers not directly represented in `rails_gate` metadata also stay in the admission handoff: `W/admin_writes_gate.ex:8` handles the retained background POST's query-toggle branch (actor/salt, OIDC/hosting, session markers and supported settings; 4 last HTTP consumer after 3b native background). `W/trip_request_gate.ex:4`, `place_request_gate.ex:4`, `route_video_request_gate.ex:4`, and `visit_request_gate.ex:5` supply A8's scalar export/page/delete/status query and hosting rules (3d/5/6). `W/authenticated_page_gate.ex:9` deliberately admits anonymous/refused GET/HEAD into the local sign-in/admin refusal pipeline, never a positive authorization shortcut. Their direct handlers/context successors keep those rules. Source gates currently calling a read before mount are identified above for duplicate-query measurement; no zero-query inference is made from a missing compiled gate.

### E5. Macro ownership (including nested imports)

Every defined macro in the old route source set is listed, including nested imports and definitions whose routes are not currently compiled. This is the static superset; R rows are authoritative for current reachability. One shared B owner integrates all macro simplification in B1–B3 after the listed feature owner supplies its handoff. A macro file is not removed just because its top-level import disappeared.

| Macro reference | Source | Last feature owner | Shared deletion/retention decision / status |
| --- | --- | --- | --- |
| M:DawarichWeb.A10Routes.a10_routes | `W/a10_routes.ex:3` | 3a/3b native + 3c/6 shell; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.A8Routes.a8_routes | `W/a8_routes.ex:3` | 3d/5/6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.A9Routes.poster_routes | `W/a9_routes.ex:4` | 6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.A9Routes.share_form_routes | `W/a9_routes.ex:29` | 4/6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.A9Routes.share_page_routes | `W/a9_routes.ex:76` | 4/6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.A9Routes.family_invitation_routes | `W/a9_routes.ex:96` | 4; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.A9Routes.family_data_routes | `W/a9_routes.ex:110` | 4/6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.A9Routes.family_page_routes | `W/a9_routes.ex:121` | 4/6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.AchievementImageRoutes.achievement_image_routes | `W/achievement_image_routes.ex:3` | 5/6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.AchievementRoutes.achievement_routes | `W/achievement_routes.ex:3` | 5/6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.ApiClosureRoutes.a12f2_b_routes | `W/api_closure_routes.ex:21` | retain external protocol; 7 B1/B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.ApiReadRoutes.a12f2_c_spatial_routes | `W/api_read_routes.ex:4` | retain external protocol; 7 B1/B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.ApiReadRoutes.api_stats_routes | `W/api_read_routes.ex:59` | retain external protocol; 7 B1/B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.ApiReadRoutes.api_places_routes | `W/api_read_routes.ex:90` | retain external protocol; 7 B1/B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.ApiReadRoutes.api_family_routes | `W/api_read_routes.ex:116` | retain external protocol; 7 B1/B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.ApiReadRoutes.api_locations_photos_routes | `W/api_read_routes.ex:137` | retain external protocol; 7 B1/B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.ApiRoutes.api_routes | `W/api_routes.ex:4` | retain external protocol; 7 B1/B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.ApiWriteRoutes.a12f2_e_routes | `W/api_write_routes.ex:4` | retain external protocol; 7 B1/B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.CableRoutes.cable_routes | `W/cable_routes.ex:4` | retain protocol; 7 B1/B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.DomainRoutes.family_native_routes | `W/domain_routes.ex:4` | 4; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.DomainRoutes.native_share_routes | `W/domain_routes.ex:37` | 4/6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.ExportRoutes.export_routes | `W/export_routes.ex:3` | 4; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.FamilyFormRoutes.routes | `W/family_form_routes.ex:75` | 4/6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.HealthRoutes.health_routes | `W/health_routes.ex:4` | retain external protocol; 7 B1/B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.ImportRoutes.import_routes | `W/import_routes.ex:3` | 4; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.IntegrationFormRoutes.integration_form_routes | `W/integration_form_routes.ex:3` | 4 last imports consumer; 3b native background delivered; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.MapFrameRoutes.map_frame_routes | `W/map_frame_routes.ex:3` | 6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.MetricsRoutes.metrics_routes | `W/metrics_routes.ex:4` | retain protocol; 7 B1/B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.NativeAdminRoutes.native_admin_routes | `W/native_admin_routes.ex:3` | 3b native delivered; 4 final background HTTP consumer; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.NotificationFormRoutes.notification_form_routes | `W/notification_form_routes.ex:3` | 4; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.OnboardingRoutes.onboarding_routes | `W/onboarding_routes.ex:3` | 6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.OperatorRoutes.operator_routes | `W/operator_routes.ex:4` | retain external protocol; 7 B1/B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.PageRoutes.page_routes | `W/page_routes.ex:3` | 3c/3d/4/5/6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.RailsPagesRoutes.rails_pages_routes | `W/rails_pages_routes.ex:3` | 3d/4/5/6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.SettingsMiscRoutes.settings_misc_routes | `W/settings_misc_routes.ex:3` | 3a native delivered/4 integrations/6 onboarding; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.ShareManagementOverrideRoutes.routes | `W/share_management_override_routes.ex:4` | 4; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.StandaloneApiRoutes.standalone_api_routes | `W/standalone_api_routes.ex:4` | 3c/5/6 API successors; 7 B1 | B1 direct routes for former secondary dispatcher; B3 strips StandaloneMap gate and slices |
| M:DawarichWeb.StorageRoutes.storage_routes | `W/storage_routes.ex:27` | retain external protocol; 7 B1/B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.TimelineShareRoutes.routes | `W/timeline_share_routes.ex:3` | 4/6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.TrackShareRoutes.routes | `W/track_share_routes.ex:3` | 4/6; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |
| M:DawarichWeb.TrialHomeRoutes.trial_home_routes | `W/trial_home_routes.ex:3` | 3c/6 shell; 7 B2/B3 | B owns integration; retain HTTP/API constraints, retire UI-only frames/ownership after S1 |

### E6. Constraints, aliases, endpoint and signed formats

| Reference | Current source and constraint | Retained contract / owner / status |
| --- | --- | --- |
| C numeric web IDs | W/strangler.ex:25: family location request, route video, visit, settings user/detail/edit, track segment parent, point address, timeline track_info, trip/detail/edit/recalculate/export/note IDs, place IDs accept 1–18 decimal digits | 3d/4/5/6 validates identifiers locally before lookups; 7 B2 preserves 404 on bad shapes; pending direct plug replacement |
| C positive segment pair | W/strangler.ex:44: tracks/:track_id/segments/:id uses positive 1–18 digit pair | 6 native segment context; 7 B2 retain local invalid-ID refusal |
| C year/month | W/strangler.ex:48: stats year is four digits, month 1–12 with optional leading zero; digests/web/API year four digits | 5 contexts/native params; 7 B2 aliases preserve shapes and 404; standalone digest dispatcher also checks year |
| C tiles | W/strangler.ex:23: points/tracks tile y ends .mvt | 6/7 B1 retain MVT MIME/bytes, grant auth and HEAD; no HTML alias rewrite on tile path |
| C coexistence-only API ID constraints | W/strangler.ex:54: visits/possible_places/select_place, notes, places, family accept/decline use 1–18 digits; tracks IDs digits; photo thumbnail ID 1–128 URL-safe chars | Today omitted in standalone; record this distinction rather than silently strengthening API behavior in B2. Controllers/context validation and error fixtures remain; retire coexistence ownership only |
| U document aliases | W/page_envelope.ex:11; W/api/request_format.ex | Keep .html and format=html as full native documents preserving filters/locale/privacy/auth. XHR/Turbo frame/minimal layout logic retires after 3c–6. B2 named successor: `HTML document aliases preserve filters privacy and admission`; existing page_envelopes_test suffix/query cases retained until then |
| U HEAD | W/strangler.ex:92; W/standalone_routes.ex:27; W/api/method_override.ex; P rate/body | Router GET is looked up for HEAD before Plug.Head while original method remains for limits/status/headers. Secondary dispatcher explicitly recognizes HEAD only for demo_data; other secondary GETs are not implicitly HEAD routes. Preserve observed differences in B1 until deliberate documented change; no blanket synthesized success |
| U API formats | W/api/request_format.ex; API pipeline put_path_format/put_tile_format | JSON suffix/query normalization, .jpg thumbnails/MVT tiles and supported MIME errors stay; malformed format fails locally. Preserve original method/body rate semantics and true API content, no Turbo page envelope |
| U public unlock | POST /s/:id/unlock, P:sharing_unlock; W/unlock_admission.ex, SharedLinks domain | Canonical ID, bounded body/rate, phrase/expiry/family audience/consent grant; keep signed cookie and local status; 4c/6 successors; never expose phrase in assigns/logs |
| U storage | W/storage_routes.ex:52, W/storage/*; P:storage_upload/storage_public | POST direct_uploads owner/checksum/length; PUT signed disk upload; GET/HEAD signed disk/blob redirect/proxy/representation URLs; keep signatures/expiry/download disposition/cache/range/MIME and byte caps. Browser native upload/editor 4/5; shared 7 B1/A3 retains HTTP data protocol |
| U render/export | imports/exports/trips/route_videos/posters handlers and R rows | Owner/expiry/durable job/cancel/download/JSON/codec/font behavior survives 4/5/6; Turbo-only responses retire with last UI consumer; renderer payload retained |
| U operations | P:health/metrics/operator/operator_session; R health/ready/sidekiq/jobs routes | Public health/readiness vs authorized metrics/operator/sidekiq remain distinct. Grant/Basic/HTTPS/hosting proof preserved; admin is not operator. 7 B3 strips routing keys only. Protected lifecycle/Cloud admission untouched |
| Endpoint LiveSocket | W/endpoint.ex:14; W/live_socket.ex | /phoenix/live websocket connect_info session, no longpoll; auth/session/CSRF and fresh event admission retained; private LiveView signed session is not ActionCable identity |
| Endpoint static | W/endpoint.ex:20–41; W/public_files.ex | /native digest chunks stay; /phoenix/js Phoenix clients stay as required; hybrid app/map_shell/rails_bridge/family_page/hooks mount retires A1 after 6; public static/PWA/fonts/geodata/Swagger stay per D2 |
| Endpoint before router | W/endpoint.ex:42–49 | PublicFiles, Cors, AuthGate, Api.RequestFormat, Api.MethodOverride, Strangler, Api.Transport(:router). B1/B2/B3 replace ownership dispatch only; retain CORS/host/SSL/rate/body/local errors/error-once redaction and auth intercepts |

### E7. Secondary standalone dispatcher APIs (before B1 promotion)

These are the real `StandaloneRoutes` definitions, not inferred URLs from the router. `active` is Api.Auth require_active; every route takes HostAuthorization, ForceSSL, RateLimit, Api.Body, then public or actor auth and settings. Errors/body ownership must remain local and pre-effect; settings read is an extra query site to include in API counters. Dispatcher routes may overlap Router patterns, so priority/HEAD must be tested, not resolved by deleting a table. `.json` normalization precedes dispatch. Endpoint mobile/auth/subscription intercepts are E8, not this table.

| ID | Method | Path | Handler/action | Active actor | Shape/public/HEAD | Owner/disposition / test evidence |
| --- | --- | --- | --- | --- | --- | --- |
| S01 | POST | /api/v1/recalculations | Api.RecalculationsController.create | true | native marker + Plug.Head (POST unchanged) | 6/7 B1 retain; standalone_api_gaps_commit_test |
| S02 | GET | /api/v1/settings/mobile | Api.MobileSettingsController.show | false | actor, no explicit HEAD match | 3c/7 B1 retain; standalone_api_gaps_test |
| S03 | PATCH | /api/v1/settings/mobile | Api.MobileSettingsController.update | true | actor write | 3c/7 B1 retain; standalone_api_gaps_test |
| S04 | GET | /api/v1/areas | Api.AreasController.index | false | actor, no explicit HEAD match | 6/7 B1 retain; standalone_api_gaps_test |
| S05 | POST | /api/v1/areas | Api.AreasController.create | false | actor write active exception | 6/7 B1 retain; standalone_api_gaps_test |
| S06 | PATCH | /api/v1/settings | Api.SettingsController.update | true | actor write | 3a/6/7 B1 retain; standalone_api_gaps_test |
| S07 | GET | /api/v1/timeline | Api.TimelineController.index | false | actor; no explicit HEAD match | 6/7 B1 retain; standalone_map_test |
| S08 | GET | /api/v1/maps/hexagons | Api.HexagonsController.index | false | present uuid uses Api.Auth.public, otherwise actor | 6/7 B1 retain; standalone_map_test |
| S09 | PATCH | /api/v1/points/:id/position | Api.PointPositionsController.update | true | id 1–18 digits, point_id passed | 6/7 B1 retain; standalone_api_gaps_test |
| S10 | GET | /api/v1/areas/:id | Api.AreasController.show | false | id forwarded, no dispatcher digit constraint | 6/7 B1 retain; standalone_api_gaps_test |
| S11 | PATCH | /api/v1/areas/:id | Api.AreasController.update | false | id forwarded | 6/7 B1 retain; standalone_api_gaps_test |
| S12 | PUT | /api/v1/areas/:id | Api.AreasController.update | false | id forwarded | 6/7 B1 retain; standalone_api_gaps_test |
| S13 | DELETE | /api/v1/areas/:id | Api.AreasController.destroy | false | native marker + Plug.Head (DELETE unchanged) | 6/7 B1 retain; standalone_api_gaps_commit_test |
| S14 | GET | /api/v1/demo_data | Api.DemoDataController.show | true | native marker | 6/7 B1 retain; standalone_api_gaps_test |
| S15 | HEAD | /api/v1/demo_data | Api.DemoDataController.show | true | explicit HEAD → Plug.Head preserves no-body | 6/7 B1 retain; standalone_api_gaps_test |
| S16 | POST | /api/v1/demo_data | Api.DemoDataController.create | true | native marker; idempotent fixture generation | 6/7 B1 retain; standalone_api_gaps_test |
| S17 | DELETE | /api/v1/demo_data | Api.DemoDataController.destroy | true | native marker; actor-owned data only | 6/7 B1 retain; standalone_api_gaps_test |
| S18 | POST | /api/v1/digests | Api.DigestWritesController.create | true | native marker; bounded year/job semantics | 5/7 B1 retain; standalone_api_gaps_test |
| S19 | DELETE | /api/v1/digests/:year | Api.DigestWritesController.destroy | true | four-digit year; native marker | 5/7 B1 retain; standalone_api_gaps_test |

B1 (2026-10-10): `W/standalone_routes.ex` deleted. S01–S06, S10–S19 are router routes R333–R347 (`W/standalone_api_routes.ex`); S07/S08/S09 were already compiled as R047/R054/R041 and their dispatcher clauses were unreachable. HEAD stays 404 for every promoted GET except demo_data (HEAD-capable slice). Promoted paths left `ApiClosureRoutes.deferred?`, so POST method overrides and local 404s follow the other native API routes; see ED-NATIVE-M7-B1-* rows.

### E8. Auth HTTP intercepts and external callback contracts

AuthGate precedes Router. In standalone it runs StandaloneAuth first (including duplicate-cookie rejection), then credentials/OTP/two_factor handlers; its `Strangler.handed_back?`, phoenix_auth flow selection and SELF_HOSTED ownership branch retire through 3c/7 B3, while actual OIDC/provider/registration/encryption/cookie policies remain. HTTP operations must remain HTTP because they rotate identity cookies or consume provider callbacks. No native retry/handback is a valid refusal destination. Every handler's actual admission/source response tests remain; native root/format successor coverage lives on 3c.

| Method/path family | Current HTTP owner | Retained admission/response / status |
| --- | --- | --- |
| GET/POST /users/sign_in; DELETE/POST /users/sign_out | AuthHandler (AuthGate) | credentials, session salt/remember/lock/OTP, scoped CSRF and full-load logout; 3c delivered |
| GET /users/sign_up; POST /users | AuthRegistration.Http via StandaloneAuth | invitation/registration/OIDC/paid policy; POST body decides registration vs account override/delete; native accessible auth root; 3c delivered |
| GET /users/password/new, /users/password/edit, /users/unlock/new, /users/unlock; POST /users/password, /users/unlock; PATCH/PUT /users/password | AuthRecovery.Http | token expiry/hash/lock, CSRF/origin/mail durable side effects, generic unavailable/refusal; 3c delivered |
| PUT/PATCH /users; POST /users overrides; DELETE /users; GET /users/me/destroy/confirm | AuthAccount.Http / Destroy | current password/actor/CSRF/hosting/OIDC/key salt/remember/account deletion job; explicit confirmation, no secret retained state; 3c delivered |
| GET/POST /users/otp_challenge | AuthOtp.Http | OTP/backup codes/pending identity cookie, bounded attempts/time/lock; 3c delivered |
| GET /settings/two_factor (native HEAD); POST/DELETE /settings/two_factor; POST /settings/two_factor/verify | AuthTwoFactor.Http | method whitelist/body + QR/encryption/OTP/backup rotation/CSRF with signed actor; 3c delivered; action method matrix in Management/Closure tests |
| POST /users/auth/:provider; GET/POST /users/auth/:provider/callback; /users/auth/failure | AuthProvider.Http | github/google_oauth2/openid_connect configured providers, callback method/state/nonce/cookie/OIDC/host policy; 3c delivered; disabled providers fail locally |
| GET /users/auth/apple; POST /users/auth/apple/callback | AuthApple.Http | .html/.json/HEAD transport special handling, state/nonce/pending import/signature/cookie integrity; 3c delivered; local refusal |
| /auth/account_link, /auth/account_link/challenge, /auth/account_link/email | AuthAccountLink.Http closure | allowed methods/action CSRF/pending identity/current password/token/cookie rotation; 3c delivered; no raw credential assigns/logs |
| POST /api/v1/auth/login, /otp_challenge, /register, /google, /apple | AuthMobile.Http (plus AuthApi.Http login/OTP historical flow) | mobile/API JSON/auth active/OTP/provider errors and rate/body checks; retained external client protocol, independent of native UI; 3c delivered |
| GET/HEAD /auth/ios/success | AuthMobile.Success | token-present text/plain close-window or JSON success, HEAD no-body; retained mobile contract |
| POST /api/v1/subscriptions/callback | Api.SubscriptionsController | configured Manager JWT validation/issuer/audience/time/signature/event/actor and local JSON errors; retained external Manager contract |

Provider/callback signatures, signed storage URL bodies and mobile JSON are independently consumed protocol contracts with repository handler/test evidence. Third-party deployed client counts were not observed in this preparation task; absence is never inferred from repository search.

### E9. Cable channels, streams, frames and external-client disposition

`W/cable_routes.ex` exposes GET /cable (R row), HostAuthorization/ForceSSL/RateLimit then Rails-compatible ActionCable upgrade. Identity is a cookie actor or admitted shared grant; channel authorization is separate. `D/cable/channels.ex` accepts the names below, optionally prefixed `::`; unknown names ignored. `D/cable/frames.ex` retains welcome/ping/confirm_subscription/reject_subscription/disconnect(reason,reconnect)/message(identifier, raw JSON payload), JSON escaping and Rails byte compatibility. Native LiveView socket is a separate protocol. Client commands/identifier/ref semantics, origin/session/token/expiry/rate/message limits and fresh delivery consent remain in cable/identity/delivery tests. No wire samples contain tokens or signed capabilities here.

Proven clients below are repository browser consumers in the separately supported Rails artifact, not proof of independent third-party clients in production. External client deployment/usage is **unknown** (OD4); retain the transport contract until the controller explicitly resolves it. Once 4/5/6 removes the final native UI subscriber, recommend retiring native UI Turbo producers/CableTurbo presentation coupling, never dropping the shared protocol solely on a lexical scan. Family/public live-location JSON and user channel payloads have independent data semantics, so preserve their authorization/consent contracts.

| Channel | Stream name derivation | Proven repository consumer / external usage | Contract evidence | Disposition | Last native feature / audit owner |
| --- | --- | --- | --- | --- | --- |
| WIRE:PointsChannel | RailsMessages.broadcasting([points, User actor]) | app/javascript/maps_maplibre/channels/map_channel.js; app/channels/points_channel.rb; independent clients unknown | cable/channels_test `user channels stream the user's broadcasting and reject a share-only connection`; frames_test | retain user-scoped JSON wire; native UI subscription retires 6; OD4 unknown clients | 6; 7 B0/B2 |
| WIRE:TracksChannel | RailsMessages.broadcasting([tracks, User actor]) | maps_maplibre/channels/map_channel.js; app/channels/tracks_channel.rb; independent clients unknown | same user-channel/frames tests | retain user-scoped JSON wire; native UI subscription retires 6; OD4 unknown clients | 6; 7 B0/B2 |
| WIRE:ImportsChannel | RailsMessages.broadcasting([imports, User actor]) | app/channels/imports_channel.rb; app/views/imports/index.html.erb uses signed Turbo imports stream (different channel); no current explicit ImportsChannel browser subscription found; global channels/imports_channel.js is reference-only | user-channel/frames tests; imports lifecycle data tests | retain actor wire; 4 import and 6 map last subscribers; OD4 unknown clients | 4/6; 7 B0/B2 |
| WIRE:MapEditsChannel | RailsMessages.broadcasting([map_edits, User actor]) | app/channels/map_edits_channel.rb, maps_maplibre/channels/map_channel.js | user-channel/frames tests, map-edit effects | retain actor wire; native UI subscription retires 6; OD4 unknown clients | 6; 7 B0/B2 |
| WIRE:FamilyLocationsChannel | RailsMessages.broadcasting([family_locations, Family membership]) | app/javascript/channels/family_locations_channel.js; maps_maplibre/channels/map_channel.js; Rails FamilyLocationsChannel | channels_test family feature/membership + excludes viewer; identity/delivery revoke tests | retain membership/consent JSON; native browser runtime 4c/6 replaces registry; OD4 unknown clients | 4/6; 7 B0/B2 |
| WIRE:SharedLocationChannel | RailsMessages.broadcasting([shared_location, SharedLink admitted id]) | app/javascript/controllers/shared_live_map_controller.js; app/channels/shared_location_channel.rb | channels_test `shared location streams only the connection's own share, compared as a string`; identity/expiry tests | retain own-grant JSON; native public UI 6; OD4 unknown clients | 6; 7 B0/B2 |
| WIRE:Turbo::StreamsChannel | verified signed_stream_name; User notifications/imports/posters, Trip, import extraction names | app/views/shared/_navbar.html.erb:178; imports/index:43/show:11; trips/show:4; posters/_studio:390; signed stream consumers in separate Rails UI | channels_test verified signature; turbo_events/pg_turbo_events producer transaction tests; frames_test | unknown independent clients; retain signature wire pending OD4; recommend retire native UI Turbo relay after 4 notifications/imports, 5 trips, 6 poster/video | 4/5/6; 7 B0/B2 |
| WIRE:ApplicationCable::Channel | confirms only; no stream | base protocol supported by D/cable/channels.ex; no explicit repository subscription found | channels_test base confirm/unknown ignore; frames_test control bytes | unknown independent clients; retain base handshake pending OD4, explicit orphan candidate only for native UI | 7 B0/B2 |

Producer audit: `D/cable/turbo_events.ex` drains notification and trip durable events; `W/cable_turbo.ex` renders navbar badge/list and trip recalculation HTML. 4 owns notification/badge native delivery, 5b owns trip invalidation, 6 owns map/studio stream-free consumers. `D/cable.ex` generic `broadcast/turbo/refresh`, Bus/PgBus/PgStore, Frames and identity security cannot be retired with the web HTML renderer without an explicit consumer decision. Generic events remain durable/idempotent where the domain requires them. D3 context-to-web audit identifies the CableTurbo leak for that handoff.

### E10. Exact test-retarget and measurement handoff

No existing behavior cases/fixtures were removed or rewritten in B0. Existing Appendix B and the main retarget table remain the full historical corpus; these rows add exact source contracts for the route cleanup owner. Names in future B1/B2/B3 columns are planned successors, not tests claimed green here.

| Existing test/case | Retain or retarget | Named successor / measurement handoff |
| --- | --- | --- |
| native_m7_route_ledger_test `route ledger retains every compiled route and admission boundary` | B ledger reader, async; exact R method/path/action/session/pipeline/metadata set | regenerate R after integration without dropping admission/source references |
| same file `route ledger assigns every source macro and gate a retained contract` | B source macro + compiled gate coverage, async | retain through B1/B2/B3 and reconcile G/M on actual retired source |
| same file `external client ledger explicitly decides every implemented Cable channel` | B protocol decision reader, async; exactly all supported channel names | explicit OD4 disposition required before protocol deletion |
| standalone_api_gaps_test `standalone demo API reports existence and creates exactly once`, `standalone demo API removes only its own data and reports SQL errors`, `standalone digest generation matches rswag year shape validation conflicts and native jobs` | B effects/owner/job/rollback retained | B1 `all standalone API endpoints dispatch directly without ownership fallback`; preserve original JSON/effects fixtures |
| page_envelopes_test suffix/query aliases, public expiry/unlock and mixed MIME cases | B URL/privacy/MIME retained; M/C envelope only retires | B2 `HTML document aliases preserve filters privacy and admission`, `unsupported legacy frame formats fail locally without mutations` |
| channels_test five named cases (E9), frames_test `control frames equal Rails' bytes`, `a relayed message splices the raw payload and escapes the identifier as Rails does` | B signature/identity/family/wire unchanged | retained external protocol tests; feature native delivery names in D1 |
| auth_gate_test/auth_gate_endpoint_test + 3c native_auth_integration_test exact names in D1 | B cookies/HTTP/Mobile/API retained; C handback retires | B3 `native routes and refusals never contact a Rails upstream`; 3c auth native refusal/current salt tests |
| a12f3a_o_closure_test, a12f3b_s02_test | B register readers unchanged | controller C1 keeps difference/bug corpus; targeted on register changes |
| Gate extra read sites in E4 plus all P auth/body/rate/admission | telemetry must positively observe SQL, include static/connected/params/events and populated page states | B2 `removing route gates does not repeat native page queries`; D3 `query budget instrumentation observes actual mount and event reads`; source sites are not measured caps |

B0 verification and preparation limits are recorded in the implementation report. 332 compiled routes, 19 secondary API method/path definitions, all declared source macros and compiled metadata gates have named ownership; no code/route deletion. Native page runtime/assets, browser/390px, S1 attestations, external-client controller decision and numeric query caps remain their later task/stage gates. No pending branch handoff blocks ledger completion.

B0 restored verification: 64 targeted tests passed, seed 404, warnings-as-errors, including all three async ledger readers; route/macro/channel omission mutations each failed the owning test. A0 direct-upload/dynamic-import mutations were revalidated and restored. Changed scanner/test formatting passed. No full suite, browser lane or protected lifecycle change.

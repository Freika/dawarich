# Milestone 5 inventory and baseline

Planning-only inventory on application head `bdaa9aa363230857b5a96fe67eb1e6d10f7390b3`, 2026-10-10, following verified native milestone 3b. E2E sources inspected at `ff256e6fd6a8a50f3f05a9e5a1e9656ef5a47b2d`. Production code, permanent tests, schemas and parity registers are unchanged. Temporary measurement tests were removed before commit. This inventory is the input to the controller's milestone 5 plan, not approval to implement it.

## Contract and scope

Source scope: `docs/phoenix/native-frontend-contexts-plan-20261008.md:119` (data-heavy pages and LiveView lifecycle). ActionText was explicitly deferred here from milestone 3 (`native-m3b-inventory.md:90`, `:212`). ADR-0017 supersedes Rails markup parity; behaviour/data/API/privacy contracts remain. Rails is a whole-app fallback, not a per-page hand-back target.

Citation roots: **W/** = `app-phoenix/lib/dawarich_web/`; **D/** = `app-phoenix/lib/dawarich/`; **T/** = `app-phoenix/test/`; **E/** = the inspected standalone E2E repository. Rails citations are relative to the Rails repository. Kinds: **B** preserve behaviour; **M** replace markup/client bridge with named behaviour successors; **C** retire coexistence/hand-back assertions; **R** update route/ownership tables. Proposed interfaces, limits and decisions are explicitly proposals. Existing code/test locations below are observations, not promises about unseen cases.

## Route, session and write inventory

| Page/flow | GET owner and session | Commands / metadata | Sources |
| --- | --- | --- | --- |
| Points filters, sorting and pagination | `PointsLive.Index`, `/points`, hybrid `:rails_pages`, NativeAuth session payload but **LiveAuth** on-mount and `Layouts.root` | `/points/bulk_destroy` DELETE/POST → `PointListActions`, `:point_list_action`; point address HTTP frame and export actions are separate callers | W/rails_pages_routes.ex:40, :102; W/points_live/index.ex:15; W/page_routes.ex:26; W/map_frame_routes.ex:46 |
| Trips owned and family lists | `/trips` → `TripsLive.Index`, same hybrid session; `TripsGate.index?` metadata | Six owned rows and separately six family shares; create link enters form; preview maps embedded in cards | W/rails_pages_routes.ex:82; W/trips_live/index.ex:24; D/trip_list.ex:11; D/shared_links/family_audience.ex |
| Trip new/edit | `/trips/new`, `/trips/:id/edit` → `TripsLive.Form`, same session, `TripsGate.form?` | POST `/trips`, PATCH/PUT/member POST `/trips/:id` → `TripActions` in A8 pipeline; name/dates/rich description; preview map is M6 | W/rails_pages_routes.ex:86; W/trips_live/form.ex:7; W/a8_routes.ex:33; W/components/trip_form.ex:54 |
| Trip show and plain daily notes | `/trips/:id` → `TripsLive.Show`; `TripDocument` pre-render calculation path; `TripsGate.show?` | Recalculate/export/delete via `TripActions`; nested note POST/PATCH/PUT/DELETE/member POST via `TripNoteActions`; sharing creation belongs to M4 | W/trips_live/show.ex:15; W/trip_document.ex:59; W/a8_routes.ex:18, :36; D/trips/show_calculation.ex:22 |
| Visits navigation | `/visits` → `VisitsNavigation`, HTTP 302 to `/map/v2?panel=timeline&date=today&status=confirmed`; explicit empty status preserved | Single edit/delete, bulk update/delete and merge → `VisitActions`; there is **no Visits page LiveView** | W/visits_navigation.ex:10; W/a8_routes.ex:78, :116; T/dawarich_web/visits_navigation_test.exs:8 |
| Visit timeline/calendar; residency | `/map/timeline_feeds`, `/map/timeline_feeds/calendar`, `/map/residency` → `MapFrames`, `:rails_frame` | `Timeline.{Days,DayRows,MonthSummary}`, `Residency` data; frame rendering and map panel host currently intertwined | W/map_frame_routes.ex:17; W/map_frames.ex:79, :134; D/timeline/days.ex:11; D/residency.ex:22 |
| Stats index/year/month | `/stats`, `/stats/:year`, `/stats/:year/:month` → `StatsLive.{Index,Year,Month}`, hybrid `:rails_pages` | Update all or period via `StatsActions`; month sharing via `StatSharing`; source verbs in router include non-GET action methods | W/rails_pages_routes.ex:68; W/router.ex:189, :236; W/stats_actions.ex:11 |
| Insights overview/details | `/insights` → `InsightsLive.Index`; `/insights/details` → `InsightsLive.Details` in distinct `:insights_details` session/root selected by `InsightsFrame` | Details and residency fetched by lazy Turbo frames; `Details.load(fill: true)` may persist digest calculations during a read | W/insights_live/index.ex:15, :152; W/insights_live/details.ex:8; W/page_routes.ex:34; D/insights/details.ex:73 |
| Digests index/show | `/digests`, `/digests/:year` → `DigestsLive.{Index,Show}`, hybrid `:rails_pages` | POST generation, DELETE/member POST deletion → `DigestActions`; sharing → `DigestSharing` | W/rails_pages_routes.ex:76; W/router.ex:209, :235; D/digests/web_commands.ex:7 |
| Achievements collection/detail | `/achievements`, `/achievements/:key` → `AchievementsLive`, separate `:achievement_pages`, `AchievementSession`, **LiveAuth**, hybrid root; `AchievementInitial` preloads | Sharing toggle and unlock next/seen/dismiss HTTP commands; collection load may mark celebrations seen | W/achievement_routes.ex:26, :63; W/achievements_live.ex:20; W/achievement_initial.ex:17; D/achievements/collection.ex:74 |
| Public month/digest | `/shared/month/:uuid`, `/shared/digest/:uuid` → `SharedStatsPage`, ordinary HTTP, **no LiveView process** | Public owner, enable/expiry and entitlement checks; public month hexagon map remains M6; chart presentation M5 | W/router.ex:243; W/shared_stats_page.ex:22; D/stats/sharing.ex:37; D/digests/sharing.ex:91 |
| Public achievement/embed/image | `/shared/achievements/:uuid` (`?embed=1`), `/og.png` → `AchievementPublicPage`/`AchievementPublicImage`, ordinary HTTP | Preserve metadata, embed headers, owner locale, public refusal and PNG URLs | W/achievement_routes.ex:55; W/achievement_image_routes.ex:15; W/achievement_public_page.ex:29 |
| Public/family shared trip, track, live and timeline | `/s/:id` GET/HEAD, `/s/:id/unlock` POST → `SharedLinkPage`, ordinary HTTP | Active/revoked/expiry, phrase cookie, family audience, view count; page data via `SharedLinks.ResourcePage`; live/timeline/map/browser polling are M6 | W/a9_routes.ex:99; W/shared_link_page.ex:17, :76; D/shared_links/resource_page.ex:6 |

**Native admission gap to close, not assume solved:** `NativeAuth` assigns Scope once and tracks the URI; inherited `LiveAuth` rechecks existence only on `handle_event`, redirecting to the same path, without refreshing Scope, salt, entitlement or async delivery (`W/native_auth.ex:19`, `W/live_auth.ex:45`). M3b has a stronger feature-specific pattern: fresh actor + original identity checks and event/params/info/async admission (`D/admin/access.ex:10`, `W/admin_live_auth.ex`). M5 should add ordinary-data admission without making ordinary pages admin-only. Public HTTP handlers need per-request resource authorization; anonymous pages do not need a fabricated logged-in Scope.

**Mutation retirement trap:** VisitActions/MapFrames/A8 transport still has M6 map consumers; storage blob/representation/download and `/api/v1/*` paths have independent clients. Do not delete them when migrating a list, an editor, or an Insights fragment. M4 owns sharing management/exports infrastructure; M5 owns these pages' callers and public presentation, coordinating interface changes rather than implementing competing share actions.

## Domain query and presentation inventory

| Existing interface / coupling | Observation | Proposed target |
| --- | --- | --- |
| `PointList.load(user, params, now, opts)` | 50-row SQL page; imports selector reads every owned import; depends on web `TripsGate` for page casting | Scoped Points page/selection/address operations; one URL normalization, retain bounded 50-row assigns; selector must be searchable/bounded without losing selection (D/point_list.ex:6, :40, :61, :133) |
| `TripList.load`, `TripPage.load` | Six rows but plan and timezone work per card; show projection includes path JSON, studio and raw API key; calls `TripPlanItems.prepare` in domain | Scope-taking Trips interface; batched list projections, separate bounded summary/days from map/studio data; web presenter owns display/helper/URL work (D/trip_list.ex:59; D/trip_page.ex:100, :135) |
| `TripDays.day_data` / `Trips.Queries` | Purpose-built multi-device windows and PostGIS distance queries; retain calculation semantics | Async bounded read or persisted versioned day-summary work, independent of MapLibre hook (D/trip_days.ex:61; D/trips/queries.ex:17, :38) |
| `Stats`, `Insights`, `Digests` | Stats reads persisted rows; Insights/Digests use web params/format/errors; overview and details each read all owner stats | Cohesive analytics interfaces with Scope, typed periods, SQL projections and separate presentation; reduce repeated full-stat reads without schema-per-table rewrite (D/stats.ex:24; D/insights.ex:7, :91; D/digests.ex:11, :14) |
| `Insights.Details` and `Details.Digests` | `fill: true` calls yearly/monthly `Digests.Calculation` on cold/stale state; overview does not itself fill | Read returns ready/pending/failed projection plus revision; durable deduped refresh outside mount/task SQL locks (D/insights/details.ex:77, :93; D/insights/details/digests.ex:30, :49) |
| `Insights.Fragments` | Domain renders web HEEx into six Rails HTML fragments; keys include actor, locale, period, update stamp, unit, selected month; 24-hour TTL when writing | Native data cache, not cached markup; rendering moves to web. Preserve source values while replacing native cache namespace/readers (D/insights/fragments.ex:5, :16, :42) |
| `Digests.Generation/Execution` | Durable execution state machine already has receipt/period locks, generated/published states and mail publication | Reuse worker/outbox machinery; automatic page refresh must not send a manual-generation email accidentally; revision-sensitive work must rerun when inputs change (D/digests/generation.ex:15, :50; D/digests/execution.ex:7, :14) |
| `Timeline` / `Visits.Web*` | 31-day range limit for day feed, but row volume inside range not bounded; bulk selection capped at 500; scoped ownership/locks/rollback/cache effects exist | Scoped timeline read and Visits commands; bounded cursor pages/stream window, preserve day totals/calendar; native host activation is M6 (D/timeline/days.ex:8; D/timeline/day_rows.ex:64; D/visits/web_scope.ex:7, :25) |
| `Achievements.Collection` | Registry-driven collection/detail/filter/pagination; domain casts via web Params and writes celebration state on load | Scoped Achievements reads + explicit once-only celebration acknowledgement; keep existing claim/seen/dismiss token safety and public projections (D/achievements/collection.ex:5, :74, :230; D/achievements/deck.ex:8, :50) |
| Shared resource data | Description goes through RichContent; day stats/photos/notes honor share flags/privacy; `days` iterates full date range | Validated share-access projection with bounded days/photo pages, no socket path/key; preserve family/public distinction and server privacy at every data fetch (D/shared_links/resource_page.ex:40, :75, :105) |

**Source-domain references that need deliberate placement:** D/insights.ex:7; D/insights/details.ex:7, :15; D/insights/fragments.ex:5; D/digests.ex:11; D/digests/context.ex:34; D/digests/web_commands.ex:5; D/digests/sharing.ex:4; D/stats/web_commands.ex:4; D/trip_page.ex:100; D/trips/web_form.ex:81; D/trips/web_notes.ex:119; D/trips/web_export.ex:44; D/trips/attachments.ex:5; D/achievements/collection.ex:230; D/achievements/public_card.ex:4. Move presentation to W/, pure casts/locale/time helpers to D/; storage URL/signing stays an explicit adapter. API closure helpers and infrastructure are separate contracts: do not remove them mechanically because their names contain Rails/web.

## Behaviour and existing coverage

### Points and Visits

| Behaviour | Kind | Current covering test file:case / source | Plan responsibility |
| --- | --- | --- | --- |
| Owner-only inclusive point bounds, default calendar month, import range before plan window, 50 rows, Lite cutoff | B | T/dawarich/point_list_test.exs:38, :45, :62, :82 | Points domain + native list |
| Filter/pagination/order navigation; bulk own deletion with filters; empty selection vs unmatched IDs; formatting coordinates/speed/local seconds | B; M form/bridge | T/dawarich_web/points_live_test.exs:37, :128, :206; T/dawarich_web/point_list_actions_test.exs:36, :59; E/points/list.spec.js:9 | Native list/events; exports context from M4 |
| Selection survives join, resets for changed page; bulk server IDs remain untrusted | B; M ignored island | T/dawarich_web/points_live_test.exs:183; W/components/point_list_table.ex:28 | Stable IDs/selection policy, no controller registry |
| Geocoding column/address ownership; malformed dates/settings/IDs and signed-out return URL | B; C handback | T/dawarich_web/points_live_test.exs:222, :291, :334, :379; D/point_list.ex:30 | Typed native refusal and address HTTP behavior |
| Visits default/empty/requested status redirects | B/R | T/dawarich_web/visits_navigation_test.exs:8, :23; E/visits/navigation.spec.js:7 | Keep public HTTP navigation |
| Single edit/delete, bulk max 500, unsupported source, owner/plan scope, same-day merge, calendar invalidation across old/new day, effects rollback | B; M stream response | T/dawarich_web/visit_actions_test.exs:139, :167, :183, :191, :250; T/dawarich_web/visit_writes_regression_test.exs; D/visits/web_update.ex:81, :94; D/visits/web_merge.ex:37 | Scoped commands/data now; M6 host/browser binding |
| Local midnight/DST, interleaved tracks/visits, continuation ordering, suggestions, 31-day maximum and calendar heat | B | T/dawarich/timeline/days_test.exs:30, :126, :200, :250; T/dawarich/timeline/month_summary_test.exs:14, :23, :82 | Preserve queries; explicit row/resource bound proposal |

### Trips, ActionText and daily plain notes

| Behaviour | Kind | Current covering test file:case / source | Plan responsibility |
| --- | --- | --- | --- |
| Owned/family pagination, six rows, new/empty/calculating/future states, dates/duration/countries/units/plans/share badges | B; M preview DOM | T/dawarich_web/trips_live_test.exs:89, :129, :314, :376; T/dawarich/trip_gate_test.exs:143; E/trips/lifecycle.spec.js:14 | Trips read/context and native ordinary page; preview host M6 |
| Create/edit validation, active-create gate, demo adoption, atomic description/attachment graph, callback/recalculation rollback | B; M HTTP form | T/dawarich/trips/web_params_test.exs:41; T/dawarich/trips/web_write_test.exs:106; T/dawarich_web/standalone_trip_form_test.exs:44 | Native Scope commands/form |
| 60-second recalculation cooldown, concurrent retry, export formats, deletion graph and storage-first purge | B | T/dawarich_web/trip_recalculate_test.exs; T/dawarich_web/trip_export_test.exs; T/dawarich/trips/review_findings_test.exs:47; D/trips/show_calculation.ex:22 | Durable operations; HTTP downloads remain |
| Canonical description and sanitized private/public rendering; HTML links, image/file attachments, galleries, captions, nullable dimensions | B; M ActionText runtime | T/dawarich/trips/rich_attachments_test.exs:219, :283, :325; T/dawarich/trip_description_test.exs:26; D/shared_links/resource_page.ex:68 | Focused editor/attachment hook and adapter, adversarial public rendering successor |
| Signed/pending/invalid attachment capability; identify/analyse; removed embeds keep shared blobs; nil/empty retains embeds until replacement | B | T/dawarich/trips/rich_attachments_test.exs:47, :172; T/dawarich/trips/review_findings_test.exs:146, :279 | Preserve data/cleanup; test owned new upload separately from legacy attachable capability |
| Daily note owner scope/noon/date casts/upsert/unique-date race, cancel/reopen | B; M frame replacement | T/dawarich/trips/web_notes_test.exs:78, :127; T/dawarich_web/trip_note_actions_test.exs:74; E/v2/trip-notes.spec.js:40 | Plain LiveView forms, not rich-text editor |
| Trip stream calculation updates; no retained path once rendered | B result/bound; M Turbo channel | T/dawarich_web/trips_live_test.exs:463, :473; W/trips_live/show.ex:45 | Authorized native PubSub result delivery; M6 map revision handoff |

**Rich-text contract:** Rails has one `has_rich_text`, `Trip.description` (`app/models/trip.rb:15`). Keep `action_text_rich_texts` and ActiveStorage graph data, including legacy Note/Place cleanup constraints; replace the JS integration, not the stored format. `RichContent` limits input to 2 MiB and canonical depth to 64 (`D/trips/rich_content.ex:11, :58`). `Attachments.resolve(repo, sgid)` has no actor argument and checks signed capability/pending metadata (`D/trips/attachments.ex:7, :15`); new-upload receipts already provide `owned?/3` (`D/storage/upload_receipts.ex:12`). Capability possession alone is not evidence of a demonstrated Rails defect. Controller must decide new upload binding and legacy re-edit policy; tests must cover cross-owner attach, expired/invalid capability, pending purge, rollback, cancellation and no removal of another owner's attachment.

### Stats, Insights and Digests

| Behaviour | Kind | Current covering test file:case / source | Plan responsibility |
| --- | --- | --- | --- |
| Year/month/user window, local cutoff, all-time totals, year chart outside card window, absent month, previous month/average, geography | B | T/dawarich/stats_test.exs:29, :43, :52, :99, :109, :210; T/dawarich_web/stats_live_test.exs:216, :301, :310 | Scoped analytics reads and presentation |
| Recalculation publication, failure/retry, source notices/inactive refusal | B; M HTTP method links | W/stats_actions.ex:15; D/stats/web_commands.ex; E/stats/stats-actions.spec.js:8, :15 | Native events over existing durable producers |
| Insights default newest year, all-time, locked/restricted no patterns, heat/streak, no-stat wording, month switching | B; M lazy frames | T/dawarich/insights_test.exs:80, :86, :104, :118; T/dawarich_web/insights_live_test.exs:46, :71, :80, :87; E/stats/insights-details.spec.js:33 | URL source of state; connected-only async details/residency |
| Yearly/monthly stale/equal/missing/cached nil/corrupt/cache outage; six fragments, TTL, key isolation | B values/expiry/error; M HTML cache; C handback | T/dawarich/insights_details_db_test.exs:21, :162, :190, :282, :340; T/dawarich_web/insights_endpoint_test.exs:195, :223, :236 | Persist through durable jobs; native data cache and loading/failure states |
| Digest past/current year availability, active-only generation, totals/full-vs-Lite, missing/foreign, delete only selected year | B; M form/chart | T/dawarich_web/digests_live_test.exs:42, :67, :80, :100, :131; T/dawarich/digests/generation_test.exs; E/stats/digests-current-year.spec.js | Scoped list/show/events, bounded persisted projection |
| Shared month/digest enabled/expiry including DST and legacy formats, deleted vs login-locked owner, no private API key | B | T/dawarich_web/public_share_owner_test.exs:38, :73; T/dawarich_web/public_share_expiry_test.exs:38, :73, :126; E/sharing/reports.spec.js:15, :64 | Ordinary HTTP, public presentation authorization before cache/data |

### Achievements and other public/shared views

| Behaviour | Kind | Current covering test file:case / source | Plan responsibility |
| --- | --- | --- | --- |
| Collection/detail filters, parent redirects, region/country cards, silhouettes, locale and pagination; untouched missing exploration | B; M ignored modal island | T/dawarich/achievements/collection_test.exs; T/dawarich_web/achievements_live_test.exs:72, :93; E/achievements/collection.spec.js:11 | Native context/page, server-rendered card dialog |
| Sharing create/revoke and owner-only disclosure; modal keyboard/Escape/backdrop/focus/clipboard | B; M card portal and HTTP form | T/dawarich_web/achievement_sharing_test.exs:105, :194; D/achievements/sharing.ex:7; app/javascript/controllers/card_modal_controller.js:60, :86, :90 | Scoped events + existing native dialog/Clipboard |
| Unlock claim/seen/dismiss/reconnect/two-tab lease and once-only celebration | B; M controller/markup | T/dawarich/achievements/deck_claim_test.exs; T/dawarich/achievements/deck_seen_test.exs; T/dawarich_web/achievement_unlocks_test.exs; E/achievements/unlock.spec.js; E/achievements/unlock-notifications.spec.js | Reuse native shell hook, preserve HTTP external caller where still used |
| Public achievement direct/embed metadata, no private chrome, HEAD, framing policy, image, disable/deleted owner | B; M recorded document | T/dawarich_web/achievement_public_test.exs:47, :101; T/dawarich_web/public_share_owner_test.exs:98; W/achievement_public_page.ex:29 | Native HTTP documents; no forced public LiveView |
| Shared phrase unlock, family consent/audience, expired/revoked/deleted resource, owner/privacy flags, view counting | B; M map document assets; C replay | T/dawarich_web/shared_link_cookie_test.exs; T/dawarich_web/sharing_endpoint_test.exs; T/dawarich_web/standalone_share_points_flow_test.exs; E/sharing/links.spec.js; E/v2/shared-trip-link.spec.js:7 | M4 share commands, M5 bounded presentation/authorization, M6 map/live hooks |

## Frontend dependencies and milestone 6 boundary

| Reachable mechanism | M5 replacement | M6 owner |
| --- | --- | --- |
| Points `checkbox-select-all`, GET/date/order controls and Turbo bulk/exports links | Phoenix JS/selection state, native submit/patch, durable export request (W/components/point_list_controls.ex:25, :106; W/components/point_list_table.ex:28) | Bbox map selection/address popup host |
| Trip `datetime`, `trix` + `@rails/actiontext`, ignored MapShell | Native date form + focused **Trix-only** lazy hook is a proposed default; native upload adapter; editor owns only its DOM (W/trips_live/form.ex:24; W/components/trip_form.ex:86, :154; W/layouts/root.html.heex:53) | `trip-maplibre-preview`, MapShell replacement and route integration |
| Trip show `trip-maplibre`, `trip-plan-focus`, replay, poster/video | Native summary/notes/ordinary toolbar and calculation state; small revision/id-only interface | All maps/plan focus/photos overlays, replay/studios/browser exports (W/trips_live/show.ex:53, :69, :124; W/components/trip_itinerary_day.ex:53) |
| `Chartkick` inline scripts/importmap/Turbo preview checks | Focused lazy chart hook, stable ID/revision, bounded JSON data; public HTTP chart initializer over same adapter | Month peak-day map, hexagons, public stat map (W/components/chartkick.ex:26; W/components/stats_month.ex:64; W/components/public_month.ex:88) |
| `activity-heatmap` ignored island | Native links/accessibility and focused tooltip hook only if needed; preserve zoned day link/streak logic | Navigation destination map and map panel lifecycle (W/components/heatmap_parts.ex:29; app/javascript/controllers/activity_heatmap_controller.js:11) |
| Insights `insights_details` + `residency-content` lazy Turbo frames | `start_async`/`assign_async` with separate loading/error/revision state, native details/residency components | Residency map visualisation if any; **country/day table is M5** (W/insights_live/index.ex:152; D/residency.ex:43) |
| Achievements `card-modal` portal, sharing controls | Native dialog/JS/Clipboard, scoped events, lifecycle cleanup; native shell unlock integration | No map rewrite needed; silhouette/OG algorithms retained |
| Public shared trip/track/timeline/live document map startup/polling | Authorized bounded non-map data/metadata/description, native HTTP templates ready for map hook | MapLibre, live-location fetch/poll/reconnect, viewport/privacy layers and map resources (W/shared_pages.ex:35; W/shared_pages/live.html.heex; W/shared_pages/timeline.html.heex) |

**Activation dependency:** standing zero-Hotwire rule and map deferral cannot both be satisfied by keeping a RailsStimulus island inside a supposedly migrated Trip/month/public page. Proposed default: M5 implements/tests the non-map slices and M6 supplies the native host before those mixed routes switch atomically. No alternate coexistence lane, temporary loss of maps, or fake Hotwire-free assertion. Controller must approve the activation order. M5 acceptance records route readiness and waits for the M6 host where necessary; a page whose native map is absent cannot be marked fully migrated. Points, stats index/year, Insights, Digests, Achievements and public digest/achievement can switch independently.

## Cache TTL, invalidation and isolation inventory

| Cache/work | Observed contract | Planning requirement |
| --- | --- | --- |
| Native summary/tracked months | `Cache.Readers` user keys, signature, 86,400 s Redis TTL; transaction-visible versioning; SQL reads still obtain signature | Reuse isolation/invalidation, add bounded payload admission; no sensitive settings or secret-bearing User serialization (D/cache/readers.ex:7, :41, :95, :127) |
| Native yearly digest | 3,600 s TTL; `yearly` invokes compute **before** cache comparison | Cache warming is not proof that mount skips computation; read persisted revision and queue refresh separately (D/cache/readers.ex:24; D/insights/details/digests.ex:35) |
| Stats point counts | 86,400 s durable cached generation via jobs repo, counts may write on cold GET | Track separately from Repo telemetry, queue heavy counts; loading semantics need controller decision (D/stats/point_counts.ex:6, :9, :57) |
| Six Insights Rails fragments | 86,400 s, source key includes user/locale/year/month/unit/stat stamp; HTML snapshots can dominate data | Do not share translated HTML across native users; new namespace and typed versioned payload (D/insights/fragments.ex:33, :42) |
| Stats/visit invalidation | Stats after-commit visibility epochs + Redis UNLINK/SCAN; Visits calendar updates old/new months | Late cache writes must not resurrect prior generation; public revocation is checked separately before serving cache (D/stats/cache_invalidation.ex:5, :15; D/visits/calendar.ex:31) |
| Trip day stats | Rails cache uses trip update, max point update, timezone, gap settings, TTL one hour; Phoenix day SQL directly computes | Preserve key inputs and multi-device logic; data caching/persisted work belongs M5, map paths do not (app/controllers/trips_controller.rb:165; D/trip_days.ex:61) |
| Public resources | Share checks are per request; owner policy differs from interactive login; /s GET counts a view | Public key includes share/resource revision and audience/privacy flags; do not cache phrase tokens, family authorization or URLs with secrets; never serve after revoke (W/shared_link_page.ex:17, :76; W/shared_stats_page.ex:22) |

Proposed explicit limits need measurement/approval: native cache value ≤1 MiB (oversize bypass cache and use bounded query projection), chart ≤366 daily/12 monthly buckets per series, heatmap ≤366 dates, 50 Points rows, six owned/six family Trips cards; growing day/timeline/photo collections use cursor/stream windows instead of full paths or unbounded day/date arrays. Existing 2 MiB rich-text input limit is separate from ordinary chart/event budgets. Do not truncate stored rich text to fit an assign/cache limit.

## Mount/request query baseline

Temporary `NativeM5MeasurementTest`, two repetitions per route, seed 404, Elixir 1.20.4/OTP 27, reduced two schedulers, standalone self-hosted. Repo SQL telemetry `[:dawarich,:repo,:query]` uses `T/support/native_admin_ui.ex:77`; connect the **same** static response with `live(conn, nil, on_error: :warn)`, then stop each owned view. Rows are synthetic: one active owner, 51 points, 21 calculated four-day trips with simple paths, one simple description, three monthly stats across two years, one complete yearly digest, one public trip link and one publicly shared achievement. No real traces, attachment storage/provider calls, family graph, visit rows or extra trackers were loaded.

Counters assert nonzero SQL for each real data page. The zero-query Visits redirect has its exact Location asserted. RED with disabled counter/wrong redirect target, GREEN, named mutations and restored GREEN validate measurement integrity; evidence lives in the controller report. Counts include transactions observed on **Repo**, but exclude fixture seeding, Redis, SQL through other repos, jobs, browser map/chart fetches and lazy frame requests. First/repeat is within one page's test; first is not guaranteed machine-wide cold. These are measured baselines, not capacity/SLOs or native final budgets. Idle-render counts are zero for all measured LiveViews; this does **not** measure ten-second navbar timers or long-lived socket memory.

| Route / synthetic state | First static / HTTP | Connected | Repeat static / HTTP | Repeat connected | Repo writes (first / repeat) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `/insights/details?year=2024` | 69 | 25 | 27 | 25 | 3 / 0 |
| `/shared/month/:uuid` | 6 | — | 6 | — | 0 / 0 |
| `/shared/achievements/:uuid` | 4 | — | 3 | — | 0 / 0 |
| `/achievements/country_de` | 15 | 9 | 13 | 9 | 0 / 0 |
| `/s/:uuid` | 14 | — | 14 | — | 1 / 1 |
| `/digests` | 8 | 8 | 8 | 8 | 0 / 0 |
| `/map/residency?year=2024` | 7 | — | 7 | — | 0 / 0 |
| `/points?start_at=1709251200&end_at=1711929600` | 29 | 15 | 29 | 15 | 0 / 0 |
| `/stats/2024/03` | 7 | 7 | 7 | 7 | 0 / 0 |
| `/insights?year=2024` | 6 | 6 | 6 | 6 | 0 / 0 |
| `/trips/:id/edit` | 43 | 16 | 43 | 16 | 0 / 0 |
| `/achievements` | 18 | 7 | 11 | 7 | 0 / 0 |
| `/insights?year=all` | 6 | 6 | 6 | 6 | 0 / 0 |
| `/stats/2024` | 6 | 6 | 6 | 6 | 0 / 0 |
| `/trips` | 86 | 67 | 86 | 67 | 0 / 0 |
| `/shared/digest/:uuid` | 4 | — | 4 | — | 0 / 0 |
| `/visits` | 0 | — | 0 | — | 0 / 0 |
| `/trips/new` | 7 | 4 | 7 | 4 | 0 / 0 |
| `/map/timeline_feeds/calendar?date=2024-03-09&status=confirmed` | 7 | — | 7 | — | 0 / 0 |
| `/map/timeline_feeds?date=2024-03-09&status=confirmed` | 13 | — | 13 | — | 0 / 0 |
| `/digests/2024` | 6 | 6 | 6 | 6 | 0 / 0 |
| `/trips/:id` | 35 | 22 | 35 | 22 | 0 / 0 |
| `/stats` | 13 | 11 | 11 | 11 | 0 / 0 |

Observations: large Trips list/edit counts include legacy gate/projection duplication; investigate batching before setting native budgets. Cold Insights detail writes digests while rendering a GET. A calculated Trip fixture avoids the independent `TripDocument` recalculation producer: missing-data/show behavior must be measured/tested separately with the proper native job ownership. Public /s performs one view-counter write per GET. First-request extra reads on Stats/Achievements/public pages are observed; their cause is not asserted.

The timeline endpoint baseline used `date` (not its actual `start_at`/`end_at` window input, W/map_frames.ex:79), so it measures the empty/default-day request. A populated, correctly ranged timeline with visits, tracks and DST is a required implementation baseline, not represented by these counts.

Browser JS bytes, auth-inclusive per-event/parameter SQL, provider/attachment-rich queries, idle connection memory and navigation-retention measurements were **not run** in this planning phase; acceptance must measure them on the production standalone stand. Reference only: verified M3b ordinary admin pages loaded 162.8–163.3 KB decoded, experimental adds lazy MapLibre (`native-m3b-inventory.md:9`). Do not substitute those bytes for M5 measurements.

## Affected tests, browser coverage and fixtures

### ExUnit and direct callers

Run changed-module tests plus direct callers found with `rg`, not a speculative full-suite fix round. Main families: T/dawarich/{point_list,trip_gate,trip_days,stats,insights,insights_details_db,digests,residency}_test.exs; T/dawarich/{trips,stats,digests,achievements,timeline,cache}/; T/dawarich_web/{points_live,point_list_actions,point_exports_direct,trip_forms_actions,trip_form_navigation,standalone_trip_form,trips_live,trip_missing_data,trip_itinerary,trip_shared_components,trip_recalculate,trip_export,trip_note_actions,visit_actions,visit_writes_regression,visits_navigation,stats_live,stats_parity,insights_live,insights_endpoint,insights_frame,insights_details_parity,digests_live,achievements_live,achievements_parity,achievement_public,achievement_sharing,achievement_unlocks,public_share_owner,public_share_expiry,sharing_endpoint,sharing_parity,shared_link_cookie,standalone_share_points_flow}_test.exs.

Route/gate consumers: T/dawarich_web/{page_routes,page_envelopes,rails_page,a8_routes,a8_request,a8_gate_endpoint,a8_remaining_request,a8_remaining_parity,a8_videos_visits_parity,a9_routes,a10c_routes,a10c_ownership,standalone_html_pages,standalone_auth_pages,map_frames_endpoint,map_frames_regression,storage_routes,native_pages_hotwire_free}_test.exs. Reconcile only touched rows; keep unconverted M6 and independent API/wire tests. Point address HTTP coverage is in `map_frames_endpoint_test.exs` and point-list behaviour tests; expand brace families before running a batch.

Registers: ED + FRB/CHANGELOG are owner-controlled appends during implementation only. Reader tests include T/dawarich_web/a12f3a_o_closure_test.exs:867 and T/dawarich_web/a12f3b_s02_test.exs:654; use `rg` to identify additional readers. Shared test fakes/seams belong `T/support/`, not inside a test module that another partition imports.

### Standalone E2E

| Feature | Existing spec sources | Missing named browser contracts to add |
| --- | --- | --- |
| Points | E/points/list.spec.js:9 | Native patch/back/forward, selection reset and reconnect, bulk error/cancel, loading/event refusal |
| Trips/editor/notes | E/trips/lifecycle.spec.js:14; E/v2/trip-notes.spec.js:40; E/trips/export.spec.js; E/v2/shared-trip-link.spec.js:7 | **E/trips/rich-description.spec.js** (new): formatting/links/paste, attachment image/file/gallery/caption round trip, upload fail/cancel/retry, saved sanitized private/public output, cross-owner refusal; no existing dedicated rich attachment editor spec found |
| Stats/Insights/Digests | E/stats/{stats-index,stats-year-month,stats-actions,insights,insights-details,digests,digests-current-year,empty-state}.spec.js | **E/stats/native-lifecycle.spec.js** (new): rapid year/month change, stale result/old timeout, pending-to-ready/retry/reconnect, chart/heatmap cleanup and URL history |
| Achievements | E/achievements/{collection,unlock,unlock-notifications}.spec.js | Native dialog keyboard/focus/clipboard; revoke from another tab; no double celebration or claim |
| Public | E/sharing/{reports,links,track}.spec.js; E/v2/shared-trip-link.spec.js | **E/sharing/native-public-pages.spec.js** (new): native HTTP digest/achievement/embed metadata, expiry/revoke/cache privacy; map assertions remain M6 |
| Assets/layout | Existing native asset lanes from Tags/settings/admin | **E/native/m5-assets.spec.js** (new): eager/lazy graph bytes per route, no Hotwire after editor/chart mount, isolated Phoenix production build |

Mixed map specs remain full-lane regressions and cannot be weakened to make M5 pass. M6 activation is a synchronization dependency for mixed-route browser assertions.

### Recorded fixtures/readers

| Corpora (T/fixtures symlink into E2E-owned phoenix-fixtures) | Current reader / disposition |
| --- | --- |
| `trips/{seed,pages,descriptions}.json`, `trips/pages/*.html`, `trips/remaining/*` | T/dawarich/trip_description_test.exs; T/dawarich_web/{trips_index_parity,trips_show_parity,trip_forms_actions,trip_note_actions}_test.exs: retain values/effects/validation, replace exact HTML assertions |
| `stats/*`, `insights/*`, `rails_cache/*` | T/dawarich_web/{stats_parity,insights_details_parity}_test.exs; T/dawarich/insights_details_db_test.exs: preserve data/codec contracts for remaining consumers, retire native HTML cache oracle |
| `achievements_ui/*`, `achievement_public/*`, `sharing/*` | T/dawarich_web/{achievements_parity,achievement_public,sharing_parity}_test.exs: named behavioural text/metadata/owner/headers replacements |
| `map_frames/*`, `a8vv/visits/*`, `map_writes/points/*` | T/dawarich_web/{map_frames_parity,visit_actions,map_writes_parity}_test.exs: shared M6/API consumers, no bulk pruning |
| `standalone/html_pages.json`, `page_envelopes/*` | Shared router/standalone tests: edit migrated route rows only; preserve API/external session/wire/cookie fixtures |

Fixture directory names are discovery families, not an instruction to delete. Audit exact file readers before pruning. E2E-owned orphan HTML is changed only by its fixture owner in that repository; never mutate a symlink target from the app worktree. No corpus was regenerated here.

## Proposed split and decisions for the controller

Four implementation tracks, with the controller owning shared files: C foundation/widgets/Achievements/public + acceptance; A Points/Visits; B Trips/editor; D Stats/Insights/Digests/cache. Domain-first tracks can proceed after shared admission/result contracts; UI changes wait for foundation. Map-host activation and M4 sharing/upload interface readiness are explicit synchronization points, not implicit exceptions to ADR-0017.

## Open decisions

1. **Mixed-route activation order. Recommended:** M5 supplies ordinary data/components/editor, M6 supplies native map hosts, then routes switch atomically. Preserve current maps and zero-Hotwire rule; controller chooses interleaving or postpones final M5 route acceptance until host readiness.
2. **Editor choice. Recommended:** preserve Trix editing features with a dynamically imported Trix-only hook and a Phoenix upload adapter, no `@rails/actiontext`/ActiveStorage JS. Store canonical ActionText HTML unchanged. Replacing the editing model wholesale adds format/round-trip risk.
3. **New vs legacy attachment admission. Recommended:** newly uploaded blobs bind to actor receipt; legacy blobs already attached to the owned description round-trip; independently signed attachable capabilities retain source behavior until controller resolves cross-owner policy. No silent rejection/data loss for old descriptions. Any approved stricter rule gets ED; a demonstrated Rails defect fixed gets FRB too.
4. **Cold/stale calculation UX. Recommended:** light totals/server shell immediately; connected read returns pending and requests one durable refresh, shows last ready revision when available, explicit failure/retry. No expensive calculation in either mount. Manual digest generation keeps source notices/email policy; automatic refresh does not send manual-generation mail.
5. **Bounds and unknown inputs. Recommended:** preserve source Ruby casts/empty/out-of-range/filter defaults, owner-local zones and Lite windows; malformed shape becomes native typed refusal. Keep page sizes 50/6, chart/day bounds above; paginate large selectors/day lists rather than lose records. Controller approves new resource budgets and any deterministic tie rule (ED for changed order).
6. **Public rendering. Recommended:** ordinary native HTTP for public digest/month/achievement/shared document and phrase unlock; no public LiveView merely to display persisted data. Browser-only chart initializer shares the chart adapter; public authorization checked before cache and each API fetch. M6 owns live-location/map subscriptions.

## Risks

- Map deferral is the main route-activation dependency; an ignored Hotwire island would contradict the standing decision.
- Attachment ownership/legacy capabilities, pending purge and shared graph cleanup need adversarial tests before changing semantics.
- Durable digest execution keys describe a period/receipt, not a new stat revision automatically; a published period must not suppress future refresh forever. Existing mail/retry semantics must survive.
- Cache warm TTL alone does not skip compute; transaction visibility and generation-safe late writes matter. Public revocation must bypass cache regardless of TTL.
- Parameter parsing currently raises or hands back in many cases; typed refusals need their own destinations and preserved failure messages, without same-URL loops.
- Sparse measurement excludes jobs repo counts, uploads, populated visits/family, browser fetches and idle timers; native budgets need those observations.
- Historical M3a acceptance once missed a whole test partition; M5 must require all three exit summaries, never a combined total alone.

## Results after implementation / spec-verify

Pending. This inventory records pre-change observations only. Record final app/E2E SHAs, full ExUnit seeds 404/202 with all partition exits, three sequential full G44 lanes, query/event/async/idle measurements, JS decoded/wire bytes and loaded graph, mechanical exits, EN/DE 390 px, stand identity, named mutation evidence, test retargets, map-boundary readiness and AFFiNE mirror here during implementation.

## Rails bugs fixed (changelog)

none — this planning phase changed no production behaviour. The reported query/ownership concerns are planning findings, not newly registered fixes. Any implementation that fixes a demonstrated Rails defect must add FRB, ED and source/test citations in its report.

## Unlock gateway coverage (integration review fix)

POST `/s/:id/unlock` is a phrase capability gateway: `SharedLinks.active`, `FamilyAudience.accessible?` and secure phrase comparison precede cookie issuance. Its successful response is an empty redirect; shared-payload `Delivery` bypass coverage is inapplicable. Named successor: `a12f3b_s01_test` “POST unlock refuses shared audience admission before issuing a phrase cookie”. The shared-admission gateway bypass mutation skips the POST audience predicate and fails this case (302 instead of 404). Positive cookie/redirect, wrong phrase and no-cookie/no-view-touch controls remain.

## Integration handoff (2026-10-10)

The baseline above remains a historical pre-change census. Current native ownership, retained callers, named transport-test successors and adapter limitations are recorded in [native-m5-integration.md](native-m5-integration.md). Public digest and achievement HTML now route to NativePublicPage using the native public HTTP pipeline; month/shared map documents retain their milestone 6 owners. The public route manifest and revocation/expiry/deletion/HEAD tests remain the delivery gate. Full and browser acceptance are pending the controller's X5 stage; no acceptance measurements are claimed.

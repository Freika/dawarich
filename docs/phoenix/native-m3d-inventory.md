# Native milestone 3d: Places and ordinary forms

Implementation status: C0/A1–A3/B1–B4/C1–C3 complete; controller FULL GATE and stage acceptance pending.

## Frozen contracts

Controller decisions O1–O7 in the approved milestone plan are binding. Create, edit and details are dialogs on `/places`; no new member navigation routes. The native host calls `Dawarich.Places` with `Accounts.Scope`. Ordinary signed-in Cloud accounts are allowed. Map HTTP/frame/stream transports stay until milestone 6.

Native operations: `list(scope, page)`, `detail(scope, id)`, `edit(scope, id)`, `change(scope, data, attrs)`, `create(scope, attrs)`, `update(scope, id, attrs)`, `delete(scope, id)`, `nearby(scope, params)`. Optional server-only test options never come from event params. Reads return `{:ok, projection}`. Writes return `{:ok, %{id: id}}`, delete `{:ok, id}`. Validation returns `{:error, changeset}`. Other results are `{:error, reason}` with bounded reasons stale_session, not_found, invalid_input, unsupported, unavailable, foreign_dependents. Partial persistence returns `{:partial, %{id: id}, :tags_failed}`. Record, adoption and tags remain separate phases; saved identity consumes the create generation.

Ordinary state: server-generated instance id/generation, changeset/form, idle/saving/accepted/partial status, selected confirmation and errors. The server binds the target and consumes each accepted generation once. Zero-effect validation failures may retry. Reopen starts a fresh generation; reconnect never submits automatically. No cross-socket durability claim.

Native events: validate_place, save_place, save_place_note, request_delete, confirm_delete, nearby, select_nearby, cancel_form. Event generation and suggestion index select server state; they grant no authority. Future native map notification contract: `place:changed`, version 1, payload `%{version: 1, id: id, operation: create | update | delete}` after authoritative reload; no provider payload or hidden HTML.

Nearby is connected-only with a 10 second watchdog, generation and per-run token, cancellation on coordinates/close/patch/replacement. Provider failures remain empty; watchdog/crash becomes a generic retryable alert. Suggestions contain only name, coordinates, street/city/country/index.

## Route and format matrix verified in C1

| Request | Native outcome |
| --- | --- |
| Signed-in GET/HEAD `/places`, HTML/default accept | 200 native shell; HEAD empty body |
| Anonymous HTML `/places` | 302 full sign-in re-entry |
| Scalar page including Ruby-cast suffix, benign scalar query | 200; raw page/query preserved |
| Nested page, huge page, unsupported settings/read failure | In-place typed alert, no upstream or same-URL redirect |
| JSON accept or `format=json` | Local 406 |
| `/places.json`, absent dialog routes | Local 404 |
| X-Requested-With / Turbo-Frame on list | Full native page, never fragment |
| Owned direct member HTML | 302 `/map/v2?place_id=:id` |
| Owned member with exactly one place-drawer header | 200 retained map frame |
| Missing/foreign/malformed/overflow member | Local 404 |
| Unknown member frame header / repeated raw member frame header | Local 302 map redirect / 500 refusal; never native dialog |
| Retained member X-Dawarich-Client / drawer disappearance after read admission | Local 500 / 422 refusal; no replay |
| Nearby missing coords | 400 retained map adapter |
| Nearby valid coords/legacy casts/extra scalar query | 200 retained map fragment |
| Retained writes | Existing CSRF/origin/method/body/format protection and effects; native list uses zero HTTP writes |

## Measurement method

Historical provenance: native-m3b-inventory.md, finished 3a, synthetic one-place dataset, main Repo only: list 9 static/5 connected; out-of-range 9/5; direct/drawer/nearby HTTP 4/7/5. These are historical, not current gates. Native admin measured 2 JS requests, 162.8–163.3 KB decoded and about 50.3 KB wire. Measure incremental eager graph through esbuild metafile with a 2 KB cap; no new browser library expected.

New measurements count all auth and main Repo work after setup, separate static/connected/params and list/delete/open/validate/save/note/detail. Seed at least 21 owned places, legacy coords, tied fifth visit cutoff, tags/notes, foreign dependents and partial/refusal cases. Nearby task counters include provider-call and cancellation evidence. Do not invent upper query limits before measuring or claim Redis/other repos are counted.

## Partition-safe test support

New cross-file helpers live in test/support: NativePlaces fixtures/connection and Repo telemetry helper, failing-tag repo, nearby deterministic message/barrier provider, OrdinaryFormLive owner harness. Test-local modules remain local. No provider configuration or credentials may enter LiveView assigns/messages/logs. Allocations and runtime identities stay in the external implementation report.

## Initial case dispositions


This is a case-level starting register, not permission to drop unlisted generated cases. C0/C2 enumerate every fixture case and assert coverage by name/effects id.

| Existing file:case/line | Kind and disposition | Named successor / owner |
| --- | --- | --- |
| `T/dawarich/place_list_test.exs:27,36,45,51,63,92,105` | B retain ordering/casts/coordinates/zone/empty/ownership | A1 `scoped Places reads preserve page casts coordinates and local dates`; existing B remains. |
| `place_list_test.exs:81,100`; `place_drawer_test.exs:179,187,199` | B refusal + C sentinel shape | A1 native typed edges; legacy sentinel tests stay while map needs them. Missing/foreign must stay unavailable. |
| `T/dawarich/place_drawer_test.exs:61,117,125,136,149,169` | B preserve projection, active/ties/zone | A1/B4 native detail test plus original projection cases. |
| `T/dawarich/places/web_write_test.exs:79,124,143,150` | B effects/phase/foreign/geometry | A2 keeps effects JSON and **partial save** at :140; new native adapter tests, legacy remains. No all-phase rollback claim. |
| `T/dawarich/places/web_delete_test.exs:22` | B graph/no-visit-loss/unsupported | A2 command deletion; original effects stay; O5 adds corrupt-owner characterization. |
| `T/dawarich/places/nearby_test.exs:42,88,106` | B provider/rate/name fallback; final component attrs M | A3 provider cases unchanged; native projection/select successor. Retain legacy component assertions for map; do not delete pacing case with markup. |
| `T/dawarich_web/places_live_test.exs:30,56,70,85,107` | Mixed B/M title/table/HEAD/empty/raw page/query/auth | B2 native list behavior; delete href/M becomes raw-page confirm event and cancel/no effects. HEAD/sign-in remain. |
| `places_live_test.exs:97` | C same-URL reload | B2 `native Places unavailable first read shows alert without redirect loop`. |
| `T/dawarich_web/places_parity_test.exs:26,38` | M normalized list HTML corpus, B seeded values | C2 splits effects/list cases → B2 named list dataset tests; retained map HTML remains deferred if present, no blind file deletion. |
| `T/dawarich_web/places_gate_endpoint_test.exs:56,63,71,80,88,96` | B native ownership + C list hand-backs | C1 native route/refusal/no-upstream matrix; missing zone/read unavailable does not loop; format matrix documented. |
| `places_gate_endpoint_test.exs:113,122,131,148,163,183,209,271` | Mixed B/C/R map frame/nearby/auth/id/headers | C1 retain Phoenix direct/frame/nearby status/ownership and pre-write no effects, remove Puma/replay promises; map frame M stays until 6. |
| `T/dawarich_web/place_navigation_test.exs:34,58,74,89,112` | B direct/nearby/no effects/radius + M exact frame HTML + C provider handback | C1 keeps direct URL/frame/nearby B in standalone; A3/B3 named native provider/default/radius cases; no coexistence owner assertion. |
| `T/dawarich_web/place_actions_test.exs:47`; `a8_request_test.exs`; `a8_routes_test.exs` | B/R HTTP method/CSRF/effects/response, M stream targets | Retain for map, expand C1 protection; B3/B4 typed event successor is additional, not replacing still-used HTTP contracts. |
| `T/dawarich_web/place_drawer_frame_test.exs:81,123,131,159,173,188` | B formatting/empty + M helper DOM/newline/whitespace | Deferred map M retains for M6, native B4 successors independently cover stats/plain note/value/escaping/empty. Native need not match helper markup newline. |
| `T/dawarich_web/standalone_place_browser_test.exs:36,186,218` | B modal/drawer/tags/precision/extra query plus M bridge | Retain map regressions; B3/B4 new event behavior covers same semantics outside map. :144 trip-note Turbo case belongs milestone 5/6, untouched. |
| `T/dawarich_web/endpoint_test.exs:1112,1208`; `a8_remaining_parity_test.exs`; `map_data_routes_test.exs`; `page_routes_test.exs` | C/R ownership and mixed adjacent features | C2 enumerate Place clauses; list native no handback, remaining map B preserved, unrelated trip/visit/video cases untouched. |
| `E/places/list.spec.js:7,15,28,42` | B list, page deletion; old browser alert/link M | C3 accessible native confirm/cancel successor, identical pagination/effects. |
| `E/places/direct-open.spec.js:13,61`; `helpers.js:35,44` | B direct map open/note and C owner branch; map JS helper M | C3 retain direct map behavior standalone, retire coexistence owner branches; native new helper never invokes map/Stimulus. |
| `E/places/drawer.spec.js:8`; `marker-edit.spec.js:27`; `drawer-delete.spec.js:11` | B map stats/edit/delete/marker | Run unchanged/standalone against retained adapters; native forms/detail specs added separately; complete native map rewrite deferred 6. |


## Source case ledger

### test/dawarich/place_list_test.exs

- `pages hold 20 places in id order, whatever order the rows were written in` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `page values follow Kaminari's to_i and clamp at 1` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `a legacy place without lonlat shows its decimal columns` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `coordinates are the stored doubles` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `created_at carries the zone offset; UTC users get Z` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `settings Rails rejects hand back` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `an empty page needs no zone` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `a page beyond 10^15 hands back` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `another user's places never appear` — retain domain/effect B and deferred map M; native list C/R retarget per table above.

### test/dawarich/place_drawer_test.exs

- `the drawer holds the place, active counts, tags and the five latest active visits` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `soft-deleted visits are excluded everywhere` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `ties order by id` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `a tie across the fifth visit keeps the higher id` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `visit times are local to the user's zone` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `a blank zone shows Rails' TIME_ZONE default, a missing one UTC` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `a missing or another user's place hands back` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `an unknown source hands back` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `settings Rails rejects hand back` — retain domain/effect B and deferred map M; native list C/R retarget per table above.

### test/dawarich/places/web_write_test.exs

- `web saves preserve name locks tags adoption and phases` — retain domain/effect B and deferred map M; native list C/R retarget per table above.

### test/dawarich/places/web_delete_test.exs

- `place deletion preserves visits and removes only its graph` — retain domain/effect B and deferred map M; native list C/R retarget per table above.

### test/dawarich/places/nearby_test.exs

- `Redis limiter errors pace nearby calls locally and retain the interactive wait bound` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `blank nearby provider names use exactly Rails address city and unknown fallbacks` — retain domain/effect B and deferred map M; native list C/R retarget per table above.

### test/dawarich_web/places_live_test.exs

- `Rails' title, tabs and table for page 1; HEAD without a body` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `the empty hero for no places and for an out-of-range page` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `the delete link carries the raw page value` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `the paginator patches and keeps other query keys` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `a state the gate would refuse redirects to the same URL` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `signed-out visitors get Rails' sign-in redirect` — retain domain/effect B and deferred map M; native list C/R retarget per table above.

### test/dawarich_web/places_parity_test.exs

- `the corpus is complete` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `#{@name} is answered as Rails answered it` — retain domain/effect B and deferred map M; native list C/R retarget per table above.

### test/dawarich_web/places_gate_endpoint_test.exs

- `Phoenix answers the list for a signed-in user` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `a non-string page goes to Puma with the Rails cookie` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `a query part without = goes to Puma, whose parser reads it as nil` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `an account whose zone PostgreSQL lacks goes to Puma` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `a gate that cannot read the database hands the request to Puma` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `the list's formats go to Puma` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `Phoenix answers the drawer frame` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `an unframed request goes to Puma` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `a second frame name or a repeated header goes to Puma` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `a query string or X-Dawarich-Client goes to Puma` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `a foreign or missing place goes to Puma before routing` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `a drawer that leaves after the gate is replayed under the places log tag` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `unsupported ids and writes go to Puma while nearby is native` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `a signed-out frame request is redirected by Phoenix` — retain domain/effect B and deferred map M; native list C/R retarget per table above.

### test/dawarich_web/place_navigation_test.exs

- `direct links redirect and nearby hands provider calls back` — retain domain/effect B and deferred map M; native list C/R retarget per table above.

### test/dawarich_web/place_actions_test.exs

- `place responses match drawer modal and list requests` — retain domain/effect B and deferred map M; native list C/R retarget per table above.

### test/dawarich_web/place_drawer_frame_test.exs

- `the full drawer` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `the note textarea keeps Rails' leading newline` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `Rails' form helpers, verbatim` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `rounding and averages follow Ruby` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `the empty drawer` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `inline siblings keep their whitespace` — retain domain/effect B and deferred map M; native list C/R retarget per table above.

### test/dawarich_web/standalone_place_browser_test.exs

- `standalone modal create and marker edit retain tags and notes through drawer saves` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `standalone trip note forms create update and delete their exact Turbo frame` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `standalone map modal preserves full browser coordinate input at Rails storage precision` — retain domain/effect B and deferred map M; native list C/R retarget per table above.
- `standalone place drawer and nearby ignore Rails-accepted extra query fields` — retain domain/effect B and deferred map M; native list C/R retarget per table above.

## Retained fixture places/remaining/effects.json

Source fixture remains unchanged. Top-level effect cases are retained by existing corpus consumers.

- `create_ordinary_html_false`
- `create_default_html_false`
- `create_unicode255_html_false`
- `create_unicode256_html_false`
- `create_blank_name_html_false`
- `create_missing_name_html_false`
- `create_blank_lat_html_false`
- `create_nil_lon_html_false`
- `create_missing_coords_html_false`
- `create_zero_html_false`
- `create_photon_html_false`
- `create_gpx_html_false`
- `create_blank_source_html_false`
- `create_invalid_source_html_false`
- `create_tags_html_false`
- `create_empty_tags_html_false`
- `update_name_html_false`
- `update_noop_html_false`
- `update_default_html_false`
- `update_unicode255_html_false`
- `update_unicode256_html_false`
- `update_blank_name_html_false`
- `update_blank_coords_html_false`
- `update_nil_coords_html_false`
- `update_coords_html_false`
- `update_zero_html_false`
- `update_source_html_false`
- `update_blank_source_html_false`
- `update_invalid_source_html_false`
- `update_note_html_false`
- `update_empty_note_html_false`
- `update_nil_note_html_false`
- `update_omitted_tags_html_false`
- `update_empty_tags_html_false`
- `update_mixed_tags_html_false`
- `update_foreign_tags_html_false`
- `update_demo_html_false`
- `delete_html_false`
- `foreign_show_html_false`
- `foreign_update_html_false`
- `foreign_destroy_html_false`
- `show_html_false`
- `create_ordinary_html_true`
- `create_default_html_true`
- `create_unicode255_html_true`
- `create_unicode256_html_true`
- `create_blank_name_html_true`
- `create_missing_name_html_true`
- `create_blank_lat_html_true`
- `create_nil_lon_html_true`
- `create_missing_coords_html_true`
- `create_zero_html_true`
- `create_photon_html_true`
- `create_gpx_html_true`
- `create_blank_source_html_true`
- `create_invalid_source_html_true`
- `create_tags_html_true`
- `create_empty_tags_html_true`
- `update_name_html_true`
- `update_noop_html_true`
- `update_default_html_true`
- `update_unicode255_html_true`
- `update_unicode256_html_true`
- `update_blank_name_html_true`
- `update_blank_coords_html_true`
- `update_nil_coords_html_true`
- `update_coords_html_true`
- `update_zero_html_true`
- `update_source_html_true`
- `update_blank_source_html_true`
- `update_invalid_source_html_true`
- `update_note_html_true`
- `update_empty_note_html_true`
- `update_nil_note_html_true`
- `update_omitted_tags_html_true`
- `update_empty_tags_html_true`
- `update_mixed_tags_html_true`
- `update_foreign_tags_html_true`
- `update_demo_html_true`
- `delete_html_true`
- `foreign_show_html_true`
- `foreign_update_html_true`
- `foreign_destroy_html_true`
- `show_html_true`
- `create_ordinary_turbo_false`
- `create_default_turbo_false`
- `create_unicode255_turbo_false`
- `create_unicode256_turbo_false`
- `create_blank_name_turbo_false`
- `create_missing_name_turbo_false`
- `create_blank_lat_turbo_false`
- `create_nil_lon_turbo_false`
- `create_missing_coords_turbo_false`
- `create_zero_turbo_false`
- `create_photon_turbo_false`
- `create_gpx_turbo_false`
- `create_blank_source_turbo_false`
- `create_invalid_source_turbo_false`
- `create_tags_turbo_false`
- `create_empty_tags_turbo_false`
- `update_name_turbo_false`
- `update_noop_turbo_false`
- `update_default_turbo_false`
- `update_unicode255_turbo_false`
- `update_unicode256_turbo_false`
- `update_blank_name_turbo_false`
- `update_blank_coords_turbo_false`
- `update_nil_coords_turbo_false`
- `update_coords_turbo_false`
- `update_zero_turbo_false`
- `update_source_turbo_false`
- `update_blank_source_turbo_false`
- `update_invalid_source_turbo_false`
- `update_note_turbo_false`
- `update_empty_note_turbo_false`
- `update_nil_note_turbo_false`
- `update_omitted_tags_turbo_false`
- `update_empty_tags_turbo_false`
- `update_mixed_tags_turbo_false`
- `update_foreign_tags_turbo_false`
- `update_demo_turbo_false`
- `delete_turbo_false`
- `foreign_show_turbo_false`
- `foreign_update_turbo_false`
- `foreign_destroy_turbo_false`
- `show_turbo_false`
- `create_ordinary_turbo_true`
- `create_default_turbo_true`
- `create_unicode255_turbo_true`
- `create_unicode256_turbo_true`
- `create_blank_name_turbo_true`
- `create_missing_name_turbo_true`
- `create_blank_lat_turbo_true`
- `create_nil_lon_turbo_true`
- `create_missing_coords_turbo_true`
- `create_zero_turbo_true`
- `create_photon_turbo_true`
- `create_gpx_turbo_true`
- `create_blank_source_turbo_true`
- `create_invalid_source_turbo_true`
- `create_tags_turbo_true`
- `create_empty_tags_turbo_true`
- `update_name_turbo_true`
- `update_noop_turbo_true`
- `update_default_turbo_true`
- `update_unicode255_turbo_true`
- `update_unicode256_turbo_true`
- `update_blank_name_turbo_true`
- `update_blank_coords_turbo_true`
- `update_nil_coords_turbo_true`
- `update_coords_turbo_true`
- `update_zero_turbo_true`
- `update_source_turbo_true`
- `update_blank_source_turbo_true`
- `update_invalid_source_turbo_true`
- `update_note_turbo_true`
- `update_empty_note_turbo_true`
- `update_nil_note_turbo_true`
- `update_omitted_tags_turbo_true`
- `update_empty_tags_turbo_true`
- `update_mixed_tags_turbo_true`
- `update_foreign_tags_turbo_true`
- `update_demo_turbo_true`
- `delete_turbo_true`
- `foreign_show_turbo_true`
- `foreign_update_turbo_true`
- `foreign_destroy_turbo_true`
- `show_turbo_true`
- `nearby_disabled`
- `nearby_zero`
- `nearby_missing`
- `nearby_blank_lat`
- `nearby_missing_lon`
- `nearby_radius`
- `nearby_enabled_zero`
- `create_de_blank_turbo_false`
- `update_de_blank_html_false`
- `update_de_long_turbo_false`
- `create_es_blank_turbo_false`
- `create_fr_blank_turbo_false`
- `create_pl_blank_turbo_false`
- `create_ca_blank_turbo_false`
- `create_zh_blank_turbo_false`
- `update_es_blank_html_false`
- `update_fr_blank_html_false`
- `update_pl_blank_html_false`
- `update_ca_blank_html_false`
- `update_zh_blank_html_false`
- `update_es_long_turbo_false`
- `update_fr_long_turbo_false`
- `update_pl_long_turbo_false`
- `update_ca_long_turbo_false`
- `update_zh_long_turbo_false`


## C2 corpus reconciliation

All 18 top-level JSON/HTML fixtures and the enumerated remaining-effect cases above remain unchanged. No fixtures were pruned through the E2E symlink. Each list case now checks the independent source fixture's name, local date and coordinate values and raw pagination links, rather than matching shell/control markup.

| Prior PlacesParity test | Named successor |
| --- | --- |
| `list_blank_zone is answered as Rails answered it` | `list_blank_zone preserves source values and retained transport` |
| `list_empty is answered as Rails answered it` | `list_empty preserves source values and retained transport` |
| `list_extra is answered as Rails answered it` | `list_extra preserves source values and retained transport` |
| `list_foreign is answered as Rails answered it` | `list_foreign preserves source values and retained transport` |
| `list_no_zone is answered as Rails answered it` | `list_no_zone preserves source values and retained transport` |
| `list_page0 is answered as Rails answered it` | `list_page0 preserves source values and retained transport` |
| `list_page1 is answered as Rails answered it` | `list_page1 preserves source values and retained transport` |
| `list_page2 is answered as Rails answered it` | `list_page2 preserves source values and retained transport` |
| `list_page_2abc is answered as Rails answered it` | `list_page_2abc preserves source values and retained transport` |
| `list_page_blank is answered as Rails answered it` | `list_page_blank preserves source values and retained transport` |
| `list_page_out is answered as Rails answered it` | `list_page_out preserves source values and retained transport` |
| `list_page_space is answered as Rails answered it` | `list_page_space preserves source values and retained transport` |
| `list_utc is answered as Rails answered it` | `list_utc preserves source values and retained transport` |

The five drawer cases retain their normalized source body/stream/control oracle, with the same named-successor suffix, until M6. PlaceActions keeps every response/effect/stream/flash corpus entry; its refused shape/HTML-create/error cases now assert local 422 and unchanged Place snapshots. A8Remaining retains every trip branch unchanged; only Place tag overflow and unsupported zone branches now assert local refusal and unchanged snapshots. Standalone navigation retains all 15 GET effect cases, default/radius progression and no job effects; the source missing-template case keeps the existing local native 406. All non-Places closure source-key tests remain unchanged; the native list source key now verifies local ownership and unchanged observations.

The old gate cases have these successors in PlacesGateEndpointTest: nested page → `native nested page is refused in place without upstream`; valueless queries → `native valueless scalar queries remain local`; unsupported timezone → `native unsupported timezone renders a local alert`; failed read → `unavailable original actor admission stays typed and local`; formats/XHR → `native list formats and XHR remain locally owned`; unframed/client → `retained member client header refusal stays local`; repeated/unknown frame → `unknown or repeated member frame headers never open a native dialog`; extra query → `member extra scalar query remains standalone map-compatible`; foreign/missing → `foreign and missing member frames are locally unavailable`; post-admission disappearance → `drawer disappearance after admission is local and is never replayed`; unsupported ids/writes/nearby → `retained ids writes and nearby are refused or answered locally`. Signed-out session-return and owned frame cases remain. Real read failure is additionally covered by initial PlacesLiveAuth safe-admission refusal; unsupported persisted containers have a connected zero-effect successor and FRB-088.

## Targeted implementation measurements

Fresh main-Repo telemetry measurement, synthetic sparse and 21+ Place datasets, seed 404, static request then real connected join. Includes authentication/admission; excludes seeding, Redis, assets, provider work and other repos. The temporary counter probe detected a zero-counter mutation, restored identical values, and was removed. These are measurements, not newly approved query caps.

| State | Query count |
| --- | ---: |
| Sparse static / connected | 9 / 8 |
| Populated static / connected | 8 / 8 |
| Page 2 static / connected | 8 / 8 |
| Out-of-range empty static / connected | 8 / 8 |
| Create open / validate / save | 5 / 3 / 9 |
| Edit open / save | 7 / 15 |
| Detail open / note save | 9 / 22 |
| Delete confirmation open / accept | 5 / 17 |

The increased connected count versus the historical 3b observation includes immutable-origin hook admission before params plus independent facade admission. Note/save counts include effect fencing, authoritative detail/form reload and list reload. Nearby does no provider work on mount; deterministic barrier tests prove one current request, cancellation and ignored stale timeout/delivery.

Esbuild metafile: PlaceDraft contributes **745 eager bytes**, within the approved 2 KB incremental cap; two eager native JS outputs. Native graph tests reject Hotwire, map and legacy imports; the valid static MapLibre mutation fails the eager graph assertion. Runtime request/decoded/wire bytes and German/English 390px Range/focus evidence remain C3/C4 measurements. Browser acceptance and controller FULL GATE are not implied by these local checks.

## Rails fixes and remaining map handoff

FRB-086 filters foreign dependent reads; FRB-087 fences foreign dependent effects; FRB-088 renders malformed settings refusal without the Rails navbar crash. Each has an appended ED row and draft changelog entry. Source confirmation copy, phased persistence, lack of a durable cross-socket receipt and retained map projections/transports remain explicit limitations. M6 must retire drawer/nearby frame routes, PlaceActions/PlaceRequest/streams, map modal/controllers and their deferred markup corpus together; direct member URL compatibility must be decided before retirement.

C2 restored strict batch: 124 passed, seed 404, exit 0. The malformed-settings case first failed decoding, then exposed a forged native write; operation/effect shape fences now refuse it. Decoder, object-only cast and write-fence mutations failed the named case; restored GREEN. Identity admission still does not eagerly reject a zone needed only by a later read.


## C3 targeted browser results

All assigned native Places and retained map/direct-caller specs pass on standalone: **33 passed, 1 skipped, 0 failed, 0 flaky, exit 0**, repeated after the mutation probe was restored. The existing emoji-label fixme is unchanged; no migration-side skips were added. This is targeted implementation evidence, not controller FULL GATE or stage acceptance. The task brief explicitly requested these C3 lane runs; the current plan moves full browser/stand acceptance to the integrated stage.

Seven new named cases first fail on the pre-milestone baseline. The mutation probe fails eight intended assertions: six-decimal persistence, reconnect draft retention, five latest visits, nearby default radius, canceled task liveness, server-bound delete target, original password identity, and visits surviving deletion. Three unchanged cases pass the probe. After restore, every assigned spec passes again. Native effects are checked through owner data/API; provider tasks use deterministic loading/delivery/cancellation, not a live service. Native clients send no HTTP Place form writes and do not use the map/Stimulus helper.

Browser proof covers invalid name/coordinates and retained fields, one accepted duplicate submit, tag clear/replacement, source/note/name locks, persisted partial create plus scoped edit recovery, two explicit note saves, foreign ids and forged targets, two-tab deletion, password revocation, real LiveSocket disconnect/reconnect without automatic submit, patch/back-forward/raw query, cancel/Escape/backdrop/focus return and keyboard wrap. Map direct link, drawer notes/stats, marker edit/tag change, drawer delete/marker removal, visit search and map creation remain retained transports.

OrdinaryDialog was added after a real Shift+Tab failure: it wraps only the owned dialog controls and removes its listener on destruction. Client RED/GREEN/wrap mutation/restored GREEN; affected native server/asset batch 22 passed. The complete restored Places/locale/primitive/asset batch is 40 passed. Five isolated scoped context modules are async; LiveView/global environment/shared-sandbox modules remain serialized. Restored context/direct-caller batch: 57 passed.

The malformed-settings successor also tests an explicit locale query. Locale selection on native Places no longer replaces a non-object container before refusal; this leaves the existing preference behavior elsewhere intact. Named RED, disabled-guard mutation and restored GREEN are recorded with FRB-088 evidence. This is a Phoenix-only widening prevented by the opaque decoder change, not an additional Rails fix.

## Final native asset and mobile measurements

Esbuild eager graph remains two outputs. Incremental hooks: **PlaceDraft 745 bytes + OrdinaryDialog 854 bytes = 1599 bytes**, within the approved 2 KB cap. Graph tests reject eager map/Hotwire/legacy imports; a valid static MapLibre mutation fails. Changed Elixir/HEEx files are formatted; Biome checks 16 asset files; three affected native client tests pass. Controller full compile/suites remain deferred.

Measured **23 English/German states at 390 px**: empty, create, validation error, edit, detail/note with long data, delete/raw-page delete, partial saved state, nearby loading/empty/failure/timeout/results. Every page has `scrollWidth == clientWidth == 390`; text Range boxes do not escape the dialog/control bounds horizontally. The table may scroll in its designated container. Popup measurements wait for a mounted open dialog; fields and accessible action labels are used in the browser assertions.

Each native measurement records two JS resources and no Turbo/Stimulus/map script. Fresh decoded total is **168279 bytes** (167735 entry + 544 chunk); fresh browser transfer total is **52511 bytes** (51874 + 637, including transfer overhead). Cached navigations report zero transfer for the entry and sometimes zero decoded size for the shared chunk; these are cache observations, not smaller bundles. Opening dialogs and nearby state changes add no JS request. Exact resource fingerprints, state measurements and runtime identities are in the external implementation report.

## Completion boundary

All eleven implementation tasks are complete. Query budgets still require controller acceptance; no new caps were invented. C4 full ExUnit seeds and integrated acceptance were not run. The current controller note schedules full G44/mobile/stand acceptance at the stage boundary. AFFiNE mirrors this implementation summary and the approved decisions; code-coupled registers stay canonical here. No retained map dependency was retired; the M6 checklist above remains binding.

## Review round 1 (2026-10-10)

Fresh Places layout actors use an explicit projection without API or integration credentials; the immutable identity and independent facade re-admission remain. The complete-assigns credential regression covers mount, event, info and async delivery. Coordinate validation bounds decimal input at 128 bytes and handles failed conversion as unsupported while preserving submitted field values and six-decimal writes.

Native transaction exceptions now return uncertain_persistence. OrdinaryForm consumes uncertain generations, permits only classified no-effect retries, and renders localized guidance to check the authoritative Places list. Known saved-id partial recovery remains unchanged; no cross-socket receipt is claimed. check_places clears dialogs and reloads the list without replaying a submit.

URL patches clear detail/note state as well as full forms and confirmation. select_nearby now requires generation, run and index; each rendered suggestion set carries a client-safe run identifier. A stale selection from a previous completed run cannot select the replacement run’s index-zero result. Future map hosts must send the rendered run identifier too.

Named successors: Places assigns exclude account credentials across mount event info and async; overflowing coordinate validation retains dialog errors and values without effects; uncertain create acknowledgement consumes generation and recovers through the list; ordinary form consumes uncertain outcomes and only releases proven zero effects; URL patches close detail and refuse its queued note generation; nearby selection refuses a previous completed provider run. RED/GREEN/mutation/restoration evidence is in the controller’s external fix report. C4 and stage browser/mobile acceptance remain controller-owned.

Foreign suggestion, tagging and note command safety now has three independent database-valid graph cases, each refusing both update and delete and checking all relevant graphs remain unchanged. Removing any one corresponding SQL branch fails its own successor. This expands evidence for existing FRB-087/ED-NATIVE-M3D-DEPENDENT-WRITES; it adds no Rails defect fix.

The credential projection retains the explicit onboarding QR feature through a fresh admitted lookup at render time. Neither the raw key nor rendered QR is assigned to Places state. Initial refused admission also clears raw previous actor/scope values from LiveView change tracking. Earlier query counts above predate this added render-time admission read; C4 must remeasure them. The A9 route metadata caller now checks the existing native Places gate/session/root/hook instead of the retired Rails list gate; adjacent routes retain their original contracts.

Final review-round gate: 47 targeted files, seed 404, warnings-as-errors; 356 caller tests plus 14 command/form tests pass, both exit 0. Separate batches isolate corpus-driven nontransactional Place sequence growth beyond the approved member-id input bound. Whole-project formatting and forced strict test-env compilation pass. Existing browser/mobile/query measurements predate these corrections; C4 and stage acceptance must revalidate them.

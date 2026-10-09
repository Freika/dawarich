# Milestone 3a inventory and baseline

Milestone 3a of the native frontend (`superpowers/plans/2026-10-09-phoenix-native-milestone-3-plan.md`, ADR-0017): `/settings/general`, `/settings/visits`, `/settings/integrations` (incl. TREK, AirTrail/TeslaMate sync) and `/users/edit` (API key, export, ZIP import). Written before any change, on the 3a base (pilot head `a3c4c56ba`).

## Baseline (3a base `a3c4c56ba`, standalone)

Ecto queries per mount (`get` = static render, `live` = connected mount; seeded user without extra data):

| Route | Static | Connected |
| --- | ---: | ---: |
| `/settings/general` | 4 | 4 |
| `/settings/visits` | 9 | 6 |
| `/settings/integrations` | 6 | 5 |
| `/users/edit` | 4 | 4 |

JavaScript loaded after `networkidle` (`settings/assets-budget.spec.js`, E2E `ea3b741`, decoded bytes):

| Route | Script requests | Bytes | Hotwire modules among them |
| --- | ---: | ---: | ---: |
| `/settings/general` | 54 | 2,795,652 | 10 |
| `/settings/visits` | 54 | 2,767,058 | 10 |
| `/settings/integrations` | 54 | 2,767,058 | 10 |
| `/users/edit` | 53 | 2,766,092 | 9 |

Standalone G44 reference: the pilot's final run on app `1bc05f892` / E2E `e6161a4` — every lane 524 passed, 0 failed, 51 skipped (`docs/phoenix/native-frontend-inventory.md`). The 3a base `a3c4c56ba` differs from `1bc05f892` only in documentation, so that run is the reference.

Pre-existing defect found while measuring: `/users/edit` renders two elements with the HTML id `Flower` (an inline SVG asset), which LiveViewTest rejects unless `on_error: :warn` is passed. The native page must not carry duplicate ids (Task 9a).

## Results (Task 12, app `8a5a2555d`, E2E `bc2fcea`)

- Full ExUnit, seeds 404 and 202: 7147 tests; the only failures were the two pinned Tailwind output hashes, which moved with the new page classes and were re-pinned (`aadedd502`); both build tests green afterwards.
- Standalone G44, three full lanes run one after another: 525 passed / 0 failed / 51 skipped each (reference 524/0/51; skip set unchanged). Two earlier attempts with the three lanes in parallel on a heavily loaded machine (load average ~34) timed out in different specs each time, all outside the 3a pages except `imports-exports/user-data.spec.js`, whose import job was cancelled after a 15 s DB connection wait; every one of them passed on a single lane. Root-cause analysis: `.scratch/orch/out/g44-flakes.report.md` (follow-up, not 3a). The app-owned `e2e/native-imports` helper still posted the old Rails general-settings form and was fixed (`8a5a2555d`).
- Queries per mount stay within the baseline (asserted by each page's budget test; visits measured 7 static / 6 connected).
- JavaScript on the four routes: 2 script requests, 164,080–164,624 decoded bytes, 0 Hotwire modules (was 53–54 requests, ~2.77–2.80 MB, 9–10 Hotwire modules).
- `mix compile --warnings-as-errors`, `biome ci app-phoenix/assets`, `node --test spec/javascript/*_test.mjs` (598 passed): clean. `mix format --check-formatted` was not clean here (two files); fixed in spec-verify round 1 (`ea7e55ac4`).
- German and English at 390 px: no horizontal page scroll and no label overflowing its control on `/settings/general`, `/settings/visits`, `/settings/integrations`, `/users/edit` (measured on the stand).

## Behaviour map

Kinds: **B** behaviour (must keep passing, ported into the new context/LiveView tests), **M** markup only (replaced or dropped), **C** coexistence/Rails hand-back only (dropped, ADR-0017), **R** route/ownership table (updated when routes move or disappear).

### `/settings/general` — `SettingsActions :update`, `SettingsSupporterActions`, `TestEmail`/`TestEmailGate`

| Behaviour | Kind | Current coverage | Task |
| --- | --- | --- | --- |
| Save digest toggles (monthly/yearly; legacy `digest_emails_enabled` sets both), `news_emails_enabled` (on unless off), `locale`, `timezone`, `show_supporter_badge` | B | `standalone_settings_test.exs` "standalone general settings persist preferences…", `settings_live_test.exs` "the legacy digest key sets both toggles…" | 3, 4 |
| Unknown locale/timezone silently ignored, still "settings updated" | B | `dawarich/` General tests (via `General.save`) | 3 |
| Timezone change resets stats calculation and schedules existing stats atomically | B | `standalone_settings_flow_test.exs` | 3 |
| Save failure → `failed_to_update_settings` alert; `:save_failed` → 500 | B | `standalone_settings_test.exs` | 3, 4 |
| Session locale staged after save | C (replaced by user-setting precedence, ED row) | `standalone_settings_test.exs` | 4 |
| Language list in `I18n.available_locales` order, current checked; zone selected | B (rendered state) | `settings_live_test.exs` "the language order…", "languages in Rails' order…" | 4 |
| Without SMTP the notice replaces digest toggles and test email | B | `settings_live_test.exs` | 4 |
| What's New (changelog consent) card toggles through the shell handler | B | `settings_live_test.exs` | 4 (shell, kept) |
| Verified supporter: thanks + badge toggle; email kept out of LiveView state | B | `settings_live_test.exs` | 4 |
| Supporter verify: success notice with platform name, not found alert, empty input alert, error → 500 | B | none at the handler level (only page state) → new tests | 3, 4 |
| Cloud hides test email, supporter, What's New and Background Jobs tab; supporter lookup never runs on Cloud | B | `settings_live_test.exs` | 4 |
| Test email: admin only (403 for non-admin, no enqueue), cloud refusal flash, CSRF, Turbo/HTML responses | B (+M for Turbo response) | `test_email_test.exs`, `residual_mail_ownership_test.exs`, `dawarich/mail/test_email_test.exs` | 3, 4, 11 |
| Rails morph metas only on this page | M | `settings_live_test.exs` "Rails' morph metas…" | 4 (dropped) |

### `/settings/visits` — `VisitSettingsActions`

| Behaviour | Kind | Current coverage | Task |
| --- | --- | --- | --- |
| Save three detection settings (`to_i`), Rails notice; PATCH/PUT and POST override | B (+R for verbs) | `visit_settings_actions_test.exs` "settings native verbs…", `dawarich/visits/web_settings_test.exs` | 3, 5 |
| `{:replay, _}` from `WebSettings` hands back | C | `visit_settings_actions_test.exs` | 3 (becomes an error) |
| Redetect enqueues and notifies; cooldown `{:cooldown, 429}` hands back, `{:cooldown, 429, :native}` alert | B (+C for hand-back) | `visit_settings_actions_test.exs` "redetection redirects after queue…" | 3, 5 |
| Edited fields stay in a stable island across join | M (hybrid mechanism) | `visit_settings_live_test.exs` | 5 (dropped) |
| Signed-out user gets the Devise redirect | B | `visit_settings_live_test.exs` | 5 (NativeAuth) |
| Route `rails_gate` `A8Gate.settings?` | C/R | `a8_gate_endpoint_test.exs`, `a8_routes_test.exs`, `a8_videos_visits_parity_test.exs` | 5, 11 |

### `/settings/integrations` — `IntegrationActions :update`, `IntegrationJobActions` (kept), `TrekSourceActions`

| Behaviour | Kind | Current coverage | Task |
| --- | --- | --- | --- |
| Inactive account → `/` with "account not active" (303); no full access → refusal | B | `standalone_integrations_flow_test.exs`, `small_parity_integrations_test.exs` | 6, 7 |
| Save credentials per service, connection test (normalized trailing-slash URLs), provider notices in Rails order, photo cache refresh notice first | B | `small_parity_integrations_test.exs` | 6, 7 |
| Blank Immich form commits without an outer transaction; SQL failure rolls back; refused nested triggers keep the outer transaction | B | `standalone_integrations_flow_test.exs`, `small_parity_integrations_test.exs` | 6 |
| Secret sentinel `"********"` keeps the stored secret | B | `dawarich/integrations_test.exs` / `Settings.Integrations` tests | 6, 7 |
| Secrets reach the page but not the LiveView state | M→changed (sentinel, ED row) | `settings_live_test.exs` | 7 |
| Immich opens by default; statuses and current service on nav links; unknown service → Immich; admin's old geocoding link → Instance settings | B | `settings_live_test.exs` | 7 |
| Cloud Lite user: Pro card with upgrade link, no panes | B | `settings_live_test.exs` | 7 |
| AirTrail/TeslaMate sync from the page via `POST /settings/background_jobs` | B | `admin_writes_request_test.exs` (job actions) | 6, 7 (route kept) |
| TREK add (verify, encrypt, reconnect without replacing an import claim) | B | `standalone_trek_sources_test.exs` | 6, 8 |
| TREK selection (dated active choices, provider failures recorded) | B | same | 6, 8 |
| TREK import (filters identifiers, claims once, publishes the native job atomically); empty selection rotates token | B | same | 6, 8 |
| TREK manual sync (refuses disabled/importing); disconnect (removes importing sources, keeps managed trip data) | B | same | 6, 8 |
| TREK owner/active/CSRF checks; Pro refusal with same-host Referer policy; per-form CSRF and effective DELETE only | B (CSRF/verb parts become LiveView events) | same | 8, 11 |
| TREK lists sources in creation order with actions | B | `settings_live_test.exs` | 8 |
| TREK coexistence forwarding | C | `standalone_trek_sources_test.exs` | 11 |

### `/users/edit` — `SettingsMiscActions :generate_api_key`, `AuthApiKeys.Http`, `UserDataController`/`UserDataGate`, `AuthAccount.Response`

| Behaviour | Kind | Current coverage | Task |
| --- | --- | --- | --- |
| API card: bare key, app QR code, key-bearing URLs | B | `settings_live_test.exs` | 9a |
| Rotation commits, revokes old credentials, preserves the session; invalidation wins over an in-flight retired-key lookup | B | `standalone_api_key_flow_test.exs`, `auth_api_keys/http_test.exs` | 3, 9a |
| Password user confirms with current password; OAuth user with email | B | `settings_live_test.exs` | 9a |
| Local account failures match source forms and clear password values | B (+M) | `settings_parity_test.exs` | 9a (redirect-with-errors, ED row) |
| Cloud cards: plan usage, subscription text by status, trial card | B | `settings_live_test.exs` | 9a |
| Export (session GET) enqueues and redirects to `/exports` with notice | B | `user_data_test.exs` | 9a |
| Import: blank archive alert, MIME/extension check, legacy-trial size/count boundaries, CSRF, hand-back keys | B (+C for hand-back) | `user_data_test.exs` | 9a, 9b |
| Import dialog is a Stimulus island with Rails' absolute direct-upload URL | M | `settings_live_test.exs` | 9b (replaced) |
| Account deletion (browser CSRF, family-owner refusal, cloud mail, enqueue rollback/retry) | B | `standalone_account_deletion_test.exs` | 9a (form only) |
| Controls stay out of LiveView patches before join | M (hybrid) | `settings_live_test.exs` | 9a (dropped) |
| Duplicate HTML id `Flower` | defect | — | 9a |

### Shell and navigation

| Behaviour | Kind | Current coverage | Task |
| --- | --- | --- | --- |
| Tabs in Rails order, active tab, 2FA only when configured, admin and self-hosted tabs | B | `settings_shared_test.exs` | 2 |
| Users/instance/background tabs active only on their pages | B | `settings_shared_test.exs` | 2 |
| Stimulus `scroll-into-view` comparator takes the caller's selector | M (becomes hook node test) | `settings_shared_test.exs` | 2 |
| Flags: locale flag without title, country flag with title; SVG read once and cached | B | `settings_shared_test.exs` | 2 (unchanged) |

## Affected test files (from `rg`, 57)

| Group | Files | Expected change |
| --- | --- | --- |
| Page behaviour + markup | `settings_live_test.exs`, `settings_parity_test.exs`, `settings_shared_test.exs`, `visit_settings_live_test.exs` | behaviour cases move to the new page tests; markup cases dropped (mapped here when removed) |
| Handler behaviour | `standalone_settings_test.exs`, `standalone_settings_flow_test.exs`, `standalone_api_key_flow_test.exs`, `standalone_integrations_flow_test.exs`, `small_parity_integrations_test.exs`, `standalone_trek_sources_test.exs`, `visit_settings_actions_test.exs`, `user_data_test.exs`, `test_email_test.exs`, `auth_api_keys/http_test.exs`, `standalone_account_deletion_test.exs`, `standalone_transaction_flow_test.exs`, `residual_mail_ownership_test.exs`, `referer_consumers_test.exs` | ported to context/LiveView tests before the handlers go (Task 11) |
| Routes, gates, ownership tables | `a8_gate_endpoint_test.exs`, `a8_request_test.exs`, `a8_routes_test.exs`, `a8_videos_visits_parity_test.exs`, `a9_routes_test.exs`, `a10b_ownership_test.exs`, `a10c_ownership_test.exs`, `a10c_routes_test.exs`, `a12f3a_{e,o,v}_closure_test.exs`, `a12f3b_{d02,i01,i04,n03,n04,n05}_test.exs`, `auth_gate_test.exs`, `auth_common_pipeline_test.exs`, `auth_two_factor/http_test.exs`, `endpoint_test.exs`, `page_envelopes_test.exs`, `page_routes_test.exs`, `strangler_test.exs`, `storage_routes_test.exs`, `standalone_auth_pages_test.exs`, `achievement_auth_refusal_test.exs`, `admin_writes_request_test.exs`, `operator_connection_security_test.exs`, `g44_admin_browser_test.exs` | rows for moved/removed routes updated (Tasks 4–11) |
| Domain (signatures kept) | `dawarich/integrations_test.exs`, `dawarich/visits/web_settings_test.exs`, `dawarich/mail/{test_email,residual,review_findings}_test.exs`, `dawarich/admin/user_security_test.exs`, `dawarich/a12f3b_{h01,m08}_test.exs`, `dawarich/build/css_parity_test.exs` | pass unchanged; extended where the plan says |
| Notes | `ASYNC_AUDIT.md` | mention only |

Recorded fixtures in the e2e repo touched by these pages: `phoenix-fixtures/settings/*.json` (account and integrations page recordings), `phoenix-fixtures/standalone/html_pages.json`, `phoenix-fixtures/page_envelopes/{rails,routes}.json`, `phoenix-fixtures/null_settings.json`, `phoenix-fixtures/admin_mutations/import_missing.json` — each is either kept (behaviour data) or deleted with the markup test that reads it (Task 11).

## Removed tests and their behaviour replacements

Filled in by Tasks 4–11 as tests are removed.

| Removed test (file: case) | Kind | Covered by |
| --- | --- | --- |
| `standalone_settings_flow_test.exs`: "standalone general form saves timezone and schedules existing stats atomically" | B (Rails form handler) | `test/dawarich/settings_test.exs` "a time zone change schedules each existing month once and a failed enqueue changes nothing"; `settings_general_live_test.exs` "saving the toggles and the time zone…" (notice, stored zone, re-rendered selection). The 302/session-flash/warden assertions are C (handler-only) |
| `settings_live_test.exs`: "Rails' morph metas are on here and nowhere else in this slice" | M | none needed: the native page has no Turbo (`native_pages_hotwire_free_test.exs`) |
| `settings_live_test.exs`: "Cloud hides the test email, the supporter and What's New cards and the Background Jobs tab" (direct `render/1`) | B via markup | `settings_general_live_test.exs` "on Cloud even an admin gets no test email, supporter, What's New or Background Jobs" (mounted page, plus the refused event) |
| `settings_live_test.exs`: "Rails form controls …" — `/settings/general` entry | C | the native form owns its state (`@form`); "picking a language without saving keeps the choice on the page" |
| `settings_parity_test.exs`: `general_*_en` (6 Rails HTML parity cases) | M | `settings_general_live_test.exs` (behaviour) and `settings_live_test.exs` rendered-state cases (language order, checked locale, selected zone, SMTP notice, legacy digest key, supporter thanks) |
| `visit_settings_live_test.exs`: "visit settings keep every edited field in a stable island before and after join" | M | `visit_settings_live_test.exs` "a typed value stays in the field while the page re-renders" |
| `dawarich/visits/web_settings_test.exs`: "connected rendering preserves edits inside the visit settings HTTP form" | M/C | same as above |
| `dawarich/visits/web_settings_test.exs`: rendered-HTML checks in "settings defaults and clamped display values…", "cooldown…", "Lite hint…"; `:rails` hand-back for invalid zones | M/C | the same cases now assert the mounted page's input values and disabled button, and `page/4` data; unknown zones: `visit_settings_live_test.exs` "a time zone the database does not know falls back to the default zone" |
| `a8_videos_visits_parity_test.exs`: `settings/*` HTML/Stimulus parity against Rails recordings | M | same cases compare the recorded Rails inputs, disabled redetect button and Lite hint with `WebSettings.page/4` |
| `a8_routes_test.exs`: "visits settings uses the existing rails_pages live session" (`A8Gate.settings?`) | R/C | `storage_routes_test.exs` "tag pages and native settings pages live in the native live_session" |
| `settings_parity_test.exs`: "local account failures match source forms and clear password values" (direct 422 render) | B (+M) | `account_live_test.exs` "a failed change returns to the page once with the errors and no password values" (request through the endpoint, redirect, one-time display) |
| `settings_parity_test.exs`: `account_*_en` (8 Rails HTML parity cases) | M | `settings_live_test.exs` `/users/edit` cases (API card, password vs OAuth confirmation, Cloud cards) and `account_live_test.exs` |
| `auth_account/response_test.exs`, `auth_account/http_test.exs`: 422 body assertions | B | same tests now assert the 303 to `/users/edit` and the stored errors |
| `settings_live_test.exs`: "the API card shows …" — `generate_api_key` link assertion; "Rails form controls …" — `/users/edit` entry; delete-dialog `phx-update` assertion | M/C | `account_live_test.exs` "a new API key replaces the old one on the page after a confirmation"; profile/delete forms are plain posts ("the profile form posts…", "the delete form posts…") |
| `settings_live_test.exs`: raw-secret HTML assertions in "integration secrets reach the page but not the LiveView state" | M→changed | Renamed to "integration secrets are masked on the page and in inspected LiveView state"; `settings_integrations_live_test.exs` "each credential pane hides stored secrets in static and connected HTML and preserves the sentinel"; ED-NATIVE-INTEGRATION-SECRETS |
| `settings_live_test.exs`: hidden `service` field and Turbo disconnect confirmation selectors | M | Existing default/status and source-order behaviours kept; native form and `data-confirm` selectors replace Rails markers. `trek_sources_live_test.exs` "native sync queues once and confirmed disconnect retains managed trip data" |
| `settings_live_test.exs`: "Rails form controls …" — five integration pane entries | C | `settings_integrations_live_test.exs` "pane patches survive reload and SSL changes are local until save without photo import buttons"; LiveView form state owns edits |
| `settings_parity_test.exs`: `integrations_*` Rails HTML/Stimulus parity cases | M | `settings_integrations_live_test.exs`, `trek_sources_live_test.exs`, retained `settings_live_test.exs` status/default/upgrade/source-order behaviours; fixtures retained for Task 11 |
| `standalone_trek_sources_test.exs`: selection-form CSRF/HTTP-action selector, `.html` locale navigation and blank redirect-body assertions | M/R | Native selection form selector; locale tested on canonical `?locale=de` URL; provider failure/disabled state and redirect destinations retained. `.html` refusal: `trek_sources_live_test.exs`; ED-NATIVE-TREK-HTML-VARIANTS |
| `standalone_integrations_flow_test.exs`: Rails form-action/CSRF-token selector | M | Handler transaction and rollback assertions retained with the established `RailsCsrf.masked_token` helper; native form save covered by `settings_integrations_live_test.exs` |
| `a12f3b_i01_test.exs`: direct legacy pane rendering for masked-secret HTML | M | Existing credential/validation/checkpoint/sentinel behaviours retained; all providers' mounted secret masking covered by `settings_integrations_live_test.exs` |
| `endpoint_test.exs`: TREK selection in the Puma-owned URL list | R/C | Canonical selection moved to the Phoenix-owned list; `storage_routes_test.exs` asserts `:native_pages` ownership and `trek_sources_live_test.exs` asserts 404 variants |
| `settings_live_test.exs`: "Rails form controls — every control a user edits in a Rails form stays out of LiveView's patches…" (whole case, after the integrations and account entries were removed) | C (hybrid mechanism) | native forms own their state (`@form`/`phx-change`, or plain posts with no server-rendered values); covered per page by the "typed value stays" / "picking a language" cases |
| `settings_live_test.exs`: "the import dialog is a Stimulus island with Rails' absolute direct-upload URL" | M | `account_import_upload_test.exs` (presigner, completed upload starts one import, nothing without an upload, cancel) and the node tests for the checksum hook and the direct uploader |
| `user_data_test.exs`: import-form markup half of "backup form and endpoint result equal Rails markup…" | M | same as above; the endpoint half stays ("backup endpoint results equal Rails in all shipped locales") |
| `settings_live_test.exs`: "Cloud cards…" (direct `render/1`) | B | same case now mounts the page on Cloud with dates relative to today |
| Task 11 — `standalone_settings_test.exs` (whole file: `PATCH /settings/general` with session and CSRF admission) | B + C | stored preferences: `test/dawarich/settings_test.exs` and `settings_general_live_test.exs`; session/CSRF admission of the removed form endpoint: C |
| Task 11 — `test_email_test.exs` (whole file: HTML/Turbo responses, action CSRF, non-admin 403 via `TestEmailGate`) | B + C | admin-only queueing, Cloud refusal, missing SMTP: `settings_test.exs` "test email" describe and `settings_general_live_test.exs` "only a self-hosted admin with SMTP can send a test email…"; responses/CSRF/gate: C |
| Task 11 — `residual_mail_ownership_test.exs` (whole file: test-email route ownership and Rails hand-back) | C/R | the route no longer exists; standalone 404: `removed_page_writes_test.exs` |
| Task 11 — `g44_admin_browser_test.exs`: "real test email link POST override queues native mail with browser Accept" | B + C | `settings_general_live_test.exs` test-email case |
| Task 11 — `mail/test_email_test.exs`: HTTP half of "mail success and render enqueue transport failures never log body or token markers" | B | same case now calls `Dawarich.Mail.TestEmail.run/4` directly (queues, never logs markers) |
| Task 11 — `a12f3b_n04_test.exs` (supporter and test-email handlers) | B | retargeted onto `Dawarich.Settings.verify_supporter/2` and `send_test_email/2`, same provider outcomes, flags and Cloud/queue-failure alerts |
| Task 11 — `a12f3b_n03_test.exs` (`SettingsActions :update`) | B | retargeted onto `Dawarich.Settings.update_general/2`: coercion, locale, zone, flags, recalculation once, failed save leaves everything unchanged |
| Task 11 — `standalone_transaction_flow_test.exs`: "uppercase general locale persists and stages the normalized Rails locale" | B + C | normalization: `settings_test.exs` "an uppercase locale is stored normalized"; session locale staging: C (ED-NATIVE-SETTINGS-LOCALE) |
| Task 11 — `a12f3b_h01_test.exs`: `/settings/general` update, `verify_supporter`, `test_email` rows in the declarations, CSRF and settings tables | R | the routes are gone; 404 in standalone: `removed_page_writes_test.exs` |
| Task 11 — `visit_settings_actions_test.exs` (whole file: verbs, `_method` override, Rails notice, cooldown hand-back) | B + C | stored `to_i` values, merge with other settings, one queued redetection, cooldown: `settings_test.exs` "visits" describe, `visit_settings_live_test.exs`, and the retargeted A8 parity cases; verbs/override/flash/hand-back: C |
| Task 11 — `a8_videos_visits_parity_test.exs`: `settings/*` write and redetect cases through `VisitSettingsActions` | B | same recorded cases now call `Dawarich.Settings.update_visits/3` and `request_visit_redetection/2` and still assert the recorded rows and Rails commands |
| Task 11 — `a12f3a_v_closure_test.exs`: V07 writes and V08 producer/blocked request through the endpoint | B | same cases now call the `Dawarich.Settings` functions (stored settings, outbox command, worker run, cooldown) |
| Task 11 — `a8_gate_endpoint_test.exs`: "A8 action pipeline runs the limiter before parsing" (used `PATCH /settings/visits`), visits settings rows in the route table and hand-back list | R | every remaining A8 action hands back in this harness; the limiter stays covered by "A8 public pipeline runs the limiter" and the RateLimit tests |
| Task 11 — `achievement_auth_refusal_test.exs`, `a12f3a_o_closure_test.exs`: `/visits/redetections` and `/settings/visits` write rows | R | routes removed; 404: `removed_page_writes_test.exs` |
| Task 11 — `standalone_trek_sources_test.exs`: add/reconnect, import filter and claim, empty selection, manual sync, disconnect, owner/active/CSRF, Pro refusal Referer, per-form CSRF and DELETE (8 cases) | B + C | `test/dawarich/integrations/trek_test.exs` (create verifies, encrypts, reconnects, keeps an import claim; sync refusals; clear rotates token; delete keeps trip data; foreign/malformed ids and inactive/Lite scopes refused; import filters and claims once) and `trek_sources_live_test.exs`; CSRF/verbs/Referer: C. The selection-page case stays |
| Task 11 — `standalone_integrations_flow_test.exs` (whole file: blank Immich form through the endpoint, non-sandbox transaction) | B + C | transaction semantics: `small_parity_integrations_test.exs` nested save/trigger cases on `Settings.Integrations.save/4`; form post: C |
| Task 11 — `small_parity_integrations_test.exs`: "photo cache refresh notices precede successful provider notices in Rails order" via `IntegrationActions` | B | same case now submits the native form and asserts "Settings updated. Photo cache refreshed. Immich connection verified" (the native form saves one provider pane at a time) |
| Task 11 — `a12f3b_i01_test.exs`: I01a/I01b through `IntegrationActions` (incl. router-level sentinel post, signed-out/CSRF/Lite/inactive statuses) | B + C | same cases call `Settings.Integrations.save/4` (validation, masks, checkpoints, sentinel, notice and alert order); refusals for expired/Lite: `integrations_test.exs`; statuses/CSRF: C |
| Task 11 — `a12f3b_h01_test.exs`: integrations update route checks, saves and invalid-CSRF row | R | routes removed; background-job imports in the same case still run through `POST /settings/background_jobs` |
| Task 11 — `auth_api_keys/http_test.exs` (whole file) and `standalone_api_key_flow_test.exs` (whole file: `POST /settings/generate_api_key`) | B + C | rotation commits, old key refused over bearer while a stale rate-limit cache entry exists, new key accepted: `account_live_test.exs` "a new API key replaces the old one…"; stale session refused: "a session from before a password change…"; rollback keeps the cache: `after_commit_account_cache_test.exs` (now on `ApiKeys.rotate/3`); CSRF, redirect, session cookie: C |
| Task 11 — `a12f3b_n05_test.exs`: API key half of N05a and the generate-key refusal row of N05b | B | rotation retargeted onto `Dawarich.Settings.rotate_api_key/2` (new 64-char key, old key gone, other user and settings untouched) |
| Task 11 — `auth_gate_test.exs` / `auth_common_pipeline_test.exs` / `endpoint_test.exs`: `api_keys` flow ownership of `/settings/generate_api_key` | R | the flow key still parses but owns no route; in coexistence the path goes to Puma (endpoint hand-back cases unchanged) |
| Task 11 — `a12f3b_h01_test.exs`: route-based key rotation and immediate cache eviction in the settings walk | B | `account_live_test.exs` rotation case; the eviction now runs through the durable after-commit worker (`after_commit_account_cache_test.exs`) |
| Task 11 — `user_data_test.exs` (whole file: export/import endpoints, CSRF, hand-back keys, 7-locale legacy-trial matrix, result flashes) | B + C | `test/dawarich/user_data_parity_test.exs`: the recorded per-locale outcomes and legacy-trial count/size/subscribed boundaries now run on `Dawarich.UserData` (outcome plus the native message equals Rails' recorded flash), same-name archives get a timestamped name, Sidekiq ownership writes Rails commands; browser flow: `account_live_test.exs` export and `account_import_upload_test.exs`; CSRF/hand-back/`x-dawarich-handler`: C |
| Task 11 — `a12f3a_e_closure_test.exs` E04: export GET, container imports, foreign and owner imports through the endpoint | B | same case calls `Dawarich.UserData.request_export/1` and `start_import/2` (containers refused with Rails' recorded alert, foreign archive refused, owner import queued), worker run unchanged |
| Task 11 — `a12f3a_o_closure_test.exs` O07: export route ownership, endpoint export loop and post-commit response failure; `strangler_test.exs` rails_key hand-back via `/settings/users/import` | R/C | routes removed; the strangler case now uses `/trips/:id/share_link` (`trip_shares`) |
| Task 11 — `standalone_auth_pages_test.exs`, `endpoint_test.exs`: `/settings/users/export` in the protected/Phoenix page lists | R | route removed (coexistence still forwards it to Puma) |
| Task 11 — fixtures `phoenix-fixtures/settings/{general,account,integrations}_*` (40 files) and `phoenix-fixtures/auth/account/*.html` (19 Rails 422 page renders) | M | no remaining reader: the HTML parity cases were removed in Tasks 4, 7 and 9a (rows above); recorded request/response JSON stays (`auth/account/requests.json`, `validation.json`, `api_keys.json`, `user_data/http.json`, `user_data/a12f3a-e04.json`) |
| Task 11 — `page_envelopes/{rails,routes}.json`, `standalone/html_pages.json` entries for the migrated pages | kept | still read by `page_envelopes_test.exs` and `standalone_html_pages_test.exs`, which pass unchanged |

## Native integrations behaviour coverage (Tasks 6–8)

| Behaviour from the map | Covering tests |
| --- | --- |
| Credential saves, sentinel preservation/replacement and URL-only changes for all four providers | `integrations_test.exs`: "credentials save every provider…"; `settings_integrations_live_test.exs`: "each credential pane…", "saving every provider…" |
| Expired/full-access refusals, Cloud Lite upgrade state, event-time expiry | `integrations_test.exs`: "credential failures…"; `settings_integrations_live_test.exs`: "Lite shows…"; retained `settings_live_test.exs` Cloud Lite case |
| Normalized connection URLs, failure alerts, notice order/cache refresh, top-level and nested SQL transaction behaviour | Retained `small_parity_integrations_test.exs`, `standalone_integrations_flow_test.exs`, `a12f3b_i01_test.exs`; `integrations_test.exs`: "credential failures…", "photo cache refresh…" |
| Stored secrets absent from both static and connected HTML | `settings_integrations_live_test.exs`: "each credential pane…"; rewritten `settings_live_test.exs` masked-secret case |
| Default/unknown pane, nav statuses, admin geocoding link, patch/reload state, SSL warning without saving | Retained `settings_live_test.exs` default/status/geocoding cases; `settings_integrations_live_test.exs`: "pane patches…" |
| AirTrail/TeslaMate durable jobs, conditional URL rows, repeated sync clicks, selected-pane notice; photo import controls remain elsewhere | `integrations_test.exs`: "sync writes…"; `settings_integrations_live_test.exs`: "AirTrail and TeslaMate sync…", "pane patches…"; existing job-action tests retained |
| TREK verification, encryption, reconnect/import claim, provider failure and disabled state | `integrations/trek_test.exs`: "create verifies…"; retained `standalone_trek_sources_test.exs`; `trek_sources_live_test.exs`: "foreign malformed…" |
| Dated active selection, filtered/deduplicated identifiers, atomic job publication, repeat import refusal, clear-token rotation | `integrations/trek_test.exs`: "list and import…", "manual sync…"; `trek_sources_live_test.exs`: "native trip selection…"; retained handler atomic-publication rollback probe |
| TREK source-order/actions, create navigation, once-per-page sync, disconnect confirmation and retained trip data | Retained `settings_live_test.exs` source-order case; `trek_sources_live_test.exs`: "native create…", "native sync…"; `integrations/trek_test.exs`: "manual sync…" |
| Owner/malformed ID, active/Pro refusal; the HTTP form routes were removed in Task 11 (404, `removed_page_writes_test.exs`) | `integrations/trek_test.exs`: "foreign malformed…"; `trek_sources_live_test.exs`: "foreign malformed…"; retained `standalone_trek_sources_test.exs` HTTP refusal cases |
| Native route ownership, no Hotwire, integrations query budget at most 6 static / 5 connected | `storage_routes_test.exs`, `native_pages_hotwire_free_test.exs`, `settings_integrations_live_test.exs`: "integrations stays…" |

Repository decisions: ADR-0017 and ED-NATIVE-INTEGRATION-SECRETS / ED-NATIVE-TREK-HTML-VARIANTS. Shared knowledge counterparts: AFFiNE “Dawarich — Standalone integration settings and photo imports” and “Dawarich — Standalone TREK source management” (native milestone 3a addenda).

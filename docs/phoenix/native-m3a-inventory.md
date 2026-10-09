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
| `settings_live_test.exs`: raw-secret HTML assertions in "integration secrets reach the page but not the LiveView state" | M→changed | Renamed to "integration secrets are masked on the page and in inspected LiveView state"; `settings_integrations_live_test.exs` "each credential pane hides stored secrets in static and connected HTML and preserves the sentinel"; ED-NATIVE-INTEGRATION-SECRETS |
| `settings_live_test.exs`: hidden `service` field and Turbo disconnect confirmation selectors | M | Existing default/status and source-order behaviours kept; native form and `data-confirm` selectors replace Rails markers. `trek_sources_live_test.exs` "native sync queues once and confirmed disconnect retains managed trip data" |
| `settings_live_test.exs`: "Rails form controls …" — five integration pane entries | C | `settings_integrations_live_test.exs` "pane patches survive reload and SSL changes are local until save without photo import buttons"; LiveView form state owns edits |
| `settings_parity_test.exs`: `integrations_*` Rails HTML/Stimulus parity cases | M | `settings_integrations_live_test.exs`, `trek_sources_live_test.exs`, retained `settings_live_test.exs` status/default/upgrade/source-order behaviours; fixtures retained for Task 11 |

| `standalone_integrations_flow_test.exs`: Rails form-action/CSRF-token selector | M | Handler transaction and rollback assertions retained with the established `RailsCsrf.masked_token` helper; native form save covered by `settings_integrations_live_test.exs` |
| `a12f3b_i01_test.exs`: direct legacy pane rendering for masked-secret HTML | M | Existing credential/validation/checkpoint/sentinel behaviours retained; all providers' mounted secret masking covered by `settings_integrations_live_test.exs` |

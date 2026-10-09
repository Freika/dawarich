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

# Phoenix browser settings and notifications

The SETTINGS package implements Plan B tasks N01–N06. The settings API remains owned by A12f-2 D. Browser writes use the existing Rails session, CSRF helpers, native persistence, and domain scheduling primitives.

Notification POST mark-as-read/destroy-all and DELETE-one actions scope every write to the authenticated actor, return 303 redirects with localized flashes, and reject foreign IDs. Reading a SQL-written blank notification raises a native 422 and preserves its unread state. Native notification title/content/kind/read-state updates append the existing durable notification event; connected views subscribe to the existing Cable stream and refresh cards and the unread navbar from owned rows.

Connected view authorization rechecks account/password authority before events. Successful native logout signals connected views sharing that Rails session through Phoenix PubSub. The signal uses a hashed topic derived from the existing session identity; it adds no persistent session store. It does not retire Rails' stateless cookie semantics or create cross-node session revocation infrastructure. The decision and its limits are recorded in `docs/adr/20261006-notification-session-events.md` and AFFiNE ADR `TYl2ZYxialWpD_dJjeLcG`.

General PATCH/PUT and overridden POST preserve unrelated settings, Rails boolean coercion, supported locale/time-zone aliases, and digest preference migration. Time-zone changes invalidate existing monthly stats and use `Dawarich.Stats.Schedule` once per existing month in the same transaction. The existing ownership primitive chooses native or retained source scheduling. SQL failure rolls back settings, invalidation, and scheduled work and returns a native 500. The prior minimal `StandaloneSettings` plug delegates to this complete browser action.

Supporter verification stores normalized supplied identity fields, invalidates only their existing verification cache keys, and calls the existing provider/cache implementation. Empty identity and denied or malformed provider responses produce localized alerts. Verification requires literal `true`, matching Rails; a truthy string cannot mark verification successful. SMTP transport and mail worker ownership remain with MAIL. The verified Rails 1.15.3 controller denies Cloud test-email requests with a 303 and queues self-hosted requests; Plan B N04's synchronous Cloud wording conflicts with that source. This package preserves the source behavior under ruling 13.

Theme, changelog consent, and current-key rotation use legacy browser URLs. Consent Turbo responses replace the version indicator and consent setting using the existing native components. Key rotation ignores request `user_id`, validates and locks the session actor, and reuses A11's entropy/storage helper. Its new session-authorized entry point supports already authenticated provider/OTP users without changing the existing bounded A11 rotation entry point.

Onboarding PATCH/PUT and overridden POST merge only `onboarding_completed: true`. Successful responses are empty 200s; repeated completion preserves the saved timestamp. Failed persistence returns a native error so the browser cannot close the modal as success.

## Endpoint activation

The main router mounts these macros in order:

1. Keep `A10Routes` before these modules; it defines the existing guarded `:standalone_settings` pipeline.
2. `DawarichWeb.SettingsFormRoutes.settings_form_routes/0`.
3. `DawarichWeb.SettingsMiscRoutes.settings_misc_routes/0`.
4. `DawarichWeb.OnboardingRoutes.onboarding_routes/0`.
5. `DawarichWeb.NotificationFormRoutes.notification_form_routes/0`.

All four modules reuse `:standalone_settings`; they introduce no unmounted pipeline names.

The duplicate minimal `/settings/general` declarations have been removed from `A10Routes`; its test-email route remains mounted. Every new route declares the standalone ownership gate; retained-source operation remains available during coexistence. DEMO adds its separate onboarding/demo routes.

In standalone mode, `AuthGate` lets current-key rotation reach the mounted SETTINGS action instead of intercepting it with the bounded A11 handler. This preserves session-authorized provider/OTP rotation through the real endpoint. During coexistence, the existing A11 handler remains available under its configured auth flow.

The minimal external seams are `AuthHandler` (successful-logout signal), `RailsAuth.live_session` and `LiveAuth` (session topic propagation), `NavbarHooks` (subscription and authorization hooks), and `Auth.ApiKeys` (session-authorized entry point). These are part of the SETTINGS handoff, not changes to the settings API.

## Validation and remaining integration

Task tests are `test/dawarich_web/a12f3b_n01_test.exs` through `a12f3b_n06_test.exs`. Each plan selector has recorded RED, GREEN, a failing named production mutation, and restored GREEN. Source characterization extends the existing notification/settings generators and onboarding request specs. Retained fixture recording was run twice with byte-identical output.

The retained H01 endpoint tests also cover the mounted method/path inventory without duplicate declarations, native settings and notification writes in self-hosted and Cloud standalone mode, session/CSRF refusal before effects, exact coexistence handback, and GET/HEAD theme response equivalence. API-key rotation primes the old rate-limit cache entry and verifies its invalidation, retired-key refusal, and preservation of another user's key.

Under ruling 15, unsupported nested/duplicate/legacy envelope edge cases may return native errors in standalone mode; this package does not invent Rails bug fixes or claim complete rare-envelope parity. The controller owns seed 202 on the integration head and deferred Rails bug records. The execution reports record gate output and these integration responsibilities.

Shared documentation: AFFiNE document `sIL5FiAZt9ZWDGTJTbQ2O` (Dawarich — Phoenix browser settings and notifications).

## Standalone settings journey regression

General settings must start a normal `Repo.transaction/1`. Unconditional `mode: :savepoint` cannot begin a transaction on an idle Postgrex connection: it returns a rollback without saving preferences and produces the failure flash. Database sandbox tests conceal this because their connection already has an open transaction.

`test/dawarich_web/standalone_settings_flow_test.exs` exercises the real Endpoint with `DAWARICH_RAILS=off`, an encrypted Rails session, rendered CSRF input, and a database checkout with `sandbox: false`. It verifies the 302 redirect, empty body, success flash, persisted and rendered timezone, monthly Oban arguments, and unchanged-zone idempotence. An injected Oban insertion error proves that preferences and stat invalidation roll back together. Each test cleans up its committed rows.

Session-authorized API-key rotation also starts a normal transaction. Its former unconditional savepoint produced the same rollback, then a result-match exception and empty 500. The merged `persist/2` helper correctly deletes the previous key's rate-limit cache entry after a successful update; that behavior remains intact.

`test/dawarich_web/standalone_api_key_flow_test.exs` uses the same standalone Endpoint and unsandboxed database boundary. It follows the account page's rotation link using its rendered CSRF token, verifies the source 302/referrer/empty-body contract, preserves the signed-in session and unrelated user fields, retires the old key through query and Bearer requests, and checks cache invalidation. It also covers authenticated provider/OTP users and rejected SQL updates that retain the current key and cache. Named savepoint and omitted-cache-deletion mutations both fail this flow.

## Transaction and cache boundary regressions

`Dawarich.Transaction.run/3` starts a plain transaction on an idle connection and selects savepoint mode only inside an existing transaction. `Dawarich.Transaction.options/2` applies the same selection to SQL statements that need savepoint error recovery. Ecto flattens nested transaction callbacks; putting a statement inside another callback does not replace its statement-level savepoint. All literal savepoint options in native production code are confined to this helper, enforced by `test/dawarich/transaction_test.exs`.

Onboarding completion and demo import/removal use the helper. `test/dawarich_web/standalone_transaction_flow_test.exs` exercises each through the real Endpoint with `sandbox: false` and cleans its committed rows. It also verifies standalone account updates and uppercase locale normalization: `DE` persists and stages `de`, with the German success flash. AccountClosure's update already has an outer transaction; its update statement now obtains recovery options from the helper. The map-matching migration's column step remains explicitly transactional. The production-runner test in `test/dawarich/release_migrations/map_matching_deadline_test.exs` verifies that its ALTER statements execute inside that transaction, including handled lock failures and retries on ordinary database connections.

`Dawarich.TtlCache.fetch/4` claims a miss with a unique pending token before invoking its loader. Filling the entry uses atomic ETS replacement only while that token still exists. Deletion, replacement, or eviction invalidates the token, so an older loader cannot restore a retired key. Pending entries are misses; nil/no-cache and exceptions remove only their own pending entry. Capacity eviction happens only when filling a cached value and preserves that pending token; uncached unknown-key lookups cannot flush unrelated live entries. An already running reader may receive its computed value, but subsequent readers do not receive a resurrected cache entry. `standalone_api_key_flow_test.exs` pauses the real plan SELECT using query telemetry, rotates the key through the Endpoint, then releases the reader and verifies cache absence and retired-key rejection. Session rotation also invalidates the retired key after its transaction returns: the token check handles delayed loads that began before deletion, and post-commit deletion handles loads that could begin after the early deletion while the old row was still visible. The same regression injects a cache fill on commit telemetry to verify final invalidation, alongside its real paused database lookup. This change preserves direct database authentication and does not add authentication caching.

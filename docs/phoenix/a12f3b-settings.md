# Phoenix browser settings and notifications

The SETTINGS package implements Plan B tasks N01–N06. The settings API remains owned by A12f-2 D. Browser writes use the existing Rails session, CSRF helpers, native persistence, and domain scheduling primitives.

Notification POST mark-as-read/destroy-all and DELETE-one actions scope every write to the authenticated actor, return 303 redirects with localized flashes, and reject foreign IDs. Reading a SQL-written blank notification raises a native 422 and preserves its unread state. Native notification title/content/kind/read-state updates append the existing durable notification event; connected views subscribe to the existing Cable stream and refresh cards and the unread navbar from owned rows.

Connected view authorization rechecks account/password authority before events. Successful native logout signals connected views sharing that Rails session through Phoenix PubSub. The signal uses a hashed topic derived from the existing session identity; it adds no persistent session store. It does not retire Rails' stateless cookie semantics or create cross-node session revocation infrastructure. The decision and its limits are recorded in `docs/adr/20261006-notification-session-events.md` and AFFiNE ADR `TYl2ZYxialWpD_dJjeLcG`.

General PATCH/PUT and overridden POST preserve unrelated settings, Rails boolean coercion, supported locale/time-zone aliases, and digest preference migration. Time-zone changes invalidate existing monthly stats and use `Dawarich.Stats.Schedule` once per existing month in the same transaction. The existing ownership primitive chooses native or retained source scheduling. SQL failure rolls back settings, invalidation, and scheduled work and returns a native 500. The prior minimal `StandaloneSettings` plug delegates to this complete browser action.

Supporter verification stores normalized supplied identity fields, invalidates only their existing verification cache keys, and calls the existing provider/cache implementation. Empty identity and denied or malformed provider responses produce localized alerts. Verification requires literal `true`, matching Rails; a truthy string cannot mark verification successful. SMTP transport and mail worker ownership remain with MAIL. The verified Rails 1.15.3 controller denies Cloud test-email requests with a 303 and queues self-hosted requests; Plan B N04's synchronous Cloud wording conflicts with that source. This package preserves the source behavior under ruling 13.

Theme, changelog consent, and current-key rotation use legacy browser URLs. Consent Turbo responses replace the version indicator and consent setting using the existing native components. Key rotation ignores request `user_id`, validates and locks the session actor, and reuses A11's entropy/storage helper. Its new session-authorized entry point supports already authenticated provider/OTP users without changing the existing bounded A11 rotation entry point.

Onboarding PATCH/PUT and overridden POST merge only `onboarding_completed: true`. Successful responses are empty 200s; repeated completion preserves the saved timestamp. Failed persistence returns a native error so the browser cannot close the modal as success.

## HOT handoff

Import and mount these macros in order:

1. Keep `A10Routes` before these modules; it defines the existing guarded `:standalone_settings` pipeline.
2. `DawarichWeb.SettingsFormRoutes.settings_form_routes/0`.
3. `DawarichWeb.SettingsMiscRoutes.settings_misc_routes/0`.
4. `DawarichWeb.OnboardingRoutes.onboarding_routes/0`.
5. `DawarichWeb.NotificationFormRoutes.notification_form_routes/0`.

All four modules reuse `:standalone_settings`; they introduce no unmounted pipeline names.

Remove the duplicate minimal `/settings/general` declarations from `A10Routes` when mounting `SettingsFormRoutes`. Preserve the existing test-email route. Every new route declares the standalone ownership gate; retained-source operation remains available during coexistence. Endpoint route activation and final HTTP integration evidence belong to HOT. DEMO adds its separate onboarding/demo routes after this shared module handoff.

The minimal external seams are `AuthHandler` (successful-logout signal), `RailsAuth.live_session` and `LiveAuth` (session topic propagation), `NavbarHooks` (subscription and authorization hooks), and `Auth.ApiKeys` (session-authorized entry point). These are part of the SETTINGS handoff, not changes to the settings API.

## Validation and remaining integration

Task tests are `test/dawarich_web/a12f3b_n01_test.exs` through `a12f3b_n06_test.exs`. Each plan selector has recorded RED, GREEN, a failing named production mutation, and restored GREEN. Source characterization extends the existing notification/settings generators and onboarding request specs. Retained fixture recording was run twice with byte-identical output.

Under ruling 15, unsupported nested/duplicate/legacy envelope edge cases may return native errors in standalone mode; this package does not invent Rails bug fixes or claim complete rare-envelope parity. HOT owns mounting and endpoint acceptance; the controller owns seed 202 on the integration head and deferred Rails bug records. The execution report records gate output and these integration responsibilities.

Shared documentation: AFFiNE document `sIL5FiAZt9ZWDGTJTbQ2O` (Dawarich — Phoenix browser settings and notifications).

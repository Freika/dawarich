# L1 package B — Cloud registration and seeds

Preparation only: public native Cloud migrate/seed remains refused in every mode until package F completes the external handoff and security review.

`Dawarich.Users.CreationEffects.apply/3` requires the caller's transaction, locks the account and stores completion in the existing processed-command ledger. It creates an API key only when absent. Ordinary Cloud creation preserves the Rails default plan, grants a seven-calendar-day trial in the configured timezone, publishes welcome mail immediately and explore mail two calendar days later, and queues Manager creation. `skip_auto_trial` preserves supplied state and publishes Manager only. Replay preserves later paid/family state and key, including after completed outbox pruning.

`RegistrationCallbacks.context/1` fills missing Manager, Partnero and real family-invitation callbacks using the context's repository; explicit injections remain supported. Browser insertion, setup, invitation and attribution publish in one transaction; mobile follows the same transaction with its existing input whitelist and response contract. Provider resolution publishes creation only for a new identity; existing identity/login/link paths publish no new creation. Ordinary OAuth consumes referral after successful creation; Apple retains Rails behavior without Partnero attribution. Referral precedence is aff before via, limited to 255 Unicode codepoints. Failed signup retains the session referral.

Manager delivery uses the shared committed-callback/HTTP primitives. No external effect runs inside an account transaction. Manager's non-2xx acknowledgement remains Rails-compatible; transport failures remain retryable. Shared transport supplies a bounded timeout, verified TLS, fixed configured origin/path and no redirects. Manager and Partnero retain Rails delivery parity without a remote dedup guarantee; PostgreSQL receipts do not make HTTP atomic.

Cloud ordinary seeds omit the Rails demo administrator, by Eugene's 2026-10-07 ruling. Administrators are created manually. Reference seeds and populated/soft-deleted-account reentry remain unchanged; Cloud seed execution does not recreate accounts or restart trials. Self-hosted bootstrap retains existing behavior.

## Register handoff to package F

| Register | Required entry | Evidence |
|---|---|---|
| Expected difference (F assigns ID) | Cloud seeds omit Rails demo admin; manual administrator creation required | `seeds/cloud_bootstrap_test.exs`: Cloud bootstrap omission and lease-backed reentry |
| Fixed Rails bug (F assigns disposition) | Rails after_commit enqueue failure can leave an account without creation callback; Phoenix rolls back account, state, invitation/attribution and intents on publication failure | Rails `app/models/user.rb:56`, `app/controllers/users/registrations_controller.rb:28`; native `auth/registration.ex:109`, `auth/providers/accounts.ex:177`; `auth/cloud_registration_test.exs` |
| Expected difference, reuse A's entry when present | Bounded shared Manager creation transport replaces Rails' missing explicit timeout | `users/creation_effects_test.exs`: signed source payload and HTTP policy |

Evidence uses the real synthetic Rails oracle `test/support/cloud_creation_oracle.rb`, captured source projection `test/fixtures/cloud_creation/source.json`, default HTTP handler tests, concurrent account resolution, rollback and replay assertions, and one failing production mutation for each new named test. Exact commands and final gate results live in the controller's package B implementation report. Public lifecycle guards and package A's shared files are unchanged.

AFFiNE counterpart: Dawarich — Phoenix A12f-3c Cloud cut-over, drain and rollback plan, L1 package B handoff (document `AVWr5ao5n-OKCZZbEphrP`).

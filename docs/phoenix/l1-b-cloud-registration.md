# L1 package B — Cloud registration and seeds

Preparation only: public native Cloud migrate/seed remains refused in every mode until package F completes the external handoff and security review.

`Dawarich.Users.CreationEffects.apply/3` requires the caller's transaction, locks the account and stores completion in the existing processed-command ledger. It creates an API key only when absent. Ordinary Cloud creation preserves the Rails default plan, grants a seven-calendar-day trial in the configured timezone, publishes welcome mail immediately and explore mail two calendar days later, and queues Manager creation. `skip_auto_trial` preserves supplied state and publishes Manager only. Replay preserves later paid/family state and key, including after completed outbox pruning.

`RegistrationCallbacks.context/1` fills missing Manager, Partnero and real family-invitation callbacks using the context's repository; explicit injections remain supported. Browser insertion, setup, invitation and attribution publish in one transaction; mobile follows the same transaction with its existing input whitelist and response contract. Provider resolution publishes creation only for a new identity; existing identity/login/link paths publish no new creation. Ordinary OAuth consumes referral after successful creation; Apple retains Rails behavior without Partnero attribution. Referral precedence is aff before via, limited to 255 Unicode codepoints. Failed signup retains the session referral.

A valid invitation to a lapsed or full Cloud family is an ordinary business refusal. Browser and mobile signup keep the account in pending-payment status, retain exactly one Manager intent and publish no welcome/explore or family-join mail. Browser checkout carries Rails' invitation refusal alert. Genuine callback/publication failures still roll back account and intents. OAuth retains Rails' separate flow: signup keeps the pending account and redirects to the invitation page without attempting acceptance; the default acceptance callback distinguishes these refusals from infrastructure errors.

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

## Handoff to F — Cloud demo administrator omission

Package F alone owns `app-phoenix/parity/expected_diffs.md`. Add the following exact row in the lifecycle expected-difference table, replacing only `F assigns ED ID` with the next available ID. The public lifecycle refusal remains unchanged; this approval covers only omission of the seeded account.

| ID | Surface | Rails today | Phoenix | Owner | Status |
|---|---|---|---|---|---|
| F assigns ED ID | Ordinary Cloud demo administrator bootstrap | Empty ordinary Cloud seeds create the demo administrator and apply ordinary account creation effects. | Ordinary Cloud seeds create no demo administrator and publish no account creation effects; administrators are created manually. Self-hosted bootstrap and populated/soft-deleted account reentry remain unchanged. | L1 package B; Eugene ruling 2026-10-07; `seeds/cloud_bootstrap_test.exs`: `L1 Cloud bootstrap omits demo admin while ordinary creation retains Rails trial effects`, `L1 populated Cloud seed and release reentry never recreate user or callback identities`; register owned by package F | closed (approved difference; public Cloud lifecycle remains refused) |

## Creation, seeds and migration readiness

Creation effects and ordinary seed reentry leave the source schema/data ledgers, private Phoenix/Oban ledgers and native-origin metadata unchanged. A missing migration remains missing after account creation or seed execution; neither operation repairs readiness or stamps historical work performed. `seeds/cloud_bootstrap_test.exs` covers these boundaries with real creation intents and lease-backed seeds. Achievement publication/completion and source-data readiness remain package A's contracts, covered by `release/cloud_review_test.exs` and `readiness_test.exs`.

A reused test database can retain private migration versions from a newer checkout. An older checkout without those migration files correctly refuses Cloud provisioning with `:newer_private_schema`. The native missing-ledger test can also delete that extra maximum version instead of a required version. Compare recorded versions with the checkout's catalogue when diagnosing this combination. Use a database initialized for the tested checkout or integrate the matching migrations; do not weaken lifecycle/readiness checks or stamp missing versions in creation/seeds. The L1 B review fix 4 report records a deterministic reproduction by omitting the digest migration from the runtime catalogue while retaining its recorded version.

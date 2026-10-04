# A12c residual mail

Implementation is in progress on `feat/phoenix-a12c-mail`, starting at `0672ae88e`.
Acceptance is tests only; stand/browser/image acceptance is deferred to the controller mini lane.
No mail ownership has changed. Auth mail is security-sensitive; no AFFiNE writes are made.

## Rails corpus

The existing `app-phoenix/scripts/parity/explore_features_mail_spec.rb` captures deterministic
fixtures under `app-phoenix/test/fixtures/mail/residual/`. Write mode requires
`WRITE_PHOENIX_FIXTURES=1`; ordinary execution compares bytes without writing.
The original explore-features corpus remains byte-identical.

- `content.json`: 23 reachable OTP-lock, test, location-request and Devise content rows,
  including recipient/ambient locales, special characters, time zones and decoded MIME trees.
- `auth_intents.json`: 17 real-model callback/OTP cases, including suppressed notifications,
  old-email recipients, synchronous delivery failure, OTP cache throttling and enqueue failure.
  The existing A11 recovery mail/lifecycle/token/effects oracles remain dependencies.

Devise 5.0.4 Cloud email/password callbacks invoke `deliver_now`; the capture intercepts that
delivery boundary while retaining actual saves, callback predicates and rendering. They remain
Rails-owned, as does OTP lockout accounting and mail enqueue. Supported reset/unlock flows keep
their existing native recovery owner.

User does not enable Confirmable. Confirmation fields, route and producer are absent;
`reconfirmable = true` alone does not enable it. The dormant confirmation template remains.
Successful confirmation/reconfirmation parity awaits an enabled real Rails contract.
Account-destruction confirmation is a separate existing route.

Runtime source search finds no `member_joined` producer. Its mailer/template remain for fallback.
The four trial lifecycle mail actions remain no-ops and their job wrapper skips them.

## Verification progress

R1's two named captures have initial RED and restored GREEN evidence. M-R1-case omits
reachable email-change rows and fails the fixed case list. M-R1-recipient changes the installed
Devise callback recipient to the new email and fails the old-recipient assertion; source restored.
Three generator examples pass in write mode. The initial compare failed because Ruby compared
binary fixture strings against UTF-8 generated strings; the helper now compares binary bytes.
Post-fix compare is blocked before examples: Postgres reports that the database system is
shutting down. Ruby lint passed with cache disabled before that one-line byte-comparison fix.

Resume at R1's no-write comparison once Postgres is available, then proceed to R2.
Native rendering, delivery workers, ownership wiring, test-mail HTTP,
ED allocation and final C1–C5 gates are pending. Rails source/specs and dormant stubs are retained.

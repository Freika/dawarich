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
- `digest_content.json`: 27 monthly/yearly cases and 21 chart helper cases, with exact decoded
  bodies, MIME trees and data projections. Cases cover units/locales, leap dates, strict
  60-minute filtering, Unicode/tied ranks, nil/malformed JSON, negative/fractional values,
  sparse yearly stats, trend boundaries and sharing links.
- `effects.json`: 44 digest staging/transport cases and 10 location reverse-command cases.
  Real serialized jobs retain ambient locale/time zone; mail rendering reads current preferences.
  Enqueue failure preserves nil `sent_at`, validation failure can leave mail queued, and later
  SMTP failure preserves the timestamp. Negative distances and inactive users remain eligible.

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
R1's three generator examples now pass in no-write mode after the controller's Postgres recovery;
Ruby lint passes with cache disabled. Binary fixture bytes compare against generated binary
bytes, preserving the original UTF-8 content.

R2 captures source rendering without calculation or delivery. M-R2-threshold changes the
significant-minute threshold to 61 and fails because the 61-minute country disappears.
The threshold is restored to 60. Rails sorts UTM query keys, and yearly sharing links depend
on a present UUID even when sharing is disabled; the corpus retains those source behaviors.
Malformed location integers and mixed-sign bars raise rather than producing empty mail.

R3 observes delivery enqueue before the timestamp update. Its save-failure case uses an actual
invalid month and model validation, with no mocked database behavior. Missing serialized digest
records discard delivery; queued soft-deleted User records still deliver under Rails GlobalID
lookup. Accepted/expired location requests still mail, missing targets fail rendering, missing
requests discard, repeated reverse commands enqueue once, and enqueue failure releases the cache
claim. Generation's retained Rails reverse handler selects `user.locale` before queueing.
M-R3-sent-order moves the timestamp before enqueue and fails the explicit enqueue-failure
case. The source is restored; the named capture and no-write fixture comparison pass.

Resume at R4 after R3's restored named test and byte comparison are green.
Native rendering, delivery workers, ownership wiring, test-mail HTTP,
ED allocation and final C1–C5 gates are pending. Rails source/specs and dormant stubs are retained.

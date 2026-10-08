# Standalone authentication and demo import corrections

OTP browser lockout queues `Dawarich.Mail.OtpAccountLockedWorker` through the
native auth gate. The tenth invalid code persists the account lock and returns
the Rails sign-in redirect. The existing Redis throttle remains authoritative;
mail delivery uses the existing native worker and recipient locale rules.

Trial welcome requires `JWT_SECRET_KEY`, as Rails does. With the key configured,
invalid anonymous links redirect to sign-in. Without the key, standalone returns
a server error with no-store headers; coexistence retains Rails hand-back.
Envelope, session, CSRF and ownership checks remain in force.

Password recovery requires `DOMAIN` for absolute mail links. The Rails mailer
raises a missing-host rendering error without it; the native recovery worker
also refuses delivery. Configure `DOMAIN` in the browser harness and deployment.
No fallback host is introduced.

Demo country assignment filters subdivided country geometry to the imported
points' bounding box before joining against those points. This removes irrelevant
polygon comparisons while preserving exact spatial intersections, the full demo
fixture, transaction deadline, adoption and deletion semantics. The regression
uses the real browser POST envelope and an executed query plan to bound candidate
pieces, without a timing assertion or machine-wide load.

Verification lives in `standalone_credentials_otp_test.exs`,
`trial_welcome_endpoint_test.exs`, `standalone_demo_import_test.exs`, the existing
recovery mail tests, and demo importer/adoption/destroy callers. Controller browser
acceptance remains separate from these ExUnit and Rails characterizations.

The unchanged browser specs passed three consecutive standalone runs and one
coexistence run: OTP lockout, four password recovery cases, two trial routing
cases, three demo-load cases, demo adoption and demo deletion. Each run passed
all 12 scenarios plus authentication setup with one worker, zero retries and
no skipped or flaky tests. The harness supplied `DOMAIN` and JWT configuration,
and each standalone run passed the source-drain and native-readiness checks.

Rails bugs fixed: none. These changes repair native wiring, failure handling and
work amplification; no new ED or DRB row is needed.

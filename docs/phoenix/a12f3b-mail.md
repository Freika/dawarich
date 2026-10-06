# A12f-3b MAIL producer contracts

Last updated: 2026-10-06. Scope: plan C M01–M12. This package supplies native mail producer seams and preserves Rails behavior; it does not activate Cloud routing, flip owners, or certify source retirement.

## Producer interfaces

- `Dawarich.Mail.DeviseCallbacks.update/4` saves a validated email/password hash and native notification intents together. `after_update/3` returns accepted jobs for callers that already own the credential transaction; call `after_commit/1` only after that transaction commits. An SMTP failure after commit leaves the credential saved, returns a delivery failure, and retains a retryable intent. `update/4` defers synchronous delivery when called within an existing transaction. CLI email/password changes use this seam. Production Cloud sends email-change notifications to the old address and password-change notifications to the resulting address. Unchanged values, skip flags, and self-hosted mode suppress them. Password validation/hashing, registration, session changes, API validation, and account lifecycle stay with the authentication owner.
- `Dawarich.Mail.UserCallbacks.created/3` runs inside the creator's transaction after the user and trial effects exist. Cloud trial creation produces welcome immediately and explore-features two days later; self-hosted and `skip_auto_trial` suppress both. Both command owners must be native. Locked user lookup and outbox dedupe preserve the first accepted event and schedule across replay, including dispatched rows. The caller owns trial creation and webhook effects.
- `Dawarich.Mail.UserCallbacks.link/5` accepts the authentication owner's already-issued OAuth-link or destruction-confirmation URL. It preserves URL, token expiry, provider label and SHA-256 digest in a typed command. Existing workers verify the accepted URL against its digest; queued args omit the raw URL. Signing and account deletion remain separate authentication responsibilities.
- `Dawarich.Auth.Otp.Lockout.register_failed_attempt/3` commits source-compatible failed-attempt/lock accounting before the cache throttle and mail enqueue. Ten attempts lock for thirty minutes; an expired lock restarts accounting. The one-hour throttle uses the Rails-compatible cache entry, not a new SQL timestamp column. Enqueue or SMTP failure does not undo the lock or clear the throttle. The authentication owner must call it from the native invalid-OTP path.

## Delivery and retry behavior

Explicit Reply-To is retained for multipart and HTML-only SMTP. Reset/unlock delivery uses the current recipient locale and original raw token while keeping only the digest in recovery state. Credential notification content retains the source callback's old/new recipient snapshot and locale.

Archival retry retains its first claim time and deterministic subscription JTI, so the accepted event's upgrade URL and Message-ID remain stable after rejection. Family-lapse retry reuses its initial claim key even though Rails clears the user warning flag on SMTP failure. Delivery receipts are written after transport acceptance. SMTP cannot provide exactly-once receipt across an acceptance/receipt-write crash.

Test-email admission accepts the transport's existing STARTTLS, SSL and plain/login/CRAM-MD5 authentication configuration. Retained Rails test mail is HTML-only without a test MIME header; the Cloud HTTP endpoint rejects the action and self-hosted delivery queues it. The ADMIN owner consumes the existing `TestEmail.run/4` interface.

The existing SMTP client negotiates supported authentication mechanisms from server capabilities. Mechanism selection is not forced to the configured Rails authentication name. This package's configuration matrix and predecessor wire tests do not certify forced-mechanism or live TLS-server parity; M01 remains incomplete. Phoenix also still rejects Rails-configurable `digest_md5`, `gssapi`, `ntlm` and `xoauth2` names. Closing M01 requires selected-mechanism and supported/error parity plus local authenticated/TLS wire tests.

Location commands continue accepting the existing two-field payload and additionally accept an explicit ambient locale. Native workers use current target preferences first, then the accepted fallback locale. Owner OFF emits only a reverse command; owner ON emits only the forward intent. FAMILY owns request validation and cache-NX producer accounting.

Digest child events are deterministic from period and parent event. They differ from the calculation event and keep the first locale, timezone, due time and payload after dispatch/replay. Preserve [DRB-013](deferred-rails-bugs.md): digest `sent_at` is set after enqueue, before SMTP acceptance; a validation failure after enqueue can leave mail queued. This package does not change that Rails bug.

## Dormant source debt

`Dawarich.Jobs.Drain.status/2` optionally accepts `source_status:` from retained Rails `JobDrain.status`, with observed queued/scheduled/retry/dead/busy/unknown counts. Unknown/nonzero wrapper debt blocks forward and binary rollback gates; an unreadable snapshot also blocks them. This interface never deserializes Ruby arguments or GlobalIDs. Native typed workers discard their own missing recipients without a delivery receipt.

The controller must supply the retained-source census to the operational gate. An absent optional snapshot preserves the preexisting native-only status, and a private synthetic empty queue is not evidence for source retirement. Under master ruling 9, confirmation, member-joined and the four no-op trial APIs/templates may be removed only after retained wrappers are inventoried and disposed. They remain present in this package.

## Integration handoffs and verification

A11 consumes credential, creation, link and OTP seams. FAMILY consumes invitation/lapse/location workers and owns transaction/cache admission. ADMIN consumes test-email delivery. HOT owns route, registry, CLI-root and retained-source census wiring. These consumer activations require integration-owner changes outside MAIL's file allocation; tests here exercise the interfaces directly and CLI credential changes end to end.

Named package tests are `app-phoenix/test/dawarich/a12f3b_m01_test.exs` through `a12f3b_m12_test.exs`. Retained source characterization is `app-phoenix/scripts/parity/explore_features_mail_spec.rb`; regenerate twice, compare the complete fixture tree byte-for-byte, and restore Swagger around each RSpec batch. The implementation report records actual RED, reused predecessor contracts, GREEN and isolated named mutation failures. Native package verification: 143 tests, 0 failures; retained Rails capture twice: 9 examples, 0 failures per run, complete fixture tree byte diff empty; changed Ruby lint clean. Final full seed-404 gate is recorded in the implementation report.

Shared knowledge-base counterpart: `Dawarich — A12f-3b MAIL producer contracts and integration handoffs`, document ID `RufCwSB0sgxVYZGY1Jta_` in the shared AFFiNE engineering workspace.

Mandatory seed-404 gate: 8,564 tests, 4 failures. The obsolete M08 HTTP admission assertion was corrected; its targeted batch passes 5 tests, 0 failures, and its regression mutation fails before restoration. Failures in unchanged monthly export file-writing, import lease-stage synchronization and visit-sweep timezone querying remain for their owners. The full suite was not retried without those root fixes. Package status is FAILED pending gate closure and the remaining M01 transport work. All test runners and session-owned Redis services have stopped.

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

### Native SMTP authentication boundary

Rails `lib/smtp_config.rb` accepts seven authentication names; this is a configuration allowlist, not a promise that the installed SMTP library implements every name. The locked Rails runtime uses Mail 2.9.1 and net-smtp 0.5.1. net-smtp registers PLAIN, LOGIN, CRAM-MD5 and XOAUTH2 authenticators, and `Net::SMTP#check_auth_args` raises `ArgumentError: wrong authentication type ...` for DIGEST-MD5, GSSAPI and NTLM unless an extension installs an authenticator.

| `SMTP_AUTHENTICATION` | Rails with the locked gems | Native Phoenix |
| --- | --- | --- |
| absent, blank, `plain` | Forces PLAIN | PLAIN only when it is the sole mechanism supported by gen_smtp in the server advertisement |
| `login` | Forces LOGIN | LOGIN under the same sole-mechanism condition |
| `cram_md5` | Forces CRAM-MD5 | CRAM-MD5 under the same sole-mechanism condition |
| `xoauth2` | Forces XOAUTH2; password contains the bearer credential | Refuses before connection: the current native client cannot force XOAUTH2 |
| `digest_md5`, `gssapi`, `ntlm` | Config accepted, then runtime rejects without an authenticator extension | Refuses before connection with the selected name and a clear native operator error |
| `none`, `nil`, `false`, `off`, `disabled` | Disables AUTH and drops credentials | Disables AUTH and drops credentials |

Native error text states that delivery is refused without authentication or TLS fallback. Authentication failure never becomes unauthenticated mail. The pinned gen_smtp 1.3.0 client chooses CRAM-MD5, LOGIN, PLAIN, then XOAUTH2 and can fall through after rejection; its public options cannot force a mechanism. Native options therefore install a non-logging `trace_fun` guard at its pre-AUTH selection boundary. The guard accepts exactly one recognized mechanism matching the configured choice, and refuses missing, different or multiple recognized choices before sending AUTH or MAIL. Unrecognized advertised mechanisms are ignored by gen_smtp and cannot become fallback candidates. A multi-mechanism server is deliberately refused even if the selected mechanism is present. Keep that configuration on Rails or use a relay that advertises only the selected mechanism; do not disable AUTH or TLS to bypass refusal. The wire regression test must remain green before updating gen_smtp, because the pre-AUTH callback boundary is version-specific.

`SMTP_SSL=true` (or port 465 with no SSL override) uses implicit TLS. Otherwise STARTTLS defaults to required; only an explicit `SMTP_STARTTLS=false` permits a non-TLS connection. Missing STARTTLS or failed TLS cannot fall back to plaintext. Certificate verification defaults to peer with hostname checking; `SMTP_OPENSSL_VERIFY_MODE=none` remains an explicit operator override matching Rails. SMTP sessions run in a short-lived task so failed pre-AUTH negotiation also releases its sockets. The E2E sink accepts no explicitly requested AUTH/SSL/STARTTLS policy and cannot bypass unsupported-mechanism validation.

`test/dawarich/mail/smtp_policy_test.exs` covers unsupported names, sink bypass, all three supported mechanisms, ambiguous/mismatched server advertisements, rejected credentials and unavailable required STARTTLS using a local ephemeral server. Live certificate/implicit-TLS handshake certification and arbitrary forced-mechanism SMTP parity remain outside this refusal boundary; do not describe the transport as exhaustively equivalent to every Rails SMTP configuration.

Location commands continue accepting the existing two-field payload and additionally accept an explicit ambient locale. Native workers use current target preferences first, then the accepted fallback locale. Owner OFF emits only a reverse command; owner ON emits only the forward intent. FAMILY owns request validation and cache-NX producer accounting.

Digest child events are deterministic from period and parent event. They differ from the calculation event and keep the first locale, timezone, due time and payload after dispatch/replay. Preserve [DRB-013](deferred-rails-bugs.md): digest `sent_at` is set after enqueue, before SMTP acceptance; a validation failure after enqueue can leave mail queued. This package does not change that Rails bug.

## Dormant source debt

`Dawarich.Jobs.Drain.status/2` optionally accepts `source_status:` from retained Rails `JobDrain.status`, with observed queued/scheduled/retry/dead/busy/unknown counts. Unknown/nonzero wrapper debt blocks forward and binary rollback gates; an unreadable snapshot also blocks them. This interface never deserializes Ruby arguments or GlobalIDs. Native typed workers discard their own missing recipients without a delivery receipt.

The controller must supply the retained-source census to the operational gate. An absent optional snapshot preserves native SQL status with `scope: native_sql`, `g49: BLOCKED` and source inspection required, and a private synthetic empty queue is not evidence for source retirement. Under master ruling 9, confirmation, member-joined and the four no-op trial APIs/templates may be removed only after retained wrappers are inventoried and disposed. The merged Phoenix port includes the later retirement decisions and `UserCallbacks.enqueue/4`; MAIL retains its `created/3` and `link/5` producer interfaces alongside that API.

## Integration handoffs and verification

A11 consumes credential, creation, link and OTP seams. FAMILY consumes invitation/lapse/location workers and owns transaction/cache admission. ADMIN consumes test-email delivery. HOT owns route, registry, CLI-root and retained-source census wiring. These consumer activations require integration-owner changes outside MAIL's file allocation; tests here exercise the interfaces directly and CLI credential changes end to end.

Named package tests are `app-phoenix/test/dawarich/a12f3b_m01_test.exs` through `a12f3b_m12_test.exs`. Retained source characterization is `app-phoenix/scripts/parity/explore_features_mail_spec.rb`; regenerate twice, compare the complete fixture tree byte-for-byte, and restore Swagger around each RSpec batch. The implementation report records actual RED, reused predecessor contracts, GREEN and isolated named mutation failures. Native package verification: 143 tests, 0 failures; retained Rails capture twice: 9 examples, 0 failures per run, complete fixture tree byte diff empty; changed Ruby lint clean. Final full seed-404 gate is recorded in the implementation report.

Shared knowledge-base counterpart: `Dawarich — A12f-3b MAIL producer contracts and integration handoffs`, document ID `RufCwSB0sgxVYZGY1Jta_` in the shared AFFiNE engineering workspace.

Historical pre-merge seed-404 gate: 8,564 tests, 4 failures. The obsolete M08 HTTP admission assertion was corrected; its targeted batch passes 5 tests, 0 failures, and its regression mutation fails before restoration. The current Phoenix port supplies root fixes for batched monthly export writes, deterministic import lease barriers and timezone validation once per sweep page. The review-fix report records their verification and the new seed-404 gate on the merged branch. The authentication refusal boundary above replaces the earlier silent negotiation limitation; broader SMTP certification remains deferred.

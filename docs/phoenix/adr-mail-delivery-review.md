# Mail delivery ownership and test-email authorization

Status: accepted. Date: 2026-10-07. Authority: fix3 MAIL review brief. Related contract: [MAIL producer interfaces](a12f3b-mail.md). Expected differences: ED-MAIL-TEST-ADMIN, ED-MAIL-TEST-REDELIVERY and ED-MAIL-ARCHIVAL-EXPIRY.

## Context

Credential notifications had an inline executor and a runnable Oban job. Event equality admitted both before either wrote a receipt. An old archival claim also doubled as a retry deadline, permitting takeover of an active retry. Test mail lacked a receipt and admitted non-admin accounts. Rejecting non-admin requests only inside the action was insufficient: route selection could send them to the permissive Rails endpoint.

## Decision

Use the existing SQL heartbeat lease to serialize each delivery attempt durably, with a ten-minute expiry and renewal every third of that interval. Refresh `claimed_at` for the active attempt and preserve a separate immutable `issued_at`. Verify the lease before SMTP and fence shared delivery receipts by holder; report lost claims as failures. Retain the lease around family-lapse marker and SMTP work. Run workers outside enclosing transactions, allowing heartbeat renewal on an independent connection.

Test mail requires admin status in the action, producer and worker. Refuse authenticated non-admin POSTs before route selection, including explicit Rails route pins. Reload current worker authorization to reject demotion after enqueue. Assign each POST a new event UUID; legacy jobs derive identity from their durable job ID. A successful receipt suppresses redelivery. Separate POSTs remain separate messages.

Archival links retain accepted issuance/JTI identity. Cancel retries at thirty-minute expiry without SMTP or a delivered marker. Do not silently regenerate an expired accepted link.

Implicit TLS and STARTTLS receive the same certificate verification, CA-file and hostname policy. Supply implicit-TLS options through gen_smtp `sockopts` and STARTTLS options through `tls_options`; never drop authentication or required TLS to recover delivery.

## Alternatives and consequences

Removing inline delivery would change the credential failure interface. Changing only Oban job state would not protect other shared worker attempts. A timestamp without renewal would still expire during live work. Regenerating archival links would break the accepted replay identity. Refusing non-admin requests only in route eligibility would forward them to Rails.

SMTP acceptance followed by a local crash before receipt persistence remains an ambiguous resend window. Hard process death retains its lease until expiry; orderly completion/error releases it. Cancellation of a late archival warning is an explicit difference from Rails' freshly rendered token. Rails test-email authorization and redelivery remain unchanged; the native differences are recorded in the parity ledger. Cloud lifecycle refusal remains in every mode pending the external L1 handoff.

## Verification and references

Named `mail_review` regressions F1–F6 cover concurrent inline/queued delivery, stale/live retry claims, actual implicit-TLS/STARTTLS handshakes, successful-job replay, producer/worker/action authorization, route pins and archival expiry. Each has a RED reproduction, GREEN, named mutation failure and restored GREEN in `fix3-a12f3b-mail.report.md`. The ordinary source-byte test covers F7 without recording mode or relaxed comparison.

Shared AFFiNE counterpart: `Dawarich — ADR-20261007-mail-delivery-ownership — Serialize mail attempts and require admin test email`. Document ID: `77dOokS2i_6wLj5wrM_uo`. The canonical MAIL contract is AFFiNE document `RufCwSB0sgxVYZGY1Jta_`.

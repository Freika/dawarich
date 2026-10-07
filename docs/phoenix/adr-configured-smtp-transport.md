# Dawarich — configured SMTP transport

Status: Accepted. Date: 2026-10-07. Shared AFFiNE document: `5ylweLA5CBHVWv_eGnC0J`.

## Context

Standalone mail must honor Rails' configured SMTP mechanism. The previous safe refusal prevented XOAUTH2 and multi-mechanism delivery because gen_smtp_client chooses a preference order and can fall back after rejection. The controller's fix-sa-smtp brief requires configured PLAIN, LOGIN, CRAM-MD5 and XOAUTH2 parity while retaining downgrade protections.

## Decision

Authenticated delivery uses a small explicit SMTP session over gen_smtp's public `smtp_socket` connection/TLS API. The existing MIME encoder and unauthenticated transport remain. Authentication selects only the normalized configured mechanism, independent of server advertisement, as locked net-smtp does. There is no fallback after rejection. Authentication response bodies are omitted from returned errors, and no authentication material is logged.

Required STARTTLS precedes AUTH, repeats EHLO after upgrade and cannot downgrade. Implicit TLS and STARTTLS retain CA/hostname verification and explicit verification overrides. All sockets close after delivery or failure. Unsupported Rails extension mechanisms and E2E sink policy remain refused. XOAUTH2 recovery/test-email admission remains with Rails during coexistence and becomes native with `DAWARICH_RAILS=off`.

## Alternatives considered

Keeping the conservative refusal leaves standalone incomplete. Allowing unrestricted gen_smtp negotiation violates the configured mechanism. Rewriting a dependency or relying on opaque socket records creates a larger, fragile maintenance boundary. The explicit session uses public socket functions and retains the pinned dependency.

## Consequences

The application owns a small authenticated SMTP protocol implementation. Local wire tests must remain green before changing it or the socket dependency. No SMTP authentication failure admits unauthenticated MAIL, and required TLS never falls back to plaintext. Lifecycle and producer ownership remain unchanged.

## Verification and references

Each of four mechanism tests verifies exact wire credentials, advertisement independence and rejected authentication. A verified TLS test exercises all mechanisms under implicit TLS and STARTTLS, including hostname rejection. A separate admission test preserves coexistence behavior. Every newly named test has RED, GREEN, isolated mutation failure and restored GREEN evidence in the fix-sa-smtp implementation report.

Code: `app-phoenix/lib/dawarich/mail/smtp_authentication.ex`, `smtp_transport.ex`, `smtp_config.ex`, `smtp.ex`. Tests: `smtp_policy_test.exs`, `smtp_tls_review_test.exs`. Related contract: [MAIL producer contracts](a12f3b-mail.md). Supersedes the transport limitation of AFFiNE ADR `uV80V1dHKCmjQqcbsHbjW`; its AUTH/TLS downgrade refusal remains mandatory. Cloud lifecycle is still refused until external L1 handoff.

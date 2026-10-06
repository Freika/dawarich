# Native admin actions

D01–D03 retain the existing self-hosted admin role, current-session, method, CSRF, origin, and form admission checks. Cloud job health keeps the existing operator role and Basic authorization on HTTP, plus the connected operator grant. Connected admin pages now revoke access after a password-salt change.

Existing native create/update/API-key/registration/instance/background-setting actions remain in place. Background POST creates native Immich, PhotoPrism, AirTrail, or TeslaMate commands only under their existing Oban owner keys. Their worker payloads retain the existing shapes; locale and time zone are recorded in command metadata. Unknown action names return a native error in standalone mode. Cloud permits only the four source-allowed integration names.

Reverse-geocoding actions enqueue a native Oban worker on the reverse-geocoding queue. It scans only the requesting user's points in pages of 1,000, publishes the existing leaf payload in chunks of 100, and uses the existing point claims. Publication and its accepted-job claim share a transaction, so retries cannot duplicate a committed batch. Continuations are native Oban jobs. Coexistence with a Sidekiq leaf owner hands back before acceptance.

Password reset uses the existing recovery lifecycle and sealed native mail worker. Token changes and enqueue share a transaction; a failed enqueue rolls back the token. The HTTP action uses the password-reset flash rather than the API-key flash. SMTP configuration and delivery remain the MAIL owner's responsibility.

Admin deletion calls `Auth.AccountDestroy.request_as_admin/3`, the minimum A11 capability added here. It checks the current self-hosted admin, locks the actor and target, reuses the family-owner guard and atomic mark/schedule primitive, and requires A11's `:enqueue_destroy` capability. A missing or failed capability returns native 503 in standalone mode without marking the user deleted; coexistence retains Rails fallback before acceptance. A11 must provide its actual native destruction enqueue function through `:account_destroy_context`; this package does not introduce a second destructive worker. Source permits deletion of the sole admin; last-admin protection remains on role/status updates only.

## HOT mount handoff

Import `DawarichWeb.AdminFormRoutes` and invoke `admin_form_routes()` after the existing `:admin_writes` pipeline is declared. It adds:

- `DELETE /settings/users/:id` → `AdminUserDestroy`, `AdminWritesGate.destroy?`.
- `POST /admin/settings/test_geocoding` → `AdminWrites.Settings`, action `:test_geocoding`, `AdminWritesGate.test_geocoding?`.

Keep the existing A10 admin routes and their order. Existing `POST /settings/users/:id` now recognizes a CSRF-validated `_method=delete` through the shared request parser and calls the same deletion seam. Existing background POST supports `job_name` from the form or source query string; PATCH and POST `_method=patch` remain settings updates. Standalone route ownership reaches native authorization/refusal handling; it does not bypass `eligible?/3` inside the action.

HOT must exercise these additions through the real Endpoint after mounting. This package tests actions directly with real encrypted sessions and CSRF and leaves shared router/slice/registry files untouched. The reverse-geocoding wrapper is directly enqueued, so it requires no new dispatcher entry.

## Verification and remaining integration

The package report contains source capture, named RED/GREEN/mutation, targeted security checks, compile/format, full seed-404, and secret-scan evidence. Controller integration owns HOT mounts, A11 deletion capability wiring, MAIL delivery configuration, and mandatory security review. Rare legacy envelope failures remain native errors under ruling 15; exact malformed-envelope parity is deferred under the controller's convention.

The provider-test adapter uses existing native geocoding Config/Search/Result. I01 owns shared provider-test integration; exact Turbo-stream output, safe error details, and bounded rate-budget parity remain follow-ups under ruling 15. The required full-suite gate also exposed an existing places CLI batch reread without ordering; its minimal fix preserves ascending user scheduling, verified after a deliberate row reorder.

## ADR: reuse native authentication owners for admin residual writes

Status: implemented, awaiting controller security review. Date: 2026-10-06.

Context: standalone admin forms still reached Rails for reset and deletion, despite native recovery and destruction primitives already owning these effects.

Decision: retain action admission and fresh admin checks, use the recovery owner for token/mail changes, and expose a narrow admin entry point on the destruction owner. Keep runtime absence of the destruction enqueue capability as a native failure before acceptance.

Alternatives considered: copying destruction/family guards into a new admin worker, or manufacturing the target user's password/confirmation to call the self-service path. Both would obscure the authorization boundary and duplicate owner behavior.

Consequences: admin and self-service deletion share their transaction and family guard. Controller integration must wire the A11 capability; admin code does not silently introduce a second deletion implementation. Named tests cover revocation, refusal, enqueue failure, and rollback; controller review remains mandatory for this security-sensitive package.

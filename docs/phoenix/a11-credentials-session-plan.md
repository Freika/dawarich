# A11 credentials and session slice

Status: bounded credentials handoff; public ownership remains inactive. 2026-10-01.
Canonical inventory: AFFiNE `ennu5GpmxllL93cPGtNQ2`, mirrored at
`superpowers/plans/2026-09-28-phoenix-a11-inventory.md` in the project plans.
Root integrates this documentation delta into the canonical inventory.

## Scope and ownership

Implement native email/password login, logout, remember-me issuance/restoration
and revocation, and legacy Rails session compatibility in the isolated A11 tree.
Own new auth modules, controllers, tests, synthetic fixtures and documentation.
Router/config/dependency edits are a separate integration delta. Existing session
reader, proxy, account schema and shared modules remain read-only dependencies.
Default ownership stays inactive until integration gates pass.

Registration, password recovery, unlock mail, OTP challenges, OAuth/OIDC, Apple,
mobile handoff and invitation/payment flows remain later A11 work. A credentials
slice does not complete A11. Defer special flows to Rails before native effects;
in particular never issue an authenticated session for an OTP-required account.

## Source-backed contract

Sources: Rails `Users::SessionsController`, `ApplicationController`, `User`,
Devise initializer and pinned Devise 5.0.4; native `Accounts`, `RailsAuth`,
`RailsSession`, `RailsCookies`, `RequireUser`; B1 auth specs and helpers read from
the authorized `~/port-work/e2e/auth/` source directory.

* Normalize email case and whitespace as configured by Devise. Verify existing
  BCrypt hashes; unknown email and wrong password use the same failure message.
* Honor soft deletion, lock state, ten failed attempts and one-hour unlock.
  Do not confuse account entitlement status with Devise authentication status.
  `paranoid = true` keeps credential failure generic for locked accounts too;
  `last_attempt_warning = true` does not override the paranoid failure branch.
* Honor OIDC-only configuration before credential authentication. Defer OTP,
  invitation, pending-payment and mobile flows before trackable/session effects.
  Also defer sessions carrying `pending_import_ticket`: Rails consumes the ticket
  in `PendingImportClaimable` after authentication, with claim-dependent flashes.
  Native login must not lose or duplicate this side effect.
* Renew the session and CSRF state on successful login. Preserve legitimate
  return-to behavior and update Devise trackable fields only for successful auth.
* Rails Warden serialization is `[[user_id], first_29_bytes_of_bcrypt_hash]`.
  `_dawarich_session` uses the existing authenticated encrypted cookie format.
* `remember_user_token` is purpose-bound and signed, with payload
  `[[user_id], bcrypt_prefix, generated_at]`; configured lifetime is fourteen days.
  Rails has `expire_all_remember_me_on_sign_out = true`.
* Logout is a DELETE action (`sign_out_via = :delete`); preserve the user-menu
  method override and CSRF admission, never create a GET logout mutation.
* B1 asserts valid login reaches `/map`, protected `/stats` works, generic failure
  remains at `/users/sign_in`, logout returns home, remember restores login after
  clearing session cookies, and replay of a captured remember cookie is refused
  after logout on another device.

The actual Rails oracle accepts replay of a captured stateless Warden session after logout, while rejecting the captured remember cookie. Root approved preserving this legacy limitation. No separate server-session architecture is introduced; logout revokes remembered credentials globally, not previously copied Warden sessions.

Pinned Devise source confirms the strict `generated_at > remember_created_at`
comparison and initializes `remember_created_at` only when absent. Payload
generation samples `Time.now` separately. Preserve this comparison and the
existing timestamp on repeated remember logins. Actual Rails fixtures and a Native→Rails Rack consumer now verify the signed and encrypted protocols. Sources:
https://github.com/heartcombo/devise/blob/v5.0.4/lib/devise/models/rememberable.rb
and https://github.com/heartcombo/devise/blob/v5.0.4/lib/devise/models/lockable.rb .
Lock expiry is also strict, and failure counting uses an atomic increment followed
by reload. Expired locks are cleared before password validity determines success.
Existing remember restoration is read-only (inventory ED058), and
locked-cookie cleanup has pending differences (ED059/ED060).

## Implementation and verification order

1. Pure issuer foundation: synthetic Rails cookie fixtures, signed purpose and
   expiry, Warden shape, session renewal and cookie flags; red test before code.
   Extend only auth-owned modules, without enabling routes.
2. After `DB_RESUME_ALLOWED`, capture bounded actual Rails outcomes for first
   remember creation/restoration, logout replay, lock/unlock boundaries, failure
   counters, CSRF and trackable effects. No external mail delivery.
3. Add native BCrypt verification as a separate dependency delta. Relevant
   primary references: https://github.com/riverrun/bcrypt_elixir and
   https://hexdocs.pm/bcrypt_elixir/Bcrypt.html . Use pinned dependency/lock data;
   test existing Rails hashes and an unknown-user timing work path.
4. Implement transactional credentials and remember state changes with own DB
   tests. Cover concurrent failed attempts/revocation and legacy credentials.
   Settle session revocation design from the captured Rails contract and report
   any required shared reader/proxy integration dependency explicitly.
5. Add auth controller/form and separate route/config ownership deltas. Run only
   the three relevant B1 suites against the own test stand, plus meaningful auth
   ExUnit gates, formatting and forced compile with warnings as errors.
6. Hand off owned/dependency SHA manifests, patch, exact gates, limitations and
   documentation delta. Do not commit, merge, push or activate production routes.

All production modules stay below 300 lines. Fixtures are synthetic. A11 resources
are remote `~/port-work/a11-auth-session-stack`, DB prefix
`dawarich_test_a11_auth_session`, Redis 7175 and proxy 3175. Never touch peer stands.
During Colima maintenance, do not start DB/Rails/browser/container gates. Pure
tests must bypass the project's `mix test` alias, which starts DB migrations.

## Verified behavior and remaining integration

The Colima maintenance pause ended with explicit `DB_RESUME_ALLOWED`. The own
stand uses Ruby 3.4.9, Elixir 1.18.3 and OTP 27; ordinary pools remain 2. HTTP uses
DBConnection.ConnectionPool rather than Sandbox: keep-alive processes otherwise
retain sandbox connections. Assets bypass the auth hook in the own wrapper.

Actual pinned Rails/Devise Rack requests characterize sixteen bounded scenarios.
The backup-code strategy runs before the password strategy: ordinary wrong
password and locked-password requests increment failed attempts twice; an
unlocked blank password increments once. Expired locks clear failed attempts and
unlock state before these checks. No new lock/unlock-mail implementation is
claimed: native credentials hand back before effects when an unlocked account's
effective failed-attempt count is >= 8. Expired locks have effective count 0.
The DB gate covers that handoff with no mutation, and two distinct PostgreSQL
backend PIDs prove concurrent rejected attempts retain all four increments.

Accepted remembered credentials persist a renewed Warden session, reset failed
attempts and update trackable once. Ordinary valid Warden fetches do not update
trackable or remember expiry. Logout clears remember_created_at under row lock.
A captured remembered credential is then rejected without auth effects.

Native→Rails consumption passed for three encrypted session shapes, signed
remember, real CSRF credential POST, Warden access, remembered access and logout
remember replay rejection. The Rack harness reloads routes before env_config;
otherwise Warden strategies are empty in runner context. CookieJar fixtures use
HTTP-unescaped values, unlike the actual wire cookie. Failed diagnostic runs are
retained; no production crypto change was inferred from harness failures.

New HTTP modules are auth-owned and unwired. AuthHandler is disabled by default
and requires an explicit boolean authoritative registration_enabled decision;
missing policy hands back before effects. Root must supply that decision from
its Rails-compatible settings/cache boundary, not substitute an env-only check.
Forms reuse existing Phoenix root/app layouts, navbar, footer, assets and locale
translations. Registration/reset/unlock links still target Rails. Configured
OIDC or Google OAuth, Cloud, mobile headers, invitation/pending-import sessions,
forwarded client-IP requests, JSON negotiation, query parameters, duplicate headers, method overrides on sign-in, ambiguous
credentials and unsupported body shapes hand back to Rails. Forwarded-IP
semantics remain a later source-backed integration task.

The auth body parser accepts only bounded forms; consumed bodies are retained
for Rails replay. It accepts the standard hidden remember=0 plus checked=1 pair
and rejects ambiguous repeated credentials. CSRF accepts actual Rails global or
per-form tokens plus the X-CSRF-Token header, with Origin checking. GET logout
is never owned. AuthCookie clears staged layout session changes so they cannot
overwrite freshly issued Warden state. It also updates the in-memory request cookie so layout changes staged after remember restoration merge into the renewed Warden session. Both callback orderings are tested. AuthRestore belongs after RailsAuth and
before layout/session staging on admitted native browser requests; its ownership
must remain disabled for Cloud and special flows.

The own support stand is an integration harness, not production routing: it
passes admitted auth actions to AuthHandler, restores browser remember state,
then replays the renewed session to Rails for protected pages. Root router,
Endpoint, shared Accounts/RailsSession and Mailers were not changed. The bcrypt
mix.exs/mix.lock delta is packaged separately. Root integration must preserve
HostAuthorization, ForceSSL, header/body negotiation and the existing strangler
ownership gate; do not use the test wrapper as a replacement production router.

The three existing B1 spec files remain byte-identical copies. Only copied helper
assertions were strengthened: native-owner headers for GET/POST login and logout,
HTTP success for protected pages, and native-restore header when no session cookie
preceded a remembered request. Every run is one worker with synthetic users in
the own database. Browser failures and corrected stand setup are recorded.

Final native gates: 19 pure/HTTP-boundary tests and 11 DB tests, all green; three B1 spec files pass 9/9 with native-owner/restore assertions. Forced compilation of 455 modules with warnings as errors and owned-file format checks pass. Exact SHAs and browser evidence are recorded in the sibling handoff report. This slice does not complete A11: registration, reset/unlock mail,
OTP challenges, OAuth/OIDC/Apple, invitations, pending import/mobile/payment
callbacks, Cloud throttling and shared integration/activation remain outside it.
Root owns the canonical AFFiNE documentation update from this scoped delta.

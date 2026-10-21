# Standalone authenticated pages

Native protected pages use `DawarichWeb.RailsAuth` and the shared
`AuthenticatedPageGate`/`RequireUser` path. In standalone mode, an active
five-minute OTP challenge prevents both Warden and remember-cookie identities
from entering protected pages or changing two-factor settings. An expired
challenge does not override an otherwise valid credential.

Successful full authentication clears `otp_user_id`, `otp_challenge_at`,
`otp_failed_attempts` and `otp_remember_me` through `SessionCookie` for credential,
provider, recovery, account-link sign-in and remember-restoration cookies.
Account-link completion that only links a provider does not complete login and
retains an existing OTP challenge. Coexistence retains its existing session and
identity behavior.

Two-factor management reuses the authenticated Rails identity, including a
valid remember cookie without a Warden session. The mutation closure rechecks
the password salt, deletion and lock state. CSRF, origin and strict write-form
validation still precede writes. Read queries accepted by the shared HTML-page
envelope, including `locale=de`, reach authentication and locale handling;
write queries remain rejected. HEAD follows GET admission and emits an empty
body, including authenticated management responses.

## Source difference

Rails permits an active challenge for actor A to remain after a full credential
login of actor B and then renders B's management page. The source stores the
challenge in `app/controllers/users/sessions_controller.rb:33`; Devise 5.0.4
`lib/devise/controllers/sign_in_out.rb:99` only expires `devise.*` keys.
The controller's F1 review correction explicitly requires clearing pending state
and refusing active challenges in standalone mode. This security correction is
recorded as ED-FIX-SA-PENDING in the
[expected-difference register](../../app-phoenix/parity/expected_diffs.md).

## Verification

`app-phoenix/test/dawarich_web/standalone_auth_findings_test.exs` reproduces F1
with actor A's current challenge and actor B's real login response cookie,
mixed Warden/remember sessions, remembered setup/verification/disable, both
roles, HEAD and German locale reads. It also checks expired challenges,
coexistence retention, link-only completion, salt revocation, lock refusal,
CSRF rejection and strict query writes. Each named regression has an independent
mutation recorded in the controller handoff report. Native Cloud lifecycle
refusal is unchanged.

AFFiNE synchronization belongs to the controller: the assigned A12f plan's
delegate rule prohibits mirroring this security-sensitive work to AFFiNE.

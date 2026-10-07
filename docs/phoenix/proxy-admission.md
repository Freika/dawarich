# Reverse proxy admission

Date: 2026-10-07. Controller task: fix-proxy-admission.

## Origin and retained protection

Commit `d94b1326f` introduced the forwarding-header refusal with the A11
credentials port. ED-335 records the deliberately unsupported forwarding
identity envelope: authentication and Devise Trackable could hand back to Rails
before any effect instead of choosing an unverified address. The restriction
was later reused by admin writes, which prevented a legitimate reverse proxy
from enabling registration.

`Admission.context/4` now also accepts a connection. It checks duplicate headers
before invoking the shared `RailsRemoteIp.ip/1`, refuses conflicting
XFF/Client-IP identities for trusted and untrusted peers, then runs every
existing context check. AdminWritesGate uses this connection form. The original header-list form stays conservative;
no other admission caller is widened.

The shared IP helper accepts XFF and Client-IP only when the socket peer is a
trusted proxy. All peers undergo Rails address validation and textual spoof
checks before identity selection. Untrusted peers use their socket address for nonconflicting
headers. Trusted chains retain rightmost non-proxy selection and configured
proxy replacement. Forwarded and X-Real-IP remain excluded from identity. Ingress must still sanitize client
identity headers: a trusted proxy passing a forged identity through unchanged
remains DRB-036, and this task does not close that defect.

This untrusted-peer rule intentionally improves Rails behavior, as specifically
required by the controller brief. ActionPack 8.1.3.1 RemoteIp's calculate_ip
(`lib/action_dispatch/middleware/remote_ip.rb:129–169`) considers supplied headers
before the untrusted socket address. Proposed expected-diff row for the matrix
owner: **direct untrusted-peer XFF/Client-IP impersonation is refused natively**.
No shared ED/DRB matrix row is assigned or edited by this task.

## Callers and write coverage

Admission.context callers besides AdminWritesGate are AuthHandler, AuthRestore,
AuthAccount.Http, AuthApiKeys.Http, AuthAccountLink.Http, AuthOtp.Http,
AuthTwoFactor.Http, AuthRecovery.Http, Auth.Recovery.Flow and TestEmailGate.
They retain their original header-list admission behavior. Native auth flows
that already use the shared helper inherit the corrected peer trust boundary.

AdminWritesGate is selected by A10Routes and AdminFormRoutes, called during
AdminWrites.Request.load/3 and refresh_actor/3, and reused by
IntegrationJobActions.enabled?/2 for legacy background settings. The fallback
module uses its context/auth options.

The proxied-write regression covers create, update, registration, instance
settings, background settings, API-key rotation, password reset, delete,
geocoding test and map-matching test. Registration executes the real HTTP
handler and proves the setting persists. Each shape also retains duplicate
header, spoofed trusted identity, missing session, invalid CSRF and foreign
origin refusal; admin-only shapes retain role refusal. A separate regression
uses each non-admin session’s valid per-form CSRF for all nine admin-only shapes.
Changing only the persisted admin flag admits the same request, proving role
enforcement independently of CSRF. Untrusted conflicting Client-IP/XFF also
refuses an otherwise valid registration form through both the shared helper
and the full request gate. The existing tests retain method, route, special-session, OIDC, Cloud and current-role checks.

## Regression evidence

- `proxied admin writes preserve CSRF origin session and role admission`:
  RED before implementation; GREEN; M-PROXY-GATE switches the gate back to the
  header-list form and fails admission; restored GREEN.
- `forged forwarding headers from an untrusted peer cannot change sign in identity`:
  RED persists the forged address; GREEN; M-IP-PEER removes the socket trust
  boundary and persists the forged address again; restored GREEN.

Production lifecycle/Cloud refusal files are outside this task and unchanged.

## Signed-in sign-in page

GET `/users/sign_in` with a live Warden user now answers Rails/Devise's 302
redirect and `alert: You are already signed in.` Pending-payment users first
redirect to `/trial/resume` and retain `user_return_to`. Other users consume a stored local `user_return_to`, otherwise
redirect to the absolute root URL. Live flash messages survive alongside the
new alert; messages listed in the prior flash discard set expire. The Warden
identity and CSRF token remain in the session, and no Trackable update occurs.
The same behavior applies to ordinary query-bearing browser GETs. Locked,
invalid, unsupported negotiation and POST envelopes retain their existing
admission behavior.

Source: `Users::SessionsController#new`,
`devise-5.0.4/app/controllers/devise_controller.rb:116–131`,
`devise-5.0.4/lib/devise/controllers/helpers.rb:217–218`,
`app/controllers/application_controller.rb:95–118`, and
`config/locales/devise.en.yml:10`. A targeted Rails request oracle records
status 302, location `http://www.example.com/`, and the exact alert above.

`signed in GET sign in redirects with the Devise already authenticated alert`
was RED before implementation, then GREEN. M-SIGNIN-OWNED restores the old
signed-out-only admission and fails the status assertion; restoration is GREEN.

Review follow-up adds four named regressions: untrusted conflicting headers,
pending-payment precedence, live flash/discard handling, and valid-CSRF role
refusal. Each was RED before its fix, GREEN, failed under one named mutation,
and GREEN after restoration. For the test-quality finding, RED reproduces the
prior admin-token/non-admin-session mismatch; M-ROLE removes the production
role check and fails the corrected regression. M-CONFLICT restores the early
untrusted-peer shortcut; M-PAYMENT removes pending-payment precedence;
M-FLASH replaces existing messages. A fresh Rails oracle confirms conflict
refusal, trial-resume precedence, stored-location consumption and live notices.
Review follow-up targeted gate: **49 tests / zero failures**. The full gate
also exposed an existing Trek test comparing Oban’s independent attempt and
reschedule clocks. It now asserts the worker’s exact 60-second snooze result
and retains scheduling/completion checks; a 59-second mutation fails it.
No worker behavior, timeout or retry policy changed. Final follow-up full
ExUnit seed 404: **9,505 tests / zero failures**, all three partitions exit 0
(2,725 / 3,311 / 3,469 tests). Warnings-as-errors compilation and whole-tree
formatting pass.

Initial implementation verification: targeted regressions **45 tests / zero
failures**; prescribed full ExUnit seed 404 **9,476 tests / zero failures**, all three partitions exit 0.
Forced compilation with warnings as errors, whole-tree formatting and feature
commit Gitleaks pass. Fresh-worktree JS dependencies were installed after the
first full gate reported only missing Tailwind and poster-renderer modules;
the affected four tests then passed before the successful full gate.

Shared decision counterpart:
[Dawarich — ADR-20261007-proxy-admission](https://app.affine.pro/workspace/c309ded7-e11e-4e72-ba6f-aec8a31a740b/onP9gbm-WRiqvxxYkkI8p).

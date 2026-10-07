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
before invoking the shared `RailsRemoteIp.ip/1`, refuses conflicting trusted
XFF/Client-IP identities, then runs every existing context check. AdminWritesGate
uses this connection form. The original header-list form stays conservative;
no other admission caller is widened.

The shared IP helper accepts XFF and Client-IP only when the socket peer is a
trusted proxy. Untrusted peers use their socket address regardless of those
headers. Trusted chains retain Rails address validation, rightmost non-proxy
selection, configured proxy replacement and textual spoof checks. Forwarded
and X-Real-IP remain excluded from identity. Ingress must still sanitize client
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
origin refusal; admin-only shapes retain role refusal. The existing tests
retain method, route, special-session, OIDC, Cloud and current-role checks.

## Regression evidence

- `proxied admin writes preserve CSRF origin session and role admission`:
  RED before implementation; GREEN; M-PROXY-GATE switches the gate back to the
  header-list form and fails admission; restored GREEN.
- `forged forwarding headers from an untrusted peer cannot change sign in identity`:
  RED persists the forged address; GREEN; M-IP-PEER removes the socket trust
  boundary and persists the forged address again; restored GREEN.

Production lifecycle/Cloud refusal files are outside this task and unchanged.

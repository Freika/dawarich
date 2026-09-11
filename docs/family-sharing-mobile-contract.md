# Family sharing mobile contract

## History consent and member indicators

`PATCH /api/v1/families/sharing` accepts `history_before_sharing` (boolean).
Explicit true plus enabled history opens the selected rolling window, independent
of the sharing start date. Missing consent retains the prior policy. Disabling
history or all sharing clears consent. All windows retain plan and one-year caps.

`GET /api/v1/families/mine` advertises `history_before_sharing_supported`;
own sharing includes `history_before_sharing`. Members include `share_history`,
`history_window`, `history_before_sharing` and `sharing_started_at`. These fields
explain the effective access without exposing additional location data.

## Native push configuration

Run migration `20260911160000` and set `FAMILY_PUSH_ENABLED=true` in both web and
Sidekiq environments. Only configured providers are advertised in `push_providers`
(`apns`, `fcm`); `push_notifications_enabled` is true when at least one is configured.
Configuration presence is checked, not credential validity. Restart both processes
after changing credentials. Delivery uses APNs and FCM directly, with no Expo Push
Service, Expo account or EAS project ID.

For **iOS**, configure these server secrets:

- `APNS_KEY_ID`: Apple push signing key ID.
- `APNS_TEAM_ID`: Apple Developer team ID.
- `APNS_PRIVATE_KEY`: complete PEM contents of the Apple `.p8` key, with real newlines.
- `APNS_TOPIC`: the signed app bundle identifier (`app.dawarich.Dawarich` for the official app).

Enable Push Notifications for the app identifier and regenerate its provisioning
profile with `aps-environment`. The mobile app reports its signed entitlement:
`production` for TestFlight/App Store, `development` for development builds. The
server selects the corresponding fixed Apple host. APNs requests use HTTP/2,
ES256 provider authentication and visible alert pushes. Provider JWTs stay in
process memory for at most 50 minutes.

For **Android**, set `FCM_SERVICE_ACCOUNT_JSON` to the complete Firebase service
account JSON as a server secret. Enable the Firebase Cloud Messaging API and grant
the service account permission to send messages for that project. The app's
`google-services.json` must belong to that same project and Android application ID;
it is supplied to the mobile release workflow as `GOOGLE_SERVICES_JSON`, never
committed. Only the public app configuration belongs in the mobile build; the
service account private key belongs exclusively on the server. FCM uses HTTP v1
with a short-lived OAuth2 token obtained from Google's fixed token endpoint.

Self-hosted/custom app operators need credentials and bundle/Firebase identifiers
for their own signed app; these secrets are not distributed with Dawarich.

## Registration and delivery

Authenticated `PUT /api/v1/push_subscriptions/:id` accepts:

```json
{
  "push_token": "native-device-token",
  "provider": "apns",
  "environment": "production",
  "context_id": "opaque-installation-session-context"
}
```

The example token is a placeholder. `id` is the installation ID; `provider` is
`apns` or `fcm`. APNs tokens must be hexadecimal and require an environment; FCM
registration omits `environment`. Tokens are unique within provider/environment.
Registration renews a 30-day lease and binds it to the current API key digest.
API key rotation invalidates delivery. DELETE is scoped to the authenticated
account. Account switching transfers the native token to the current account.

Request creation enqueues a job after commit. Before each device delivery the job
checks pending/unexpired status, both family memberships, entitlement, the target's
sharing state and registration validity. It sends a generic visible alert; payloads
contain request/user/installation IDs and an account-session context, no API keys,
email or coordinates. No arbitrary callback URL is accepted. APNs custom `body`
and FCM `data.body` preserve the native notification library's tap-routing contract.

Provider errors identifying an unregistered token remove that registration only
if it has not changed during delivery. Credential failures and transient failures
retain registrations. Retries are bounded to four attempts, at least one minute
apart, and stale requests are rechecked each time. APNs collapse IDs and FCM tags
reduce duplicate alerts for the same request. Provider acceptance is not proof
of device delivery; offline/OS/provider restrictions can delay or drop alerts.

The mobile app registers on foreground/settings changes, at most daily unless
settings or tokens change. It does not poll, wake GPS, or accept requests when a
push arrives. Notification taps open Family and reload pending requests. Permission
and account/server checks apply. Offline unregistration is best effort; a generic
alert can still arrive until unregister succeeds or the lease expires.

## Rollout and verification

Companion mobile PR: https://github.com/dawarich-app/multiplatform-app/pull/123

The mobile changes can ship first; history consent and native push remain
capability-gated until this server is deployed/configured. Existing history access
is not expanded without explicit consent. Backend-only deployment does not upgrade
older mobile clients' registration or notification handling.

Tests stub the Apple/Google HTTP boundaries and cover JWT signatures, payloads,
provider errors, consent, token ownership and revoked/stale requests. Before
production enablement, verify delivery on two physical devices in foreground,
background and after termination, notification taps, opt-out and account switching.
A simulator build or accepted provider response cannot establish device delivery.

References: [Apple APNs](https://developer.apple.com/documentation/usernotifications/establishing-a-connection-to-apns),
[FCM HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api),
[native notification payloads](https://docs.expo.dev/push-notifications/sending-notifications-custom/).

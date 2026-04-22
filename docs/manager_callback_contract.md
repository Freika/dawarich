# Manager → Dawarich Subscription Callback Contract

Dawarich exposes **one** billing-related inbound endpoint. Manager is the
source of truth for all subscription state. Dawarich stores a read projection
(`plan`, `status`, `active_until`, `subscription_source`) on the `users` table
so it can enforce plan gating locally.

## Endpoint

```
POST /api/v1/subscriptions/callback
```

## Authentication

Two layers — both required:

1. **Shared secret header**
   `X-Webhook-Secret: <ENV['SUBSCRIPTION_WEBHOOK_SECRET']>`
   Compared with `ActiveSupport::SecurityUtils.secure_compare`.
2. **Signed JWT** in the form body as `token`, signed with
   `ENV['JWT_SECRET_KEY']` (HS256). Both secrets must be provisioned in
   Dawarich and Manager out of band.

## Request body (form-encoded or JSON)

```
token=<jwt>
```

## JWT payload

```json
{
  "user_id": 123,
  "plan": "pro",
  "status": "active",
  "active_until": "2026-05-21T00:00:00Z",
  "subscription_source": "paddle",
  "event_id": "1b0d…-uuid",
  "event_timestamp_ms": 1714000000000,
  "exp": 1714000900
}
```

Field semantics:

| Field                 | Required | Allowed values                                      | Notes                                                                                    |
| --------------------- | -------- | --------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `user_id`             | yes      | integer                                             | Dawarich `users.id`. 404 if missing.                                                     |
| `status`              | yes      | `inactive`, `active`, `trial`, `pending_payment`    | Maps to `User#status` enum.                                                              |
| `active_until`        | yes      | ISO8601 timestamp                                   | Stored verbatim; nil allowed.                                                            |
| `plan`                | no       | `lite`, `pro`                                       | Unknown values are logged and ignored; other attrs still applied.                        |
| `subscription_source` | no       | `none`, `paddle`, `apple_iap`, `google_play`        | When absent, Dawarich leaves the existing value untouched.                               |
| `event_id`            | no (recommended) | string (uuid recommended)                  | Idempotency key; duplicate events are no-ops for 7 days.                                 |
| `event_timestamp_ms`  | no       | integer (ms)                                        | Informational; Dawarich does not arbitrate ordering — Manager must.                      |
| `exp`                 | yes      | Unix seconds                                        | Required by JWT library.                                                                 |

## Idempotency

When `event_id` is present, Dawarich caches it for 7 days under
`manager_callback:processed:<event_id>`. Replays return `200 OK` with
`{ "message": "Stale event" }` and do not mutate the user record.

If Manager omits `event_id`, **every request mutates state**. Manager SHOULD
include `event_id` on all production calls.

## Responses

| Status | Meaning                                                            |
| ------ | ------------------------------------------------------------------ |
| 200    | Update applied, or duplicate `event_id` silently ignored.          |
| 401    | Missing/invalid `X-Webhook-Secret` **or** JWT failed to decode.    |
| 422    | JWT decoded but payload was structurally invalid (ArgumentError).  |
| 503    | `SUBSCRIPTION_WEBHOOK_SECRET` env var is not configured in Dawarich. |

## Responsibilities that MOVED to Manager

- RevenueCat webhook receipt and signature verification.
- Apple App Store / Google Play store → `subscription_source` mapping.
- Product-id → plan catalog (e.g. `dawarich.pro.yearly` → `pro`).
- Paddle webhook receipt and processing.
- Trial-lifecycle emails (`trial_expires_soon`, `trial_expired`,
  `post_trial_reminder_*`, `trial_first_payment_soon`, `trial_converted`).
- Reverse-trial pending-payment lifecycle emails
  (`pending_payment_day_1/3/7`) and the 30-day purge decision.
- Determining `status` + `active_until` across every subscription event,
  including refunds, chargebacks, and out-of-order webhook retries.
- Arbitration between billing sources (Paddle vs IAP vs Google Play) —
  Dawarich no longer refuses updates based on existing source.
- Emitting the single normalized callback above on **any** change.

## Responsibilities that remain in Dawarich

- User authentication (Apple ID, Google, email+password, OTP/2FA) —
  unrelated to billing.
- Plan-gating enforcement: `PlanScopable`, `require_pro_api!`,
  `require_write_api!`, `reject_pending_payment!`.
- Reverse-trial UI surfaces (`trial/welcome`, `trial/resume` pages).
- Signup-variant bucketing, reported to Manager via the `variant:` claim on
  `generate_subscription_token` during checkout handoff.
- Product emails: `welcome`, `explore_features`, `archival_approaching`.

## Deprecated and removed in this extraction

- **RevenueCat path** on `POST /api/v1/subscriptions/callback` (previously
  dispatched via request-body inspection). Removed entirely.
- `REVENUECAT_WEBHOOK_SECRET` is no longer read.
- `Subscription::HandleRevenueCatWebhook` service — deleted.
- `Users::PendingPaymentReminderJob` and `Users::PendingPaymentPurgeJob`
  cron jobs — deleted. Manager now drives reminder emails and the 30-day
  purge via the callback above (e.g. by sending `status: "inactive"` once
  the purge window expires, after which Dawarich handles local cleanup).
- The 409 `Conflict` response for IAP-with-future-entitlement collisions —
  removed. Arbitration is now Manager's concern; Dawarich applies whatever
  Manager sends.
- `X-Webhook-Secret` is **required** on every call. There is no longer any
  unauthenticated webhook path into Dawarich.

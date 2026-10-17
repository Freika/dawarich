# Dawarich Cloud product analytics

**Status:** Draft PR; consent gate and production verification pending (2026-09-25).

The product analytics contract is defined in `/Users/frey/projects/multiplatform-app/docs/posthog-product-funnel-design.md`. Cloud owns account consent, a random PostHog distinct ID, and the event/property allowlist in `app/services/product_analytics.rb`. Mobile sends safe UI milestones to authenticated API endpoints. Rails emits signup, activation, and first confirmed mobile upload. Manager owns billing events and sends a signed callback; Cloud checks current consent before capture.

## Configuration

Use existing EU PostHog project `Dawarich` (ID `82529`). Cloud requires `PRODUCT_POSTHOG_API_KEY`, `PRODUCT_POSTHOG_PERSONAL_API_KEY`, and `PRODUCT_POSTHOG_PROJECT_ID`. The optional hosts default to `https://eu.i.posthog.com` for capture and `https://eu.posthog.com` for deletion. Keep the project key and personal key in deployment secrets. PostHog capture is disabled when any of the three required settings is absent or the instance is self-hosted. Withdrawal queues a person/event deletion job that retries until those settings work. A second deletion pass 24 hours later catches any pre-withdrawal SDK event that was still in transit.

Create the erasure personal API key with access limited to project `82529` and the `person:write` scope. The [PostHog persons bulk-delete API](https://posthog.com/docs/api/persons) requires that scope and queues deletion of events captured before the request. Grant no unrelated scopes. Confirm the key can invoke the deletion endpoint before enabling capture in production.

EU organization `ZeitFlow UG (haftungsbeschänkt)` currently allows one project and requires billing details to create another (checked 2026-09-24). The user chose to reuse project `82529` for the canonical product schema. Keep new dashboards scoped to canonical events, `schema_version=1`, and the migration start date. Historical events and identities remain in the project; do not join them to the new pseudonymous IDs.

Privacy settings applied to project `82529` on 2026-09-24: session replay, web autocapture, web-vitals autocapture, and exception autocapture disabled; discard client IP data enabled. These settings do not erase historical data or stop explicit pageviews sent by deployed legacy JavaScript. A deletion request was made, then canceled in the PostHog UI after the user chose reuse; the project is accessible again. The legacy deployment still needs a consent-aware cutover.

The obsolete Codex deletion-slot heartbeat `dawarich-posthog` was deleted after cancellation.

The following endpoints are added:

- `GET/PATCH /api/v1/users/me/analytics_consent` for the Cloud account choice, including pending-payment accounts.
- `POST /api/v1/users/me/analytics_events` for authenticated mobile UI events only.
- `PATCH /product_analytics_consent` and `POST /product_analytics_events` for session-based web choice and first observation.
- `POST /api/v1/subscriptions/analytics_events` for a Manager-signed billing event. It accepts the existing subscription webhook secret and a JWT with purpose `product_analytics_billing`.

The web application and map layouts load self-hosted Rybbit only after product analytics consent. Google Ads and Partnero additionally require the site's shared attribution consent cookie. The unused global Paddle script was removed from the Cloud layout; payment checkout remains in Manager. The PostHog Ruby final send hook strips request URL, IP, user agent, and any field outside the event allowlist. The mobile app must not contain PostHog credentials.

## Google Ads attribution

Set the **Final URL suffix** on each active Google Ads Search campaign to
`utm_source=google&utm_medium=cpc&utm_campaign={campaignid}`. Google replaces
`{campaignid}` with the numeric campaign ID. The marketing site keeps the
landing UTM values on links to `my.dawarich.app` only after site consent. Site
sets a first-party `dawarichAttributionConsent` cookie on `.dawarich.app` after
acceptance. Cloud ignores UTM and `_gl` without that cookie, and stores UTM on
the account only after a separate, unchecked-by-default product analytics checkbox at email signup.
OAuth signups currently have no account opt-in before callback, so they are
intentionally unattributed. For consenting users, `user_signed_up`, `trial_started`,
`paid_conversion`, `payment_charged`, and `payment_refunded` events include
`ad_source=google_ads` and, when valid, `ad_campaign_id`. Only a decimal campaign
ID of at most 20 digits is sent; free-form UTM text and Google click IDs are
never sent to PostHog. The campaign is the saved signup acquisition source,
not the latest touch before payment. Map campaign IDs to names using Google Ads.

PostHog shows the consenting cohort only. Use Manager's billing ledger for the
all-customer payment count and reconcile the two; do not treat PostHog as the
source of truth for ad spend or Google Ads bidding. This attribution does not
create a Google Ads conversion import. Deploy Cloud before Manager's signed
billing callbacks, then verify a consented signup, trial and first charge with
the same pseudonymous ID and campaign ID. Check a declined signup sends none.

## Verification before release

1. Run migrations in Cloud and Manager. Ensure their worker queues run.
2. Confirm no event for undecided/declined accounts or self-hosted instances. Grant consent, capture a safe event, and inspect the actual EU PostHog payload.
3. Withdraw consent and verify both immediate capture refusal and successful asynchronous deletion of the old distinct ID and its events.
   Withdrawal also clears campaign fields from the account and the Rybbit ID from browser storage.
4. Run the consent, activation, and billing callback request specs. Check signup, import completion, ten non-import points, and first nonzero mobile upload with iOS and Android headers.
5. Inspect `ProductAnalyticsErasureJob` retry failures and billing callback failures. Reconcile the consenting PostHog cohort against Manager's all-customer ledger without treating their denominators as identical.

Anonymous signup starts/failures, non-Google campaign attribution, additional data-quality and money views, and device validation remain open. The product funnel is not live until credentials, deletion path, and production event quality are verified. The existing project's historical data is still present.

The [Dawarich Cloud sales dashboard](https://eu.posthog.com/project/82529/dashboard/973682) now contains three draft 30-day funnels: [signup → first paid](https://eu.posthog.com/project/82529/insights/gdNqr3MS), [signup → paywall → purchase attempt → first paid](https://eu.posthog.com/project/82529/insights/uqapp4O8), and [trial → first paid](https://eu.posthog.com/project/82529/insights/k2i8j0d7). Each step filters `schema_version=1` and the reports begin 2026-09-24. They contain no canonical production events yet. Review cohort maturity and billing reconciliation before using conversion rates for decisions.

The same dashboard includes [trial, first-paid, expiry and refund counts](https://eu.posthog.com/project/82529/insights/dc90MCNx) and [weekly net receipts in EUR cents](https://eu.posthog.com/project/82529/insights/gNLCy1uJ). Net receipts subtract the sum of `payment_refunded.amount_eur_minor` from the sum of `payment_charged.amount_eur_minor` within the consented cohort. Reconcile this result with Manager's all-customer ledger.

The [signup → activation report](https://eu.posthog.com/project/82529/insights/4v6hKJU5) measures product value within 30 days, independently of whether payment happened before or after activation.

Project reuse decision: `/Users/frey/projects/multiplatform-app/docs/adr/0003-reuse-existing-eu-posthog-project.md`.

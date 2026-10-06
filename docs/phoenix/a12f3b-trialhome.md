# Native trial and home closure

Standalone mode (`DAWARICH_RAILS=off`) owns the root guest/member flow and trial
upgrade, resume and welcome requests. Existing rollback pins retain the Rails
path during coexistence. HTML GET and HEAD remain supported; unsupported formats
and malformed envelopes return native errors in standalone mode.

Home and trial flows preserve `dawarich_client` for iOS/Android and Cloud
`partnero_referral` (`aff` wins over `via`, truncated to 255 characters). The
existing account registration attribution owner consumes the referral; these
pages do not enqueue attribution or perform manager callbacks. Self-hosted home
uses native registration settings and redirects members to `/map/v2`.

Resume requires pending-payment status, independently of plan or trial expiry.
The page uses the existing reverse-trial checkout token. Missing or invalid
checkout configuration returns 503 without a redirect loop. Connected resume
sessions reload account status before handling events/messages and redirect to
root after entitlement changes. The auth owner retains identity verification.

Welcome verifies signature, purpose and expiry before claiming the existing
Postgres once-claim. Mobile/referral/legacy session markers no longer require
Rails in standalone mode. Consumed links cannot sign a guest in again. A failure
in sign-in or response construction after claiming returns a terminal native
500; the claim remains consumed and the handler does not replay through Rails.

## HOT route handoff

`DawarichWeb.TrialHomeRoutes.trial_home_routes/0` declares the existing four
routes. HOT must import the module and invoke the macro once after its existing
`:public_home`, `:trial_welcome`, `:rails_frame` and `:trial_resume` pipelines are
defined. Replace the corresponding four route scopes in `A10Routes`; do not
mount duplicates. Pipeline definitions remain HOT-owned. The current route
mounts already call the updated handlers, so the package tests exercise these
requests through the existing Endpoint without editing shared router files.

## Verification

`a12f3b_d04_test.exs` covers payment/plan/expiry states, HEAD, manager refusal and
fresh connected authorization. `a12f3b_d05_test.exs` covers standalone root and
welcome markers, signature/expiry/replay and deterministic response failure.
Each named case has its plan selector and a failing mutation. Source generators
characterize Rails behavior and verify byte-identical repeated captures. The
package gate is the existing full ExUnit seed-404 runner; integration seed 202
and HOT route-mount verification remain controller-owned.

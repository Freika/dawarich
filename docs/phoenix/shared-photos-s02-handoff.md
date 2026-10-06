# S02 public photo ownership and provider failures

Plan counterpart: `2026-10-06-phoenix-a12f-3b-producers-plan-a.md`, task S02.
Shared knowledge-base counterpart: AFFiNE document `sTHXI_y0g2E7VcjM02YGf`,
“Dawarich — Phoenix SHARES native management handoff”.

The A12f-2 photo search/ACL prerequisite is present. Standalone public photo
requests use that native provider search and thumbnail transport. SharedApi
filters geotagged results by the share owner's privacy zones before building
the thumbnail ACL or selecting the first 100 map markers. Rails accepts string
coordinates: privacy distance checks now use Rails-compatible float coercion,
while responses retain the original coordinate values.

Trip thumbnail authorization includes every visible photo in the trip window;
track and timeline authorization includes only the first 100 visible photos.
Live shares have no photo window and return an empty list. Resource lookups
remain scoped to the owner. A privacy-zone fingerprint change forces a new ACL
lookup, preventing the previous cached grant from bypassing an expanded zone.
Disabled photos, expired/revoked links, phrase refusal, private/unlocated assets,
foreign resources and out-of-window assets cannot trigger a thumbnail fetch.
Provider failures return an empty photo list or thumbnail 404. Each provider
request uses the share owner's configured credentials and PhotoPrism preview
token; another user's token never authorizes the fetch.

`a12f3b_s02_test.exs` covers real standalone GET requests, actual local providers,
source-recorded metadata responses, deterministic provider timeouts, native
controller HEAD behavior, ACL caps, credentials and unchanged outbox/blob
footprints. Both named tests failed before the coordinate fix. M-S02a removes
the photo toggle; M-S02b uses an owner-wide unfiltered list for thumbnails.
Both mutations must fail their selector and pass after manual restoration.

## HOT integration boundary

The existing Strangler gate rejects slice-owned HEAD requests before they reach
the shared controller. Direct controller tests prove photo HEAD semantics, but
mounted standalone photo HEAD requests still return 404 at this baseline.
Plan A assigns Strangler to HOT. The minimal proposed exception accepts
standalone HEAD only for `:api_shared` routes whose action is `:photos` or
`:thumbnail`, using the existing authorization pipeline and Plug.Head.
The controller must approve that exception or apply it during HOT integration.
Coexistence HEAD hand-back and other API slices must retain their current gates.

Mandatory privacy/security review follows this task. Full acceptance evidence
is recorded in the controller's S02 implementation report. This handoff does
not authorize a source cut, merge or deployment.

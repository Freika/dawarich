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
remain scoped to the owner. Every thumbnail request rereads the effective owner-scoped window and privacy
zones. The v3 ACL key binds owner, resource type/ID, effective window and sorted
zones. List and cold-thumbnail grants use the exact snapshot that selected
their IDs, preventing a concurrent expansion from poisoning a newer key.
Trip/track boundary changes and timeline date/timezone changes select a new
grant key, so warm IDs cannot bypass the current scope.
Disabled photos, expired/revoked links, phrase refusal, private/unlocated assets,
foreign resources and out-of-window assets cannot trigger a thumbnail fetch.
Provider failures return an empty photo list or thumbnail 404. Each provider
request uses the share owner's configured credentials and PhotoPrism preview
token; another user's token never authorizes the fetch.

`a12f3b_s02_test.exs` covers real standalone GET requests, actual local providers,
source-recorded metadata responses, deterministic provider timeouts, real
HTTP HEAD behavior, ACL caps, credentials and unchanged outbox/blob
footprints. Both named tests failed before the coordinate fix. M-S02a removes
the photo toggle; M-S02b uses an owner-wide unfiltered list for thumbnails.
Both mutations must fail their selector and pass after manual restoration.

## Minimum HEAD integration seam

The baseline Strangler gate rejected slice-owned HEAD requests before they
reached the shared controller. The brief's minimum-dependency-seam allowance
was used for a four-line exception in this otherwise HOT-owned module. It
accepts standalone HEAD only for `:api_shared` routes whose action is `:photos`
or `:thumbnail`, using the existing authorization pipeline and Plug.Head.
The actual socket assertions were RED before this seam and GREEN afterwards.
Removing the seam fails the HEAD assertion and restoring it passes again.
Coexistence HEAD hand-back and other API slices retain their current gates.
HOT must retain this exact scope when integrating the task; no route, source
pin or other shared-file change is required.

Mandatory privacy/security review follows this task. Full acceptance evidence
is recorded in the controller's S02 implementation report. This handoff does
not authorize a source cut, merge or deployment.

## Review privacy corrections

Review findings F1 and F2 are covered by named regressions S02F1 and S02F2.
S02F1 expands a zone through one-shot Ecto query telemetry between reading
its snapshot and writing the grant, through both list and cold-thumbnail
paths. Subsequent GET/HEAD must return 404 without a thumbnail fetch.
S02F2 warms a trip grant, moves both boundaries one day forward without
refreshing the list, and requires the same denial. Both were RED at 200/200
before the fix. M-S02F1 rereads zones when storing the key; M-S02F2 omits the
window from the key. Each mutation must fail its named regression and pass
again after restoration.

Rails request-local zone memoization prevents F1's poisoned-new-key race.
Rails retains F2's warm-window defect, reproduced through request GET/HEAD
and recorded as DRB-023 in `deferred-rails-bugs.md`. The review-fix brief
explicitly authorizes Phoenix to prioritize privacy over that source parity.
The decision is recorded in `shared-photo-grants-adr.md`.

# Rails bugs fixed in the Phoenix port

This register records the S02 privacy correction required by ruling 17.
The controller compiles other packages' reports for the release-wide changelog.
Repository source anchors identify the current implementation; runtime allocations
and private records are excluded.

## S02 shared trip thumbnails — DRB-023

Rails exposes a previously granted trip photo after a trip date edit excludes it:
warm GET and HEAD can still return 200 until the ten-minute grant expires.
Rails sources: `app/controllers/api/v1/shared/photos_controller.rb:42` (cached
ID authorization), `app/controllers/api/v1/shared/photos_controller.rb:63`
(window-blind key), and `app/controllers/api/v1/shared/photos_controller.rb:86`
(current trip window is read only on a cache miss).

Phoenix binds grants to the current owner, resource window and privacy zones
at `app-phoenix/lib/dawarich/shared_api/closure.ex:16` and
`app-phoenix/lib/dawarich/shared_api/photos.ex:32`. Standalone native requests
and coexistence proxy requests apply the same policy. The proxy guard in
`app-phoenix/lib/dawarich_web/shared_photo_guard.ex` denies excluded GET/HEAD
before Rails forwarding, including `api_shared` slice handoff; valid requests
retain Rails authorization and responses.

Named regressions in `app-phoenix/test/dawarich_web/a12f3b_s02_test.exs`:
S02F2, “warm thumbnail grants expire when the shared trip window excludes the
photo”; S02C1, “mounted coexistence GET and HEAD revoke excluded trip thumbnails
before Rails handoff”. Both require 404/404 without a provider thumbnail fetch.
S02C1V checks that missing native family-viewer recognition cannot bypass the
current scope on Rails handoff. S02C1O checks that native owner unavailability
cannot bypass that scope. S02C2 verifies the fixed/deferred register entries.

Rails remains unchanged. DRB-023 records its deferred repair; no additional
DRB or ED row was added. S02F1's poisoned-zone-key race is Phoenix-specific:
Rails memoizes zones within each request, so it is not a second Rails bug.
An in-flight request can finish using its already captured policy; these tests
establish denial for subsequent requests, not cancellation of in-flight responses.

CHANGELOG-ready: Fix shared trip thumbnails remaining accessible after trip
boundary changes. Phoenix now checks the current shared scope and privacy zones
before serving or forwarding GET/HEAD thumbnails in standalone and coexistence.

AFFiNE decision counterpart: `kcLrxKCKEyl9xcbirP9V9`.

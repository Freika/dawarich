# Rails bugs fixed in the Phoenix port

This register records corrections required by ruling 17.
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

## Photo provider client — redirect credential disclosure

Rails follows a provider redirect to another host while retaining the Immich
API key. A loopback probe against `Photos::Thumbnail` confirmed that the second
host receives the key. Rails source: `app/services/photos/thumbnail.rb:19`.

Phoenix uses one passive Mint transport for thumbnail, listing and enrichment
requests. It returns redirect statuses without following Location, matching the
Atlas client policy. Provider credentials stay on the configured host.
Phoenix source: `app-phoenix/lib/dawarich/photos/provider_http.ex:58`.
Named test: “photo provider redirects never forward credentials to another
host” in `app-phoenix/test/dawarich/photos/provider_client_test.exs`.
No ED/DRB row was added; the controller owns release-wide ledger consolidation.

CHANGELOG-ready: Prevent photo provider redirects from disclosing API keys to
another host.

## Photo provider client — unbounded response bodies

Rails buffers thumbnail responses without an explicit cap. A loopback probe
confirmed that `Photos::Thumbnail` accepts a 32 MiB plus one byte response.
Rails source: `app/services/photos/thumbnail.rb:19`.

Phoenix enforces the existing 32 MiB policy in the shared transport, checking
Content-Length before reading and counting streamed bytes for every status.
Overflow closes the socket before the provider finishes its response; exactly
32 MiB remains valid. Native and legacy thumbnails, provider listings and
enrichment responses all use this transport.
Phoenix sources: `app-phoenix/lib/dawarich/photos/provider_http.ex:91` and
`app-phoenix/lib/dawarich/photos/provider_http.ex:121`.
Named test: “every photo response is capped during streaming before the provider
finishes” in `app-phoenix/test/dawarich/photos/provider_client_test.exs`.
No ED/DRB row was added; the controller owns release-wide ledger consolidation.

CHANGELOG-ready: Bound photo provider responses to 32 MiB and cancel oversized
downloads while streaming, including error responses.

## Photo provider client — credential-bearing enrichment errors

Rails copies the upstream HTTP reason phrase into enrichment error bodies.
An upstream that echoes its API key in that phrase exposes the key in the API
response. A loopback probe confirmed this behavior.
Rails source: `app/services/immich/enrich_photos.rb:67`.

Phoenix derives the message from a trusted status mapping. Upstream reason
phrases, response bodies and transport details are never interpolated into
enrichment errors. Unknown statuses have an empty trusted description.
Phoenix source: `app-phoenix/lib/dawarich/photos/enrichment.ex:169`.
Named test: “enrichment errors contain only trusted status text when upstream
echoes credentials” in `app-phoenix/test/dawarich/photos/provider_client_test.exs`.
No ED/DRB row was added; the controller owns release-wide ledger consolidation.

CHANGELOG-ready: Sanitize photo enrichment errors so upstream diagnostics cannot
expose provider credentials.

## Photo provider client — malformed base URLs fetch unrelated resources

Rails appends asset paths to unchecked provider URLs. When a base URL contains
a query, the asset path becomes part of the query and Rails can accept the
provider root response as a thumbnail. A loopback probe confirmed this behavior.
Rails source: `app/services/photos/thumbnail.rb:50`.

Phoenix validates configured URLs before appending internal resource paths.
The shared validator preserves the existing thumbnail policy: HTTP(S), valid
host and port, safe base path, and no userinfo, query or fragment. Thumbnail,
listing and enrichment clients share that validator.
Phoenix sources: `app-phoenix/lib/dawarich/photos/provider_http.ex:11` and
`app-phoenix/lib/dawarich/photos/provider_http.ex:33`.
Named test: “photo clients validate configured base URLs before appending
resource paths” in `app-phoenix/test/dawarich/photos/provider_client_test.exs`.
No ED/DRB row was added; the controller owns release-wide ledger consolidation.

CHANGELOG-ready: Reject malformed photo provider base URLs before fetching
thumbnails, listings or updating enrichment data.

AFFiNE decision counterpart for these four photo fixes: `5-hALFzd96DSlwiLB8lt5`.

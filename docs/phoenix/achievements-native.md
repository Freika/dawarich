# Native achievement journeys

Phoenix owns achievement pages, unlock requests, sharing toggles and public cards through
`DawarichWeb.AchievementRoutes.achievement_routes/0`. The map's
`POST /achievements/unlocks/next` uses the native deck in standalone mode.

## Integration handoff

HOT must import `DawarichWeb.AchievementImageRoutes` and call
`achievement_image_routes()` in the main router. This adds the dedicated
`:achievement_image` pipeline and `GET /shared/achievements/:uuid/og.png`.
HEAD follows the existing Strangler/Plug.Head path. The image route has
`rails_key: "achievements"` so the coexistence route pin still applies. It must
use the image pipeline, which accepts PNG requests rather than the HTML public
page gate. The route macro is exercised through a test router; the final main
router mount and endpoint acceptance belong to HOT.

No registry changes are required. Existing achievement command/cron entries
already reference the native bulk and check workers.

## Behavior and boundaries

- Unlock transport and CSRF checks precede deck mutation. Requests reauthenticate
  from the cookie immediately before effects; deletion, lock and password
  revocation invalidate an admitted request. LiveView parameter handling also
  reloads and checks the actor. Standalone action refusals return native 401 or
  422 responses. Coexistence keeps pre-effect hand-back and explicit route pins.
- Standalone achievement pages resolve flat-country and hidden-tier redirects
  and unknown definitions natively. The page gate checks current authentication
  rather than a cached connection actor.
- Sharing retains one UUID across disable/re-enable. Public HTML and embed reads
  always check sharing and owner existence. An owner's requested locale is
  persisted by the existing locale plug and used in the returned card. Other
  viewers use the owner's locale. Embeds retain `frame-ancestors *`, and HEAD
  returns no body. A response failure after a sharing save is terminal and cannot
  replay the toggle to Rails.
- Public OG images check sharing and owner existence before computation-cache
  lookup. The one-hour cache includes the carrier, owner, definition, owner
  locale, timezone and exploration-state digest. HTTP responses remain
  `private, no-store`, including missing or disabled shares. Images are inline
  PNGs at 1200×630. Rendering uses the existing `rsvg-convert` executable with a
  native EEx SVG template, a ten-second deadline and temporary-file cleanup.
  There is no Ruby rendering call. Unsupported state/envelopes and rendering
  failures produce terminal native errors.
- Standalone bulk checks publish native Oban leaves even when a retained
  achievement-check owner row names Sidekiq. Coexistence retains ownership-based
  publication. Existing deterministic child IDs, stale filtering and batching
  remain in use; the obsolete `force` option does not change check behavior.
- CheckWorker runs calculation, progress, awards, unlocks and notifications in
  one database transaction. A notification failure rolls back the check, and a
  later retry converges without duplicate unlocks or notices. Direct Checker
  calls retain their existing interface.

## Verification

The task tests are `a12f3b_a01_test.exs` through `a12f3b_a04_test.exs` under
`app-phoenix/test/dawarich_web`. Each new named case was observed RED, then GREEN,
then failed its specified mutation and passed after restoration. A02b reuses the
existing sharing response-failure test and extends its UUID/state assertions;
it was already GREEN on the baseline and is not claimed as new TDD.

Retained Rails generators cover CSRF refusal without claims, public PNG locale
changes and deterministic achievement-check fixtures. Record with
`WRITE_PHOENIX_FIXTURES=1` and compare repeated captures. Test database and Redis
configuration comes from the environment.

Shared knowledge base counterpart: `Dawarich — Native achievement journeys
(A12f-3b A01–A04)` in AFFiNE. The implementation report records exact execution
results and the controller's remaining route mount.

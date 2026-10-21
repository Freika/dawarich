# A10c achievement actions and public cards

A10c extends the original achievement read boundary (ED-295–299) with sharing toggles, durable unlock-deck actions and public achievement HTML. Rails controllers, services, views and specs remain the oracle and rollback implementation through A12. This does not complete A10 or retire Rails.

## Ownership and rollback

| Route | Native boundary | Rollback key |
|---|---|---|
| `PATCH /achievements/:key/toggle_sharing` | Signed-in supported JSON/form requests for a registry key | `achievements` |
| `POST /achievements/:key/toggle_sharing` | URL-encoded form with `_method=patch` | `achievements` |
| `POST /achievements/unlocks/next` | Signed-in supported JSON/form claim/resume | `achievements` |
| `POST /achievements/unlocks/:id/seen` | Signed-in supported JSON/form acknowledgment | `achievements` |
| `POST /achievements/unlocks/dismiss` | Signed-in supported JSON/form bounded dismissal | `achievements` |
| `GET/HEAD /shared/achievements/:uuid` | Supported public document; `embed=1` selects embed | Either `shared` or `achievements` |
| `GET/HEAD /shared/achievements/:uuid/og.png` | Rails OG converter | Rails retained |

Set `DAWARICH_RAILS_ROUTES=achievements` to return achievement pages, these actions and public cards to Rails. Add `shared` to return public cards independently. Preserve other configured rollback keys.

Actions require fresh Rails session identity and a valid Rails CSRF token. The unchanged Stimulus client sends JSON with `X-CSRF-Token`; HTML forms use their authenticity token. Requests need a single supported content type and content length, at most 65,536 body bytes, valid UTF-8, unique scalar keys and an admitted locale. Unknown/nested/duplicate fields, duplicate headers, method overrides outside the sharing form, unusual auth/session markers and unsupported response formats hand back before effects. Action fields are `enabled`, `claim_token`/`batch_end_id`, `claim_token`, and `batch_end_id`, respectively; query parameters allow only `locale`. Form common fields are `authenticity_token`, `_method` and `locale`.

Settings require a supported timezone. Exploration state requires map-shaped `earned`/`celebrated`, string earned keys and supported ISO dates/timestamps. ED-297–299 retain their existing date and silhouette boundaries. Public reads accept only `locale` and `embed` query keys, require a representable session, and use the live owner's settings and exploration state. An owner requesting a different saved locale hands back before locale/session effects. Admission finishes before native locale/cookie writes, claims or carrier mutations; subsequent failures are terminal and never replay a committed action to Rails.

## Durable and visible contracts

Sharing inserts/locks only the owner's carrier, retains its UUID and state, and uses Rails boolean semantics for supported input. Absent `enabled` toggles; nil/empty input is retained on Rails. JSON returns enabled/UUID/public URL; HTML preserves the captured redirect contract.

Deck claims serialize on the user row and sample the clock after acquiring that lock. A pending lease is active through 45 seconds inclusively across every pending event before batch filtering. Resume refreshes the same token; new claims fix the maximum pending ID and select the lowest pending ID within it. Remaining includes the displayed card. Tokens are 32 lowercase hexadecimal characters. Seen/dismiss changes leave `updated_at` untouched, scope the owner, and do not consume future or foreign events. An already-seen own acknowledgment accepts another nonblank token.

Next checks pending state first, reads exploration state once and attempts at most ten presenters, acknowledging invisible cards between attempts. Busy returns 409 with `retry_after: 2`; empty/exhausted returns 204. Seen and dismiss positive IDs use canonical decimal syntax bounded by signed bigint; invalid IDs or blank acknowledgment tokens return 400, conflicting claims 409, and successful acknowledgments/dismissals 204.

Reveal tests compare normalized native HTML, Stimulus actions and texture paths with actual Rails partial captures for en/de/es/fr/pl/ca/zh at counts 1, 2 and 11. Expected labels never come from native translation code. A named mutation selecting the Polish singular remaining label at count 11 fails this comparison; restoring it passes. The generator runs twice directly and the ordinary fixture directory is byte-identical.

Public lookup requires sharing enabled, a live owner and a registry definition. Owner locale overrides viewer locale. Rendering exposes one summary card without application navbar, unlock host or private account/session payload. Embeds omit the public header/footer while preserving metadata/assets. Public HTML, including not-found redirects, removes X-Frame-Options and sets CSP `frame-ancestors *`; not-found redirects root with the captured localized flash. HEAD retains headers and suppresses the body. Preview metadata keeps the existing Rails OG URL.

## Retained ownership

| Surface | Owner/follow-up |
|---|---|
| OG PNG and `rsvg-convert` | Rails; later bounded achievement-image lane |
| Admin user deletion | Rails; A10b ruling retained until an A11 synchronous producer exists |
| Settings user-data export/import | Rails; A7 export/restore lane, including Cloud/non-admin semantics |
| Plain background-job producer POST | Rails `EnqueueBackgroundJob`; existing A7/A12 producers; A10b supported PATCH settings remains native |
| Geocoding provider test | Rails; separate provider/network/Turbo contract lane |
| Sidekiq/Flipper mounts | Rails until A12 retirement |
| Award execution, debounce and backfill | Existing worker/coexistence owners; A10c only reads durable unlock events |

## Verification and deferred work

Source generators and focused tests cover carrier/deck interoperability in both directions, owner isolation, lease/batch timing, transport/CSRF admission, locale-before-effect ordering and dual public rollback. Branch merge gates use the existing resync script's seed 404 and seedrun's seed 202 only, plus RuboCop `--cache false` and branch-history/changed-file gitleaks. Final seeds 101/303 are skipped by the controller's 2026-10-04 branch rule; the controller runs a third seed on the integration head.

Actual commands, failures, mutation, byte comparison, gate summaries and commits are recorded in `SP/orch/out/finish-a10c.report.md`. D1 browser/stand/image acceptance is deferred to the controller mini lane. This task uses no SSH, Docker, GitHub or AFFiNE writes; the latter is prohibited for this security-sensitive scope.

# Native milestone 4 sharing context

`Dawarich.Sharing` consumes the X1 sanitized `Accounts.Scope`/`Accounts.Principal` identity. It refreshes the original session version and current actor before every read and repeats admission after locking the actor for commands. HTTP/session adapters must retain the original principal rather than rebasing it onto a freshly loaded actor.

`page(scope, resource, params, opts)` and `change(scope, resource, action, attrs, opts)` accept closed resource maps. Every map contains `type` and `owner_id`; the owner must equal the current actor. Extra fields are rejected. Types and additional fields:

| Type | Fields | Commands |
| --- | --- | --- |
| `:hub` | none | read only |
| `:live`, `:timeline` | none | create, regenerate, regenerate_phrase, revoke, destroy |
| `:trip`, `:track` | positive integer `id` | same link commands |
| `:shared` | canonical UUID `id` | revoke |
| `:month` | integer `year`, `month` | update |
| `:digest` | integer `year` | update |
| `:achievement` | registered `key` | update |

Resource reads also query current ownership. Report reads/writes check active access, including strict equality at expiry; month sharing checks current Cloud entitlement. Link commands reuse the existing parameter/date/audience/setting validation and compatibility effects. Invalid active live replacement preserves the recorded rollback plus compatibility revoked events; it does not produce a successful native invalidation. Database/enqueue failures roll back the command transaction.

Page and result DTOs omit `magic_phrase`, actor credentials and raw write attributes. Validation returns localized errors without submitted phrases. `reveal(scope, resource, :phrase | :url, opts)` is an owner-checked HTTP adapter seam for an owned `:shared` resource; its transient return must never be assigned to LiveView state or sent through socket messages. The HTTP adapter owns CSRF, no-store headers and hook cleanup. Raw phrases remain write-only socket payloads; the native submission boundary never retains or renders them.

Successful commands enqueue durable ID-only invalidation with `event_id`, `user_id` and affected-owner `public_ids` in the command transaction. The worker publishes `{:domain_changed, user_id, :sharing}` to the authenticated owner topic and `{:share_changed, public_id, version}` to public topics. Delivery runs outside the transaction and retries converge through `AfterCommit.once`. Consumers must re-admit before querying/rendering; neither a subscription nor a version is permission.

`version(id)` is an opaque digest of the current persisted link state, including phrase, settings, expiry and revocation. It changes on phrase rotation even when timestamps coincide; URL rotation removes the old version. It contains no phrase or credential. Public admission still independently checks current owner, resource and family audience; connected public bootstrap and timer handling belong to C8.

Existing independently consumed HTTP/API protocols are retained. C6/C7 and X2 integrate native controls and any preserved HTTP write adapters with this context. This domain milestone does not claim native manager/public browser completion.

## Native owner manager

The existing hub/live/trip/track/timeline manager GET URLs mount a dedicated native session. The actor's original Principal version is checked on mount and refreshed before params, events, info and async callbacks. Scoped resource reads refuse foreign/missing targets to a safe map destination; invalid form values and localized notices remain in place. A native-ui route marker prevents legacy feature hand-back keys from bypassing migrated manager admission. Ordinary links from map/trip/track hosts and studio links leave the manager without a frame request.

Hub tabs are query patches. The empty shared-list fallback uses the same live resource for both its displayed form and commands. Confirmation consumes its resource/action before dispatch; cancellation, Escape and teardown have no effect and return focus. Creation retains only bounded scalar non-secret fields and closed boolean settings. Submitted phrases and malformed nested attributes never enter assigns. DTOs include only a protection boolean, not the phrase.

Fresh-session, same-origin, CSRF-checked GET `/native/sharing/phrase` supplies the legacy generated default into transient input DOM. GET `/native/sharing/:id/:field` (`phrase` or `url`) resolves an owned link and returns transient plain text. Both use no-store. Hooks abort and version pending work; failed/successful submit, patch, disconnect and destruction erase the input/reveal status and cannot restore a late phrase. Clipboard denial is visible. Public reader admission remains separate.

Measured domain reads including current identity: hub three queries, live two, trip three. The fixture corpus retains all 505 management and 21 track/timeline vectors, comparing successful native read DTO identity/settings and retaining independent write/status/effect/cookie coverage. Native manager behavior and hook tests replace modal/frame assertions. German 390-pixel and actual keyboard/host navigation E2E specs are prepared for controller stage acceptance; no implementation-time browser result is claimed.

## Native report controls

Month, digest and achievement hosts enter the native manager by ordinary links. Card previews remain deferred but cannot create a share through the old modal; keyed leaf cards have a manager link. Return links are derived solely from the validated resource, ignoring supplied return URLs. Monthly Cloud upgrade copy/link remains on its host; scoped reads/writes still refuse inadequate current entitlement.

Native report submit delegates enabled and expiration casts to the existing scoped domain operation; UUID stability, disable visibility and 1/12/24-hour/week/month presets remain unchanged. Public report/achievement HTTP contracts remain separate. Host map/chart/preview/delete behavior stays in its existing tests. German narrow-screen and keyboard browser acceptance remains controller-owned.

## Native public admission

HTTP `/s/:id` and scalar form unlock stay at their existing URLs. Unsupported formats, body shapes and client/method hints refuse locally before view count or limiter mutation. Wrong phrase, Rack-compatible counters and cookie/token purposes/attributes remain. Rails explicitly exempts public show/unlock from CSRF verification; Phoenix preserves the exemption and still renders the session-derived form/meta tokens. Native document loads the native bundle, retaining localized status/title/body semantics.

A separate read-only embedded LiveView receives a signed bootstrap only after HTTP admission. TTL is at most 30 minutes and no later than the link, authenticated Rails session cookie or unlock cookie expiry. It binds an encrypted Phoenix browser-session digest and original viewer identity. Socket assigns contain only a sanitized principal/link, version fingerprint and absolute deadline; no phrase, credential, raw bootstrap or cookie. Subscriptions precede fresh snapshots; every delivery, event and reconnect repeats admission. Unknown events cannot write or count views. Session signout and a replaced versioned nearest-deadline timer clear content. Locked public owners remain readable; deleted owners do not.

The 64-page corpus keeps every status/header/token/cookie/view-count vector, replacing old body/importmap bytes with localized headings and native graph assertions. Native public map/gallery rendering is implemented as C9. Stage acceptance owns browser measurements.


## Native public snapshots and browser resources

`Public.read` loads privacy-filtered latest/route/photo snapshots, then repeats current link admission and a stable privacy-zone fingerprint check before publishing. A deterministic query synchronization test covers revocation and privacy changes during the read. Live latest locations have an additional nearest stale-point deadline; an old marker disappears without another point publication. Committed point batches and place geometry/tag/privacy-radius changes enqueue transactional ID-only share invalidations, retaining duplicate delivery fences and rollback behavior.

The read-only public hook loads the vendored MapLibre module/styles only for a nonempty map. Route segmentation retains existing time/distance gaps, date-line interpolation and trip day colors. Authorized thumbnails supply photo markers and lazy day galleries. Native localized trip replay retains day, time scrubber, speed, follow and point controls; its timer and marker are destroyed with the map. Optional route/stats/days/description/photos and missing-resource states remain independently controlled. Supported descriptions use the existing sanitizer.

Every replacement/refusal/disconnect aborts pending requests and images, increments a generation, destroys maps/workers/markers/replay timers, clears gallery data and prevents old style callbacks from replacing newer routes. Destruction removes all LiveView and DOM listeners. No ActionCable, Stimulus or Turbo module enters the native loaded graph. Native track pages additionally honor a disabled route setting (FRB-NATIVE-M4-TRACK-ROUTE / ED-NATIVE-M4-TRACK-ROUTE). Browser/German 390-pixel/keyboard checks are prepared for controller stage acceptance, not claimed as executed.

## Unlock snapshot binding (review round 1)

Public bootstrap grants retain an opaque phrase digest derived from the exact link snapshot whose HTTP cookie was accepted. Fresh admission compares this digest with the current active link alongside its revocation version and audience. Adding or rotating protection between the HTTP check and issuance refuses the grant, rather than promoting an old proof to the new credential version. Raw phrases remain outside native state.

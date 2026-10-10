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

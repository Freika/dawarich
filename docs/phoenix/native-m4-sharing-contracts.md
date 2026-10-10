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

Page and result DTOs omit `magic_phrase`, actor credentials and raw write attributes. Validation returns localized errors without submitted phrases. `reveal(scope, resource, :phrase | :url, opts)` is an owner-checked HTTP adapter seam for an owned `:shared` resource; its transient return must never be assigned to LiveView state or sent through socket messages. The HTTP adapter owns CSRF, no-store headers and hook cleanup. Raw phrases remain write-only socket payloads until the native submission boundary is implemented in C6.

Successful commands enqueue durable ID-only invalidation with `event_id`, `user_id` and affected-owner `public_ids` in the command transaction. The worker publishes `{:domain_changed, user_id, :sharing}` to the authenticated owner topic and `{:share_changed, public_id, version}` to public topics. Delivery runs outside the transaction and retries converge through `AfterCommit.once`. Consumers must re-admit before querying/rendering; neither a subscription nor a version is permission.

`version(id)` is an opaque digest of the current persisted link state, including phrase, settings, expiry and revocation. It changes on phrase rotation even when timestamps coincide; URL rotation removes the old version. It contains no phrase or credential. Public admission still independently checks current owner, resource and family audience; connected public bootstrap and timer handling belong to C8.

Existing independently consumed HTTP/API protocols are retained. C6/C7 and X2 integrate native controls and any preserved HTTP write adapters with this context. This domain milestone does not claim native manager/public browser completion.

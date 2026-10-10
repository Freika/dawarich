# Native family domain contract

`Dawarich.Families.page/3`, `locations/2`, `history/3` and `subscribe/2` take an `Accounts.Scope`. Every read reloads the actor and compares the original session identity before reading current membership and entitlement. Invalid input, missing targets, stale sessions, inaccessible families and expired access return typed errors; native callers never receive a Rails hand-back sentinel.

Page DTOs preserve the existing owner/member/create/upgrade/lapsed/request branches, dates, ordering and invitation metadata, but omit invitation tokens. Tokens must be revealed through authenticated HTTP into transient browser DOM. Location/history reads reuse the existing consent, history window, viewer exclusion and strict expiry rules. A subscription grants no continuing permission: consumers must call the scoped read again before delivery.

Family invalidations use an owner topic and `{:domain_changed, user_id, kind}` with a closed kind. The event contains no location, email, settings or credentials. Scoped commands enqueue durable Oban invalidation intents in the same transaction as family effects. Recipients include members before and after the command, so removed members still receive an invalidation. Replay is idempotent and delivery rechecks permission in the consumer.

Native scopes use X1’s `Accounts.Principal`: an immutable session digest with a sanitized user projection. Family reads compare that original digest with the freshly loaded database actor. Full user structs never belong in native socket assigns. Internal repository arguments support deterministic tests against real independent transactions; browser input cannot select a repository.

Verification: `families_scope_test.exs` has six read/subscription/principal regressions, each checked with RED, GREEN, a discriminating mutation and restored GREEN. The consent equality, family/history and API golden corpora remain unchanged. Synthetic two-member domain reads observed 10 queries for show, 5 for invitations, 2 for new and 9 for locations. These include one fresh actor read; location admission adds one current family/owner read. These are domain measurements, not LiveView mount budgets.

The command interface covers create/update/delete, invitation create/cancel/HTTP acceptance, member removal/leave, location requests/responses and sharing consent. Commands lock the current family, affected users and memberships, then repeat admission against the original scope. Request targets are checked under their row lock. Validation retains safe field values; invitation capabilities remain transient. Public invitation landing uses the native HTTP shell and ordinary CSRF forms. Existing HTTP acceptance status/session semantics remain.

Authorization clocks advance while commands wait on locks. Request responses decide expiry and write their timestamps using the post-row-lock clock. Invitation acceptance checks expiry after the invitation lock and again after the family and owner locks, before membership creation; Cloud access uses the same fresh decision instant. An injected clock preserves deterministic equality-boundary tests. API effect fixtures retain their exact rows while checking and normalizing only the observed decision timestamp precision.

Cloud invitation capacity is checked while holding the family lock, preventing two pending invitations from consuming one remaining slot. Rails checks capacity before its transaction (`app/services/families/invite.rb:19,53`); this race fix requires the controller’s FRB/ED/changelog registration. No Rails production source is modified.

Successful scoped commands also persist ID-only scheduled invalidation at finite consent, request/invitation expiry and effective Cloud family access boundaries. These jobs are committed/rolled back with their command; old scheduled invalidations cannot grant permission and consumers must always refresh admission. API/housekeeping producer integration and connected versioned timers are completed in C4.

Connected snapshots carry the deadline from their own admitted context. In Cloud, inherited owner access and the viewing member's personal Family subscription are alternative grants; access ends after the last active grant expires. Consent, request and invitation deadlines can require an earlier refresh. Show and invitation pages schedule that carried boundary without a separate deadline read.

## Native family controls

Family page routes share a dedicated native session. Original session identity and
current membership, owner entitlement and request target are admitted before
params, commands, messages and async results. Refusal erases the snapshot and uses
an independent safe destination. Upgrade links and invitation capability reveal
remain fresh, scoped HTTP adapters; capabilities are absent from LiveView state.

Forms dispatch scoped commands and render validation in place. Confirmation is a
server-held action/id pair, consumed before dispatch; cancellation consumes no
command. Clipboard responses are no-store, CSRF checked and transient; hook patch,
disconnect and destruction abort requests and discard late responses. Consent
fields preserve duration, history window and prior-history independence and the
existing disabling reset. Successful consent refreshes the native indicator and
localized notice.

The family GET corpus retains all 294 role, locale, access and expiry fixtures.
Native cases compare scoped snapshots, titles and visible input values instead of
Rails DOM/controller attributes. HTTP invitation status, token, CSRF and action
vectors remain. Native action successors live in `family_native_events_test.exs`;
legacy client hints have no family write effect. Independent invitation and JSON
client forwarding remains characterized separately. Native family HTTP write
route retirement belongs to controller integration.

Keyboard confirmation and German 390-pixel checks are prepared in the E2E native
controls spec. They are deferred to stage acceptance under the controller decision;
targeted ExUnit and Node evidence is not a browser acceptance claim.

## Snapshot publication guard (review round 1)

Location/history reads fingerprint current family membership, all member consent settings, member subscription facts and owner access before loading points. Before returning coordinates they reload the original actor's admission and compare the fingerprint with the current consent clock. Any removal, changed consent/history settings, access loss or crossed expiry discards the snapshot. Reader/clock seams allow deterministic sandbox regressions after real SQL completes and before publication.

Invitation browser landings return a local typed invalid-input refusal (HTTP 422) for unsupported settings. Their route metadata has no per-feature Rails gate and their response adapter has no upstream fallback. Genuine HTTP token/status/CSRF acceptance and whole-application routing contracts remain independently tested.

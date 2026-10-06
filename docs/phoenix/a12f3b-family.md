# Phoenix family producer handoff

FAMILY implements plan A tasks F01–F06. The Rails 1.15.3 source characterizations live in `app-phoenix/scripts/parity/family_pages_fixtures_spec.rb`; native tests use `a12f3b_case:F01a` through `F06b` in task-specific test files.

## Activation owned by HOT

Mount `DawarichWeb.FamilyFormRoutes.routes/0` once in the existing browser routing pipeline. Put literal `/family/invitations/new` before `/family/invitations/:token`; it must select the missing Rails action and return 404 even when an invitation has token `new`. Preserve source recognition for legacy formatted form paths and POST method overrides. Domain tests exercise the declared action modules directly with signed Rails session cookies and CSRF verification; Endpoint activation and integration tests belong to H01.

Attach `{DawarichWeb.FamilyGate, :default}` after LiveAuth in the family LiveView session. Its event hook reloads the actor, membership, entitlement and page before events, refusing removed membership or malformed settings without replaying to Rails. FamilyLocations reloads actors for each request and treats admitted malformed reads as terminal native errors.

## Delivery owned by MAIL

Invitation creation locks `command:mail.family_invitation` and writes the existing native `mail.family_invitation` job-outbox payload (`invitation_id`, `locale`) in the invitation transaction. The producer requires native ownership; source-owned delivery refuses without effects. HOT must retain a pre-admission source route while that command remains Rails-owned, and activate creation only with the native leaf available. M09 verifies the final mail callback; FAMILY does not edit delivery workers or registries.

Location request creation uses the existing ResidualCommands/location delivery seam, including its owner selection. M10 verifies final delivery. Acceptance sends recipient and owner notifications; it never resurrects the retired member-joined mail API (master ruling 9).

## Source behavior preserved

- Family names use Rails codepoint length limits. Creation trims source whitespace; structured update names are filtered by strong parameters and succeed without changing the name. Creator-only writes, independent family scoping and validation refusals preserve existing data. Invalid creation renders its source alert; authorization refusals retain same-origin Referer redirects. Missing invitation parameters return 400. Creation and invitation notification failures are rescued without undoing successful writes.
- Deletion requires an empty family apart from its creator. Member departure revokes inherited cloud entitlement, disables sharing and expires pending requests. Publication failure after deletion is terminal, with no replay.
- Invitation email normalization accepts the Rails URI mail validator, including local domains. Exact invitation expiry remains acceptable. Replayed or cancelled invitations never create a second membership. Acceptance refreshes the family period under family/creator locks and commits that refresh even if a downgraded owner's period makes joining unavailable.
- Request responses require the target actor and a strictly future expiry. Web creation persists the request before delivery. An enqueue failure leaves the request and notification committed and returns the source error. This supersedes the plan's proposed F05b rollback expectation under ruling 13; the mutation wraps creation in a transaction and must fail the parity test. The existing API transaction behavior remains separate.
- Legacy sharing permits duration coercion and structured truthy booleans. It remains reachable after a family plan lapses so sharing can be disabled. Errors before a settings write preserve settings; malformed response duration may fail after enabled settings are committed. These failures never hand back to Rails. JSON and Turbo responses retain source locale and status conventions.
- Locations require an entitled family actor and currently consenting other members. Expired sharing, including exact expiry, hides points. The response remains private and non-cacheable.

Known source bugs are retained under ruling 13, including the invitation `new` missing action (DRB-011), malformed settings failures and request enqueue partial effects. This package does not change the controller-owned deferred-bug ledger or shared router/registry files.

Shared knowledge counterpart: **Dawarich — A12f-3b family producers and activation handoff** in AFFiNE. The implementation report records task commits, RED/GREEN/mutation logs, source fixture determinism and final gates; runtime allocations stay outside versioned documentation.

# Standalone demo, digest and area API closure

With `DAWARICH_RAILS=off`, the existing standalone dispatcher binds the six
previously absent Rails API declarations. Coexistence still sends these
requests to Rails. Cloud lifecycle refusal remains in force in every mode.

| Request | Rails-compatible result |
| --- | --- |
| GET `/api/v1/demo_data` | 200, `{ "exists": boolean }` for the authenticated user's demo marker |
| POST `/api/v1/demo_data` | 201 `created`, 200 `exists`, or 422 `error` in the `status` field |
| DELETE `/api/v1/demo_data` | 200 `destroyed` or `no_demo_data`, or 422 `error` |
| POST `/api/v1/digests` | Top-level JSON `year`; 202 generation message, 422 invalid year, 409 existing yearly digest |
| DELETE `/api/v1/digests/:year` | Delete the actor's yearly digest; empty 204 or Rails record-not-found 404 |
| DELETE `/api/v1/areas/:id` | Delete the actor's area and dependent visits/notes; 200 deletion message or Rails record-not-found 404 |

API keys work in Bearer headers and query parameters; optional `.json` suffixes
use the native transport. Demo requests and digest writes require an active
account. Area deletion retains ordinary API authentication. Pending-payment
admission and English machine-contract messages use the existing API modules.
Digest POST validation retains Ruby integer coercion, the user's local current year
and entitlement-scoped tracked statistics. Generation reuses `YearlyWorker`
with one durable event identity per accepted request; no synchronous calculator,
mail producer or Rails reverse command is added. DELETE member years must match
Rails' exactly four ASCII digits; malformed or oversized years return route 404
without invoking deletion. Out-of-range area IDs return the Rails JSON 404 before
querying the bigint identity.

Demo writes reuse the existing locked importer/destroyer. Area deletion locks the
actor-scoped row and owned visits before inspecting its dependent graph. A
cross-owner visit, point, area/visit note or place link refuses deletion with 422
and `{"error":"Area has foreign dependents"}`, preserving records, references and
jobs. Every dependent mutation is owner-scoped. This fixes the inherited Rails
attachment-only deletion defect documented as [FRB-066](fixed-rails-bugs.md#frb-066--area-deletion-removes-another-users-linked-records). Orphan-place and visit-month
jobs are recorded with `Dawarich.AfterCommit` in the deletion transaction.
JSON writes and digest DELETE use the existing `Api.WriteResponse` transaction
so domain changes, after-commit intents, encoding and response headers succeed together. A response preparation
exception rolls them back without replaying the request to Rails; existing native
error handling returns 500 when its error response can be framed.
This extends the existing native failed-response durability correction to demo,
digest-generation, digest-deletion and area-deletion APIs. The empty digest 204
and its headers are prepared inside the deletion transaction; no content-type is
added. An invalid response header cannot leave the digest durably deleted. Rails commits these writes or queues
work before rendering; the controller report records these Rails bug fixes.
The response correction extends FRB-052; no additional ED/DRB row is added.

Verification lives in `standalone_api_gaps_test.exs`,
`standalone_api_gaps_commit_test.exs`, `standalone_api_review_test.exs` and
`standalone_digest_response_test.exs`: endpoint contracts, native job counts,
foreign/monthly record isolation, SQL and rendering failures, coexistence method
and body preservation, and durable commits outside a sandbox transaction.
Each newly named test has a separately observed production mutation.

Source contracts: `app/controllers/api/v1/demo_data_controller.rb`,
`digests_controller.rb`, `areas_controller.rb`, and their request/swagger specs.
Audit rows closed: R0256, R0293, R0294, R0295, R0301 and R0303 in the controller's
standalone-completeness audit. Recalculation APIs and lifecycle ownership are
outside this change.

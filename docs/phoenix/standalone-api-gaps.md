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
Digest validation retains Ruby integer coercion, the user's local current year
and entitlement-scoped tracked statistics. Generation reuses `YearlyWorker`
with one durable event identity per accepted request; no synchronous calculator,
mail producer or Rails reverse command is added.

Demo writes reuse the existing locked importer/destroyer. Area deletion locks the
actor-scoped row before removing its dependent graph. Orphan-place and visit-month
jobs are recorded with `Dawarich.AfterCommit` in the deletion transaction.
JSON writes use the existing `Api.WriteResponse` transaction so domain changes,
after-commit intents, encoding and response headers succeed together. A rendering
exception rolls them back and returns 500 without replaying the request to Rails.
This extends the existing native failed-response durability correction to demo,
digest-generation and area-deletion APIs. Rails commits their writes or queues
work before rendering; the controller report records these Rails bug fixes.
No shared ED/DRB row is added in this scoped fix.

Verification lives in `standalone_api_gaps_test.exs` and
`standalone_api_gaps_commit_test.exs`: endpoint contracts, native job counts,
foreign/monthly record isolation, SQL and rendering failures, coexistence method
and body preservation, and durable commits outside a sandbox transaction.
Each newly named test has a separately observed production mutation.

Source contracts: `app/controllers/api/v1/demo_data_controller.rb`,
`digests_controller.rb`, `areas_controller.rb`, and their request/swagger specs.
Audit rows closed: R0256, R0293, R0294, R0295, R0301 and R0303 in the controller's
standalone-completeness audit. Recalculation APIs and lifecycle ownership are
outside this change.

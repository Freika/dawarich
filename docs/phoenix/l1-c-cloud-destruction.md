# Cloud account destruction callback

Package C captures the account email and user ID before hard deletion, then publishes one typed `users.destruction_webhook` intent inside the deletion transaction. Its identity derives from the accepted deletion event. A rollback publishes no unlink; committed receipt replay sends nothing. Account admission, confirmation, ownership and family policy remain in the shared deletion implementation.

The callback uses the shared after-commit runner and configured Manager transport. The unlink path is fixed, TLS verification stays enabled, redirects are not followed, and the request has a ten-second timeout. Source-compatible retries preserve the captured identity. An accepted HTTP send followed by process death before its receipt can cause a repeated remote unlink; local receipts do not guarantee remote deduplication.

## Dispatch regression verification

`test/dawarich/users/cloud_destruction_test.exs` and `test/dawarich/users/standalone_deletion_test.exs` exercise an explicit consumer clock behind the producer's schedule, preserve the account while the intent is not due, and dispatch at the exact committed due time. The callback test reads its own committed due time as well. Tests pass `now:` to Dispatch rather than assuming PostgreSQL and BEAM wall clocks agree. No sleeps, deadline increases or scheduler policy changes are required.

The two reported `test/dawarich/release/cloud_review_test.exs` failures occurred at provisioning with `newer_private_schema`. Keeping the recorded digest migration while omitting its file from the runtime catalogue reproduces both failures. Integrating the current migration catalogue resolves that mismatch; provisioning must continue refusing an unknown newer ledger. Fixture reuse must account for native migration catalogue changes as well as the Rails schema. Controller-owned fixture handling remains with the controller.

Public native Cloud lifecycle refusal remains enforced in every mode until the external L1 handoff. This callback does not authorize activation or rollout.

Execution evidence: controller reports `impl-l1-c.report.md` and `fix2-l1-c.report.md`. The shared AFFiNE document **Dawarich — Phoenix Ruby-free release operator contracts** indexes this contract and the review correction.

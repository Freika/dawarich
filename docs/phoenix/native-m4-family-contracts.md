# Native family domain contract

`Dawarich.Families.page/3`, `locations/2`, `history/3` and `subscribe/2` take an `Accounts.Scope`. Every read reloads the actor and compares the original session identity before reading current membership and entitlement. Invalid input, missing targets, stale sessions, inaccessible families and expired access return typed errors; native callers never receive a Rails hand-back sentinel.

Page DTOs preserve the existing owner/member/create/upgrade/lapsed/request branches, dates, ordering and invitation metadata, but omit invitation tokens. Tokens must be revealed through authenticated HTTP into transient browser DOM. Location/history reads reuse the existing consent, history window, viewer exclusion and strict expiry rules. A subscription grants no continuing permission: consumers must call the scoped read again before delivery.

Family invalidations use an owner topic and `{:domain_changed, user_id, kind}` with a closed kind. The event contains no location, email, settings or credentials. Durable command producers are the next implementation step.

The initial domain tests use the existing Scope identity contract. Controller-owned X1 must supply the sanitized principal contract before native page integration; full user structs must never enter native socket assigns.

Verification: `families_scope_test.exs` has five read/subscription regressions, each checked with RED, GREEN, a discriminating mutation and restored GREEN. The consent equality, family/history and API golden corpora remain unchanged. Synthetic two-member domain reads observed 10 queries for show, 5 for invitations, 2 for new and 9 for locations. These include one fresh actor read; location admission adds one current family/owner read. These are domain measurements, not LiveView mount budgets.

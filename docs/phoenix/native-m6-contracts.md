# Milestone 6 native map contracts

Status: foundation in progress, 2026-10-10. The controller starts tracks B/C/D only after the separate S1 SHA artifact exists. Source baseline is `bdaa9aa36`; the A0 measured baseline is recorded in `native-m6-inventory.md`.

## Session and domain admission

`Dawarich.Maps.principal(user, locale)` returns an Accounts.Scope containing a sanitized actor and a SHA-256 fingerprint of the original Devise session salt. Raw API keys, password hashes and provider settings never enter this scope. The fingerprint remains immutable across refreshes. `Maps.admit(scope)` returns a refreshed sanitized scope; `Maps.with_actor(scope, effect)` independently checks that original fingerprint, lock/deletion/status/subscription before invoking the effect with its transient domain actor. Commands must recheck inside their transaction when they span a read/effect boundary.

`Maps.page(scope, params, opts)` wraps the existing MapPage queries and returns `{:ok, projection}` or `{:error, :stale_session | :unauthorized | :not_found | :invalid | :unavailable}`. Projection excludes credentials, bulk points/tracks and signed subscription URLs. Settings on the actor are allowlisted. Existing hybrid consumers of MapPage remain unchanged until X1; no native host delegates its UI to them.

`DawarichWeb.MapLiveAuth` is the dedicated native host hook. Its `live_session/1` signs the original map identity into the server mount session. Connected mount also compares the socket session actor ID; events, params, info and async each re-admit. Session loss clears state and redirects to sign-in. Resource refusal clears the projection and records a typed error in place, with no reload to the same URL. X1 adopts this hook on the routed hosts.

## Dependency adapters

| Adapter | Current implementation | Accepted dependency awaited | Switch task |
| --- | --- | --- | --- |
| `Dawarich.Maps.Dependencies.Principal` | Accounts.get, Devise salt fingerprint, sanitized Scope | m4 fresh/sanitized principal and callback admission | Controller integrates m4, then dedicated adapter switch with original-session revocation tests |

The other O10 dependencies (m4 upload claims/finalization, owner invalidations, family consent/public admission; m5 Trip/Visit/timeline projections and map insertion points) receive one thin adapter each when the owning A/B/D task first consumes them. The ledger will name actual modules and methods at that point. No duplicated domain queries or placeholder native fallback is part of this contract.

## Verification

A1 covers real LiveView events/params/queued info/async delivery on a routed test host; scope refresh followed by password revocation; actor deletion, lock, inactive/pending status; credential-free projection and state; typed missing-place refusal. Named mutations and strict direct-caller batches are recorded in the implementation report.

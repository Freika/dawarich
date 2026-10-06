# A12f-3a W closure

W10/W11 implement native top-level area POST/PATCH/PUT forms and actor-scoped writes. Valid and invalid Turbo responses preserve Rails HTTP 200 and append the translated success/error flash. Invalid coordinates/radius leave the area unchanged; foreign IDs return 404. Name-only and no-op updates do not enqueue relabeling. Create/reshape produces `areas.relabel_visits` version 1, payload `{area_id}`, aggregate/dedupe identity = area ID, under the existing ownership lock. The existing RelabelWorker performs historical visit attribution.

The explicit Sidekiq owner rolls back and hands back before commit. Native work uses the existing public outbox; registry claimability remains with sibling rows20–22.

Minimal route wiring in page_routes.ex makes these forms reachable. O06/O07 should retain/reconcile this wiring in its serialized route pass.

Source captures W10/W11 were obtained locally because the O03–05 captures were not present at the assigned base. Two writes are byte-identical. The Rails request/job batch passed 73 examples. W10's initial RED was HTTP 502 instead of 200; reading an invented nested area root failed the successful flash assertion. W11's initial RED was the absent WebWrite module; publishing relabel on a name-only update failed the empty-outbox assertion. Both restored selectors passed (one selected test each).

Residual format, locale and legacy coercion envelopes and the remaining W tasks are still being completed. This document does not declare shared effect sinks or release browser gates closed.

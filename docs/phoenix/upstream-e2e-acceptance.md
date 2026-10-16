# Upstream E2E absorption

The native E2E feature branch merges upstream Playwright main through `cf25763`.
Rails remains the behavior oracle; native LiveView connections, cookie-bound
map reads and native hooks own readiness and markup.

Public trip day galleries deliver image elements only after expansion, remove
them on collapse, and reload them on reopening. Each gallery command passes the
existing public grant admission hook. Private and disabled photos stay refused.
The native `PublicGallery` hook forwards the actual details toggle and removes
its listener on teardown; the server owns image rendering.

Native search keeps successive completed visit selections visible and clears
them after an outside map click. Map controls retain a 40px minimum touch target.
Changing map style discards the previous editing geometry and history; it does
not retain undo controls belonging to the old style.

Named witnesses are in `public_native_gallery_test.exs`,
`test/client/public_gallery_test.mjs`, `phoenix_m6_host_search_test.mjs` and
`phoenix_m6_host_editing_test.mjs`. Each new witness has failing-first and named
mutation evidence in the controller report. Browser counterparts retain the
upstream behavior assertions through native selectors and connection receipts.

Native timeline selection and point-edit geometry have independent owners.
History assertions inspect the selected timeline source while editing may
invalidate its own stale geometry. Replay request assertions count complete
bounded snapshot pages separately from live-marker reads.

The old insights Countries card no longer exists in Rails 1.16.0. Its successor
exercises the year residency view, page scrolling, mobile country expansion and
horizontal bounds rather than the retired card's fixed height.

Whole-suite MacBook and mini acceptance remains pending. The controller report
`impl-e2e-upstream-1016.report.md` records the paired commits, exact lane counts,
remaining scenarios and cleanup; this document does not claim release acceptance.
AFFiNE counterpart: `Dawarich — Rails 1.16.0 native shell sync`.

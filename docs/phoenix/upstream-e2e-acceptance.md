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

Acceptance requires one complete standalone MacBook lane and one complete mini
lane with zero failures, preserving declared non-applicability and privacy
reporting. The controller report `impl-e2e-upstream-1016.report.md` records the
frozen paired commits, exact lane counts, mutation evidence and cleanup.
AFFiNE counterpart: `Dawarich — Rails 1.16.0 native shell sync`.


The tile cutover cases now use isolated native fixtures. Offline browsing keeps
Point and Track vector sources and bundled country PMTiles without complete
history reads. Import-scoped metadata/tiles, bounded selection and Replay,
LiveView-delivered timeline journeys, day routes, flight exclusions, canonical
edits, stale refusal, rollback, style/range teardown and reduced-motion feedback
retain individual browser assertions. The million-point measurement is outside
the existing D1–D4 native performance scope; the dedicated Cloud/Lite server is
outside self-hosted lane admission. No applicable case is blanket-quarantined.

Native read failures expose a bounded, localized Retry control owned by the
ignored map hook. Shell patches retain it; teardown removes it. Point/Track
retries replace their failed vector sources, preserve filters and admit a fresh
error episode. Country metadata and bundled PMTiles have independent retry
flows. The bundled native country archive serves exact single byte ranges under
the existing path, symlink, host and HTTPS checks. Other legacy public-file
range behavior remains subject to its existing admission.

A successful edit applies its visited-country receipt immediately. A later map
edit invalidation rereads membership in each connected tab. The editor survives
its own already-confirmed edit only after a fresh canonical track revision check;
a newer foreign revision, pending command, read refusal or reconnect retires
stale geometry. Range/style changes retain their separate cleanup boundaries.

Protected map capture installs the account-scoped onboarding key before
navigation, waits for the connected renderer, dismisses optional prompts after
connection, and checks loaded tiles plus an unobscured map before its private
screenshot. The native CLI receipt exposes only readiness booleans alongside its
existing protected artifact receipt. Rails and non-map capture paths keep their
existing behavior. Repository E2E counterparts are the individually named
`tile-only` cases, the native map-toast backport and `native/scenario-capture`.

# Standalone place browser envelopes

Place modal submissions include the scalar root field `_method_url`. The
retained place-creation controller leaves it in both create and edit forms;
edit adds `_method=patch`. Rails ignores `_method_url` when permitting nested
place attributes. Phoenix now accepts that scalar field for place create and
update in `DawarichWeb.PlaceRequest`, without changing shared A8 admission.
Nested values, unknown root fields and the field on other actions remain
outside native admission. Authentication, CSRF and ownership checks still run.

`StandalonePlaceBrowserTest` covers the actual Turbo Accept list, modal create
with a note, marker edit with tag replacement, repeated drawer note saves with
`Turbo-Frame: place-drawer`, and trip-note create/update/delete with their day
frame and method overrides. The place regression first returned 422; restoring
the original root validation reproduces that failure. Trip notes characterize
existing behavior: removing their permitted body field fails the create request.
Both mutations were restored and the two tests pass. The targeted place,
trip-note and shared request batch passes 29 tests; forced warnings-as-errors
compilation and whole-tree formatting checks also pass.

A real Rails request oracle with CSRF protection enabled returns 200 Turbo
streams for all eight submissions and verifies the same persisted notes/tags.
Modal create replaces `place-creation-data`; modal edit also updates
`place-drawer`; drawer saves update only that drawer plus flash messages;
trip-note operations replace the day frame.

Required browser acceptance is the four assigned Playwright files at the
controller's pinned E2E commit, three standalone runs and one coexistence run,
with one worker and zero retries. The controller authorized the pinned checkout
and a fresh full-gate allocation for the crash continuation. Browser acceptance
and full-gate results are recorded in the task execution report. No Rails
defect is fixed by these parity corrections; no fixed/deferred Rails bug
register entry is required.

The shared AFFiNE counterpart is the places follow-up in
`Dawarich — Final G44 and image smoke launch runbook`.

Browser continuation found two further request incompatibilities. The retained
map controller submits full-precision coordinates. Place web writes now accept
that decimal precision and round with Decimal to the Rails columns' six-decimal
scale before constructing geometry, so subsequent drawer edits see coherent
coordinates. The existing coordinate bounds remain enforced.

Standalone drawer/navigation and nearby reads now validate ignored query
fields using the existing Rails-compatible ignored-query decoder. Known nearby
fields retain their scalar validation; session and ownership gates remain.
Coexistence keeps its existing extra-query handoff. No shared decoder changed.
A real Rails request oracle accepts scalar, hash and array extra fields and
confirms identical decimal/geometry rounding. Both new tagged regressions
first fail their status assertions, pass the fixes, fail named production
mutations, and pass again after restoration.


The crash continuation's final-head browser runs pass marker editing, place-note
creation, and modal-close persistence three consecutive times in standalone.
All four assigned files pass once in coexistence. The pinned direct-open spec
saves both drawer notes and gets 200 for the extra-query drawer request, then
fails solely because it requires Rails' `x-runtime` header. That retained-owner
assertion belongs to coexistence; standalone serves the drawer natively. It was
reported unchanged for controller correction, so complete standalone browser
acceptance remains blocked. Every lane uses one worker and zero retries, with
zero skipped or flaky cases. The final caller batch passes 35 tests. Exact
browser and full-suite evidence is in the task execution report.


The single full seed-404 gate completed with 9,898 tests and three layout
assertion failures caused by generated browser asset manifests selecting
fingerprinted CSS paths. Moving that generated asset state aside restores the
ordinary test URLs: the unchanged layout and places batch passes 21 tests.
Keep generated browser manifests/assets aside for ExUnit layout gates and
restore them for browser runs. A passing full-gate rerun remains pending
controller authorization under the one-run limit; targeted proof does not
replace that gate.

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
with one worker and zero retries. At implementation time the required private
detached E2E checkout was denied by automatic approval review, so browser
acceptance remains pending. See the task execution report for exact gate
results and the approval decision. The prescribed full-suite runner also
derives Redis ports occupied by another task; a private gate allocation is
pending controller approval. No Rails defect is fixed by this parity
correction; no fixed/deferred Rails bug register entry is required.

The shared AFFiNE counterpart is the places follow-up in
`Dawarich — Final G44 and image smoke launch runbook`.

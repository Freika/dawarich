# Native onboarding demo data

Phoenix imports and removes the onboarding demo synchronously in standalone mode.
The compressed fixtures in `app-phoenix/priv` are byte-identical copies of the
retained Rails demo fixtures in `lib/assets`; release imports read `priv` without
loading Rails or using a Rails root path.

`Dawarich.DemoData.Importer` locks the user and creates the marker import,
shifted points, countries, tracks, segments, tags, places, visits, trip description
and month stats in one transaction. Existing markers return `exists`. The anchor
is the user's local start of today; fixture offsets place the latest data on
yesterday. Fixed-second fixture offsets across DST match Rails. Existing real
tags and stats are preserved. Track point assignment is restricted to the marker
import. Country assignment intersects subdivided polygons within the import bounds.

`Dawarich.DemoData.Destroyer` removes demo visits, trips, tracks and the marker's
points; retains adopted entities, places used by real visits, tags used by real
places, and month stats containing remaining points. It publishes one existing
`stats.calculate_month` native command for each affected month with real points.
No visit-orphan or import-recalculation callback fan-out is produced. Cache
invalidation covers the affected local month summaries and existing user/digest
cache keys, including on import. Post-commit failures preserve Rails' successful
result. Unsupported attached content returns a native error and rolls back,
consistent with tonight's ruling 15; full rare-envelope parity remains separate.

Post-hoc cleanup corrections detach attachments from the deleted marker,
points, stats, visits, tracks, tags and trips, including supported trip notes
and rich descriptions. All use `Dawarich.Exports.PurgeWorker`, whose shared
purge machinery removes stored objects before blob/variant rows and retains
rows on storage failure. Shared blobs retain their other attachments and bytes.
Place and visit-note graphs outside the supported envelope still roll back.

Demo cleanup locks the owner's demo graph and refuses unsafe cross-owner
dependent references with the existing native error. Point nullification,
extracted import links and place/trip dependent writes are owner-scoped.
Foreign extracted import references without foreign-key constraints remain
unchanged when the marker disappears. The inherited Rails isolation defect is
registered as [FRB-031](fixed-rails-bugs.md#frb-031--demo-removal-can-alter-another-accounts-dependent-records) in `docs/phoenix/fixed-rails-bugs.md` under ruling 17.

## HOT handoff

Mount `DawarichWeb.OnboardingRoutes.onboarding_routes/0` in the shared router;
its existing onboarding-completion routes remain present. The module now declares
POST and DELETE `/settings/onboarding/demo_data` through `:standalone_settings`,
using the existing standalone settings gate. POST with `_method=delete` invokes
destruction. No shared router, Strangler, route macro owner or job registry file
was changed by DEMO. `stats.calculate_month` already maps to
`Dawarich.Stats.CalculateMonthWorker`; HOT needs no new command registration.

Actions require a matching Rails session user and valid CSRF admission. Created
and existing imports redirect to `/map/v2` with timeline panel and user-local
yesterday's start/end query; destroy/missing/error results redirect to root with
translated Rails-session flashes. Existing map demo banner and Delete form use
this URL. HOT owns integrated Endpoint/browser route acceptance.

## Verification

The unique task files `a12f3b_n07_test.exs`, `a12f3b_n08_test.exs` and
`a12f3b_n09_test.exs` cover DST, countries, dimensions, retry identity, bundled
fixture import, derivative rollback, authenticated/CSRF form actions, ownership,
scoped deletion, mixed and demo-only month stats, shared real places/tags, cache
invalidation and delete rollback. Each of the six named tests has its plan's
RED/GREEN/mutation/restored-GREEN evidence in the controller report.

Shared knowledge counterpart: AFFiNE document
`Dawarich — Demo data import and onboarding load` (`NlnCxYrw7yZXilTOdkJzb`).

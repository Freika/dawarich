# Visits and redetection closure

Package V implements the visits web domain on the existing domain dispatch.
The source controller/model remains the behavior oracle for Rails 1.15.3.

## Navigation (V01)

Public GET/HEAD `/visits` redirects with status 302 and preserves an explicit
empty status in self-hosted, explicit Cloud and unset mode. The package-owned
request gate admits the same scalar envelopes in each mode.

The new aggregate test failed initially when Cloud attempted Rails fallback,
passed after removing the domain Cloud veto, failed when the empty status was
replaced with `confirmed`, and passed after restoring production.

## Source handoff

The base has existing A8 visit and settings captures but lacks the task-specific
V01–V09 paths. The execution brief authorizes capturing these locally. The
existing map-frame and settings generators write additional V aliases of their
real request/graph results without changing existing cases or adding a driver.
O05/O08 must reconcile these focused generator changes with its own captures.

Rails merge keeps the base visit's notes and destroys removed visits' notes;
the source does not concatenate notes. Ruling 13 requires that behavior. The
planned V06 mutation that discards the second note already describes Rails
behavior; its source-backed inverse (retaining the removed note) is required.

No shared router, Registry or transport files are changed by this cut.

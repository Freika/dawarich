# Standalone recalculation admission and queueing

The standalone API queues `users.recalculate_data` for the authenticated API
actor. It locks native ownership before writing the Rails-compatible pending
flag, and inserts the outbox event before reserving pending state. Source-owned
or failed production remains retryable without a false 30-minute reservation.

The web action `POST /tracks/recalculation` accepts global and action/method
specific Rails CSRF tokens. Either the body or header token can verify this
request, as in Rails `verified_request?`; wrong action/method, missing tokens and
foreign origins still refuse. Existing conservative coexistence admission for
all map writes remains. Extra body fields do not select a target: the action
always uses the session actor. A valid anonymous form reaches the existing
sign-in redirect without queueing work.

## Durable web retry fence

`phoenix.transportation_recalculations` has a primary key on `user_id`. The web
producer claims that row and inserts its root outbox event in one transaction
under the user lock. A conflict reports already running, including before any
worker starts or after Redis progress is lost. Ownership refusal never claims
this row.

The committed fan-out sets the remaining child count. Zero-track fan-out releases
the fence immediately. Each committed progress intent decrements the count only
for a child belonging to the current root event; the last child releases it.
Existing intent receipts prevent repeated delivery from decrementing twice.
Root failure or missing actor releases its matching fence. The native migration
is additive; Rails production and the Cloud lifecycle refusal are unchanged.

This intentionally repairs the Rails queued double-click defect, under the
controller's explicit exactly-once requirement. See ED-FIX-SWEEP6-RETRY and
DRB-FIX-SWEEP6-RETRY. Other admission changes restore Rails behavior.

## Oracle and regressions

`app-phoenix/scripts/parity/standalone_recalculation_spec.rb` records the web
fixture with `RECORD_RAILS_PARITY=true`, clearing jobs between scenarios and
using Rails' own per-form token with forgery protection enabled. Ordinary runs
compare the stored web snapshot. A clean web request queues only
`TransportationModes::UserReclassifyJob`. The source characterization also
confirms actor-only extra parameters, anonymous redirect, and Rails' two queued
jobs after two pre-worker submissions.

`test/dawarich_web/standalone_recalculation_test.exs` retains the review's five
named scenarios plus the isolated-fixture assertion. The retry scenario also
covers SQL uniqueness, missing Redis progress, empty and nonempty fan-outs,
repeated progress delivery and a fresh request after completion. Named source
mutations and release gates are recorded in the controller's fix2 review report.

Shared index: AFFiNE, **Dawarich — Standalone journey sweeps and native
confirmation** (`yOmZHafRYnvfFikBv_3K0`).

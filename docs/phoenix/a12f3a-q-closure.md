# Stats, insights, digests and public month implementation

Last updated: 2026-10-06. Rails 1.15.3 is the source contract. Repository implementation covers the supported native browser journeys in package Q. Release retirement remains conditional on the shared transport, cache/effect and final route integration handoffs described below.

## Domain contracts

- `Stats.WebCommands.update/5`: repo, user, year, month, context (now/locale); typed `stats.calculate_month` outbox entries under the existing command owner lock. A single month publishes once; all publishes twelve. Invalid periods retain the source alert and publish nothing.
- `Stats.WebCommands.update_all/3`: transactionally claims the existing user dedupe key for 900 seconds and publishes one `stats.full_recalculation` command with source job UUID. Duplicate requests retain the source notice. Existing full-recalculation worker and tracked-month calculations remain the terminal implementation.
- `Digests.WebCommands.create/4`: validates source past-year/tracked-year rules and publishes typed `digests.calculate_year`, including actor time zone. `destroy/4` deletes only the actor's yearly digest; source found 303 and missing 302 responses remain distinct.
- `Digests.Sharing.update/5` and `Stats.Sharing.update/6`: actor-scoped mutations preserve UUID, exact enabled coercion, all five expirations, locale messages and JSON/Turbo results. Hour durations use elapsed time across DST; week/month durations use calendar time. Disabled and expired public capabilities redirect to the root with the source flash. Public digest lookup uses the capability's exact row, including a monthly digest UUID.
- Public digest full/partial and public month documents retain source page markup, chart payloads and public map data attributes. Public map boot uses the existing Stimulus bridge. Public pages expose no owner API key.
- Native insights details calculate missing or stale yearly/monthly digests synchronously through existing `Digests.Calculation` entry points. Warm Rails cache reads remain compatible. Cold and unavailable cache stay native. Native requests write no Rails fragments and do not enqueue reverse Rails commands. This is not a claim that shared cache/effect workers are retired.
- Source failures remain failures: nil/nonempty string-keyed month daily data, malformed insights periods/daily pairs, nonempty object digest toponyms, nil country flags, non-array first visits and nonnumeric country minutes. Empty legacy object toponyms remain readable.

## Oracle and route ownership

O03 source additions were absent at the allocated base. Under the task's explicit exception, Q extended the existing `stats_fixtures_spec.rb` generator through `stats_closure_fixtures.rb` and captured the fourteen assigned JSON files. Two complete recordings were byte-identical; preexisting stats fixtures, country names and stats corpus remained unchanged. O08 must reconcile this generator extension with O03's additions.

Minimal reachable wiring in `router.ex` adds stats update, digest create/delete, sharing mutations and public digest/month pages. Public routes carry the relevant stats/digests coexistence key. O06 owns final route reconciliation. No global fallback, route retirement flags, worker readiness registry or shared sink routing was changed.

## Verification convention

Q01 reuses the existing source-backed year/index parity cases rather than inventing a new failing test for already implemented behavior. Its plan-window mutation fails the year oracle and restoration passes. Q02–Q14 add named closure assertions: each initial RED, GREEN, named production mutation failure and restored GREEN is recorded in the implementation report. Additional DST and malformed-digest assertions also failed before their fixes.

## Required integration handoff

The domain implementation does not close unsupported dotted/JSON/XHR/valueless request envelopes or ambiguous/failed CSRF/body/session transport. Shared `Strangler`, `RailsForm`, `Api.Body` and auth primitives remain A12f-2 owned. Explicit Sidekiq ownership is a pre-effect coexistence hand-back; native post-effect failures are terminal.

Q04/Q07/Q14 final no-Rails cache/effect terminal proof depends on sibling rows 19–20. Existing effect sinks/registry readiness remain inert until that handoff. The public map still consumes `/api/v1/maps/hexagons`, which belongs to A12f-2 package C; this package supplies native page bounds and capability hooks, not an unowned replacement API. O06/O08 must reconcile routing/source captures; the controller runs seed 202 on the integration head.

No browser acceptance or whole-domain retirement is claimed by this implementation. Gates and exact commit/test evidence are maintained in the assigned controller report. AFFiNE counterpart: Dawarich — Phoenix A12f-3a Q native stats and digest implementation.

## Task commits

- Q01: verify existing index and year parity; source/mutation evidence recorded.
- Q02: preserve month comparisons and malformed data failures; source/mutation evidence recorded.
- Q03: preserve period selection and source failures; source/mutation evidence recorded.
- Q04: calculate cold and stale digests natively; source/mutation evidence recorded.
- Q05: serve native details frames in Cloud mode; source/mutation evidence recorded.
- Q07: publish deduplicated full recalculation commands; source/mutation evidence recorded.
- Q08: retain private source failure boundaries; source/mutation evidence recorded.
- Q09: generate past yearly digests natively; source/mutation evidence recorded.
- Q10: pin actor-scoped deletion and missing responses; source/mutation evidence recorded.

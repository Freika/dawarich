# Native visit producers

R20 closes the bulk suggestion, settings redetection, and realtime-arrival visit producers. The existing visit HTTP routes, command registry, suggestion worker, and full-history worker remain their entry points.

With `DAWARICH_RAILS=off`, bulk suggestion children and settings redetection requests run natively even when their persisted owner rows select Sidekiq. Bulk cron admission also selects native work in this mode. Coexistence still locks the command owner and retains the Rails reverse command when Sidekiq owns the effect. This standalone selection assumes Rails is stopped; it does not transfer accepted source jobs or consume old reverse rows.

Settings redetection locks the user row, checks the existing completion-based one-hour cooldown and timezone, and writes the existing version-one `visits.full_history_redetect` command. Dispatch carries its event ID into `RedetectWorker`, which retains the start/month lease, month retries, progress counts, completion notification and cooldown stamping. Pending requests are not deduplicated: Rails permits another request before completion, and the worker prevents simultaneous runs.

Realtime intake calls `Visits.RealtimeDebouncer` only for its `visits.realtime` effect. Native admission requires configured geocoding, an existing actor and enabled suggestions. The producer uses Rails' shared `visit_realtime:user:<id>` SQL claim: the first arrival publishes `visits.suggest` for five minutes later over the previous six hours; repeat arrivals extend the ten-minute claim without creating another command. Claim and outbox publication share a transaction, so failed enqueue rolls back the claim. User timezone, calendar stepping and entitlement restriction use the existing native adapters.

`SuggestWorker` clears the debounce claim at the start and rechecks user existence and suggestion preference before processing. Once execution starts, a later arrival can schedule another window. Standalone visit month invalidation also runs natively; coexistence keeps its existing owner choice.

## Integration handoff

HOT owns final registry activation and route mounting. This package edits no hot files and needs no new worker registry entry or route: the existing `visits.suggest` and `visits.full_history_redetect` mappings already dispatch both native workers.

The minimal shared-file seam is the `visits.realtime` branch in `Ingest.Intake.commands!`. RX-POINTS and RX-TRACKS should retain that delegation when reconciling their neighboring arrival effects. The optional owner argument in `HistoryRedetect.enqueue` is internal to the standalone settings producer. BulkSweep changes must be retained when SOURCE-PLACES verifies its source contract.

Place enrichment, point broadcasts, tile invalidation, anomaly work and track effects have separate package owners. This work does not claim those reverse kinds closed or change their policies. Existing reverse rows still require controller disposition.

## Evidence

`test/dawarich/a12f3b_r20_test.exs` exercises the actual producers, outbox dispatch, Oban execution and native SQL results. Its three named aggregates each have baseline RED, GREEN, a failing production mutation and restored GREEN evidence in the controller execution report. Neighboring visit, intake and source characterization tests remain part of verification. Seed 404 is the package gate; seed 202 belongs to the integration head under ruling 14.

The AFFiNE counterpart is “Dawarich — Phoenix visits and redetection implementation” (`BsApq3bMe4_hiZ9Co4mUq`).

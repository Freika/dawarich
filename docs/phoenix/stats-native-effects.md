# Native stats and digest effects

R06–R07 retain Rails 1.15.3 period calculations and mail eligibility. In standalone mode (`DAWARICH_RAILS=off`), stats and digest producers choose native execution even when an ownership row remains pinned to Sidekiq. During coexistence, the first accepted publication fixes the runtime for that event, user and period; replay after an ownership change keeps that original delivery. Fresh events follow the current ownership. Stats and digest reverse payloads retain their period fields and add the scoped execution identity as `source_job_id`.

Stats scheduling inserts `CalculateMonthWorker` jobs, preserving the notification flag and delay. Callers with a stable event can pass `event_id` to suppress duplicate publication of the same user and period while retaining every month in a composite fanout. Full recalculation publishes `stats.full_recalculation` to the existing job outbox using an identity derived from `source_job_id`, command and user; the existing worker clears the shared debounce and fans out tracked months.

AirTrail storage claims the accepted event in its transaction and schedules the union of months before and after the sync. Flight dates take precedence; missing dates use the departure timestamp in the user's timezone. Deleted and moved flights therefore invalidate their former months as well as their current months.

Stats calculations, toponym refresh and nightly geocoding call the native cache invalidator when the stats calculation owner is Oban or standalone is enabled. It deletes shared Rails Redis cache keys and scans the exact yearly insights snapshot prefix. The toponym scope retains total-distance and geocoded-point caches; the all scope removes them. Other users and years remain intact. Readers that query PostgreSQL directly need no additional cache.

Digest scheduling inserts the existing monthly/yearly native workers, preserving source timezone and due time. Calculation settles its accepted event once and publishes the existing digest mail command. Publishing mail does not mark the digest sent; the existing enqueue worker checks saved eligibility, queues delivery, then marks sent. The existing failure and sent-at ordering remain unchanged.

No new reverse poller or generic dispatcher is introduced. Existing worker registry entries are reused. HOT retains ownership of final registry and route integration. Other point/import/release packages can use `Stats.Schedule.calculate/6` for monthly fanout; their composite effects remain with their assigned owners.

Execution authority: `2026-10-06-phoenix-a12f-3b-producers-plan-d.md`, R06–R07, and the controller's standalone ruling 15. Test evidence and integration notes are recorded in the RX-STATS implementation report and shared AFFiNE knowledge base.

## Durable publication and execution

Publication, monthly execution, digest generation and digest terminal publication have separate deterministic identities. `Stats.EffectIdentity` scopes the source event to the effect, user, year and month using the existing UUID helper. The existing `phoenix.processed_commands` unique event key serializes duplicate admission, and its receipt commits in the transaction that writes the corresponding delivery or calculation. Receipts survive completed Oban/outbox row removal. A composite source event therefore retains every user and period without creating a second delivery after ownership changes. No runtime handoff or new dispatcher is introduced.

Every newly scheduled monthly job carries an event ID. Accepted legacy Oban jobs without one derive their execution identity from the persisted Oban job ID and period. Synthetic calls without a persisted ID use a deterministic argument identity. Successful and missing-user calculations settle once; calculator failures leave no successful receipt, preserve the existing failure notification and remain retryable. Nested calculator transactions use the existing savepoint helper, so failed writes roll back without poisoning the receipt transaction.

Digest generation commits its database writes and a scoped generation checkpoint together, before attempting terminal publication. The checkpoint stores a successful outcome (`mail` or `missing`) in the existing receipt handler. A failed generation removes its checkpoint claim, retains the source failure notification, returns a retryable error and never consumes the terminal receipt. A terminal retry reads that outcome and publishes only the outstanding terminal effect, without rerunning monthly stats or digest storage. Terminal receipts and mail intent identities include the user and period. Simultaneous deliveries serialize on the database checkpoint rather than on process state. Existing nil-digest mail chaining, failure reporting, eligibility checks and enqueue-before-sent-at behavior are retained.

The controller fix is verified by the seven retained post-hoc probes in `test/dawarich/fix_rxstats_test.exs`. They also cover legacy redelivery, pruned delivery rows, both ownership-flip directions, composite fanout, concurrent admission, publication rollback and concurrent digest generation. Each named probe has baseline RED, GREEN, mutation failure and restored GREEN evidence in the controller implementation report. The shared RX-STATS AFFiNE document indexes the same contract.


## Upgrade receipts and Rails completion

Generation recognizes a pre-upgrade raw-event receipt only when its handler matches the monthly or yearly terminal effect. This preserves completed legacy events and their original mail identities. New composite events write scoped receipts, so different users and periods remain independent. Explicitly failed scoped checkpoints left by the previous fix release their matching terminal receipt atomically on redelivery; successful checkpoints remain consumed.

Rails stats and digest jobs use the same UUIDv5 receipt identity as Phoenix. Their execution receipt and successful database result commit together under the existing unique event key. Redelivery preserves the accepted result, and an ownership flip checks completion before forwarding. Failed attempts release the receipt; notifications keep their existing source disposition. Digest mail admission uses the existing durable `RailsCommands::Poller.publish` seam: its intent commits with generation and the receipt, then the existing after-commit handler attempts enqueue. An enqueue failure retains the intent for poller retry without regenerating the digest.

Native schedulers place their scoped execution identity in the reverse command's `source_job_id`. The Rails consumer retains it as both the ActiveJob identity and an explicit execution receipt. Forwarded typed commands carry that receipt through the validated optional `execution_receipt` field; native workers consult it before calculation. Existing payloads without these fields keep their original job-ID-derived identity. No schema migration, new dispatcher or queue handoff is added.

Review regression probes are in `test/dawarich/fix2_rxstats_test.exs` and `spec/jobs/stats/redelivery_spec.rb`. They retain the four reviewer digest scenarios, exercise real Rails stats/digest calculations on serialized redelivery, preserve results after ownership flips, and verify the scheduled Rails/native completion identity. The controller fix2 report records RED, GREEN, mutation/restoration and release-gate evidence.

## Atomic cross-runtime digest generation

Rails and Phoenix take the same PostgreSQL transaction-scoped advisory lock, keyed by `hashtextextended(execution_receipt, 0)`, before deciding whether to generate a monthly or yearly digest. Phoenix checks Rails completion and claims generation inside that locked transaction. The earlier completion read remains an optimization; it does not authorize generation. Rails holds the lock through its completion receipt and result writes. A Rails commit between native's initial read and claim therefore suppresses native calculation and storage.

Native successful generation also commits a shared generation checkpoint derived from the execution receipt and generation handler, with null user/period fields in the existing UUIDv5 identity function. The execution receipt already scopes the user and period. Rails checks this checkpoint under the lock before claiming its terminal receipt, so a native mail-publication retry cannot cause Rails to regenerate the digest. Native redelivery with a different source event but the same explicit execution receipt reads the shared outcome. Existing event-scoped checkpoints remain readable for upgrade and terminal-retry compatibility. Failed generation writes no shared checkpoint and retains its retryable failure disposition.

No migration or new table is needed. Rails 1.15.3 keeps its existing positional arguments, calculation and mail behavior, and the helper still executes directly when the Phoenix receipt table is absent. Both runtimes must retain this lock protocol during coexistence and rollback.

`test/dawarich/fix3_rxstats_test.exs` retains the reviewer's real Rails monthly/yearly completion-between-check-and-claim probes and adds reciprocal native-generation/terminal-retry probes. `spec/services/stats/effect_receipts_spec.rb` verifies the Rails lock through an independent PostgreSQL connection. The controller `fix3-fix-rxstats.report.md` records their RED, GREEN, mutation and gate evidence. Shared AFFiNE counterpart: `Dawarich — Phoenix RX-STATS native reverse effects` (`XWYD5Erib3gyCNduJLSx8`).

## Single digest period record

The digest checkpoint protocol above is superseded by
[digest period execution](digest-period-execution.md), following the controller's
fix4 RX-STATS ruling. Both runtimes use the additive period record and shared
period lock for claim, generation and publication. Older successful results and
retained accepted arguments are reconciled before upgraded consumers start.

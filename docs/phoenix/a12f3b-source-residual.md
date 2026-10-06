# Native per-user residual jobs

The E03 package retains Rails 1.15.3 behavior for per-user visit maintenance and
transportation fanout. This is an implementation handoff, not standalone or
G49 release acceptance.

`Dawarich.Visits.UserRedetectWorker` is the fleet maintenance leaf. It uses the
same `tracks:per_user_lock` lease as track generation and the redetection button,
but has no cooldown or user notifications. It purges obsolete machine visits,
detects the history month by month using the captured Rails application time
zone and existing entitlement policy, and backfills legacy confidence. Failed
months preserve the previous `visits_redetected_at`; successful empty histories
are stamped too. Cloud handled month exceptions are reported through Sentry.

The leaf runs on the native `visit_suggesting` queue with priority 3, corresponding
to the source's low-priority maintenance queue. It allows two execution attempts
(source `retry: 1`) with the source polynomial backoff. A busy lease publishes at
most three additional commands, each scheduled 15 minutes later. Each command
has its own event UUID, carries the original `run_id`, and links its immediate
parent in outbox metadata. Recording the handled event and publishing its lock
continuation are one SQL transaction. An insertion failure preserves the event
for retry without stamping completion. Successful duplicates have no effects.

`ReleaseOperations.VisitsFleetRedetect` now calls this leaf's ownership-aware
producer inside its existing cursor transaction. It retains the source active
user filter, 500-user pages, common start time and 30-second stagger. Sidekiq
ownership keeps `release_user_redetect`; Oban ownership writes
`visits.user_redetect`. A failed child insert rolls back both children and the
release cursor transition. The release operation's completed state means fanout
finished; pending outbox/Oban children still block the existing drain observation.

The existing `Transportation.UserReclassify` and `UserReclassifyWorker` are reused
unchanged. They preserve sorted track IDs, 100-track slices 10 seconds apart,
transactional child publication, parent identity, failed cache status and no
automatic parent retry (`max_attempts: 1`). Only per-track completion advances
progress. Duplicate parent events retain the original child IDs and due times;
duplicate child execution does not increment progress twice. An explicit retry
of a failed fanout uses its same uncommitted event identity. There is no source
transportation user lease to add; the native fanout serializes on the user row.

H02 must add `command:visits.user_redetect` with
`Dawarich.Visits.UserRedetectWorker` to the registry, initially unclaimable during
coexistence, before activating this key. No shared registry file was edited by
E03. The fleet producer change is the minimum seam into the existing release
owner. Other source visit wrappers and release-package closure remain with
their assigned tasks.

Accepted Rails serialized jobs continue to drain in the retained source app.
This package neither decodes them nor transfers pending work between runtimes.
Accepted reverse commands remain visible as debt to the existing drain observer.
No source job or wrapper was retired.

Verification is in `test/dawarich/a12f3b_e03_test.exs`: shared-lock contention,
bounded real continuation chain, source-filter skips, real history detection,
partial-month effects, release dispatch, pending-child drain visibility, sorted
101-track fanout and real child execution, interruption rollback and preserved
accepted source debt. Source oracles are
`spec/jobs/visits/user_redetect_job_spec.rb` and
`spec/jobs/transportation_modes/user_reclassify_job_spec.rb`. The named mutations
bypass the user lease and mark transportation complete before child insertion.
The controller implementation report contains exact commands, results and logs.

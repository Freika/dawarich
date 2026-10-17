# Native archive continuation identity

The archive chain has exactly one incomplete Oban row per user, including
executing and retryable rows. Oban uniqueness by user/cursor alone cannot enforce
this invariant: a competing insertion can commit after an unresolved handoff,
and workers can overlap after lease expiry.

Oban migration `20261007120000_archive_continuation_identity.exs` installs a
per-user transaction lock, a reconciliation trigger and a partial unique index.
Publishing a replacement atomically cancels superseded rows and transfers their
accepted coverage into the replacement. Transaction rollback restores the old
row. Oban Basic acknowledges only incomplete states, so late completion or
snooze of a superseded row cannot revive it. The index independently rejects
multiple incomplete identities.

The public `cursor` never decreases. A merged `coverage_floor` records earlier
accepted work without regressing that cursor. ArchiveWorker selects from the
lower bound and carries it forward until the pass advances. Continuation metadata
identifies the publishing parent so its consumed coverage is not reintroduced.
An overlapping worker's independent coverage is still merged. Oban uniqueness
includes the coverage floor so equal cursors with different coverage bounds
reach database reconciliation. Unchanged Oban
uniqueness conflicts preserve the existing job and scheduled time.

ArchiveWorker reads back the persisted continuation before acknowledging it:
Oban's insertion struct may contain proposed arguments rather than arguments
modified by the database trigger. Unresolved insertions and busy leases snooze
the accepted row. Archive verification, snapshot checks, cooling before clearing,
Rails source execution and the shared lease primitive remain unchanged.

The migration can replay an unrecorded ledger: it replaces the function,
reinstalls the trigger and preserves an existing index. It consolidates
pre-existing incomplete chains using their maximum
cursor and minimum coverage floor before adding the index. Its downgrade removes
the constraint and trigger; it does not resurrect superseded jobs. Deploy the
Oban migration with the worker change through the normal release migration path.

Regression evidence lives in `a12f3b_e11_review_test.exs`: E11R1 tests contention
rollback; E11R2 tests a busy lower range during a higher worker's pass; E11RR1A
tests contention commit; E11RR1B tests deterministic lease takeover with two
real archive passes. E11RR1C checks migration replay and E11RR1D combines
lease takeover, a snapshot change and equal cursors with different coverage.
Tests settle jobs through Oban Basic and check drain
visibility, complete coverage and cursor monotonicity.

Shared decision history: AFFiNE, “Dawarich — Native source archive closure
(A12f-3b E11)” (`9E9-ewYUJRm4QG0uBDZon`) and the archive continuation identity ADR
(`mNbizthUKZmJG-wPzUcMI`). Repository code and
tests are canonical for the versioned implementation.

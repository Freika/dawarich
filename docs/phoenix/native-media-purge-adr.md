# Dawarich — ADR-20261007-native-media-purge — Retain storage rows until deletion succeeds

Status: Accepted. Date: 2026-10-07.

## Context

The scoped E13 re-review requires native purge to retain blob/variant rows until
physical deletion succeeds, including failed deletion and serialized retry.
The former shared worker durably retained keys but removed rows in the producer.
Immediate native download revocation must survive the ordering repair. The
original Rails job also loses its serialized target after storage failure; the
fix brief requires preserving Rails-owned coexistence under ruling 13.

## Decision

Keep shared native storage rows until every eligible object is deleted. Reserve
`phoenix_purge_pending` blob metadata for native access revocation and producer
deduplication, while Oban stores root IDs plus durable object keys/services.
The worker locks and rechecks references, deletes storage, then removes rows in
one transaction. Preserve historical key-only job arguments. Native admission,
redirect/proxy/representation lookup and local download/upload endpoints reject
marked blobs. Clients cannot set the reserved metadata through direct upload.

Compute deletion eligibility across the whole reachable variant graph, rather
than traversing each root independently. Ignore variant references only when
their parent also belongs to the eligible purge set. Remove externally referenced
nodes and propagate that protection to descendants until the set is stable.
Persist every eligible target and repeat the same guarded collection at execution;
a shared child referenced only by purged parents must be deleted before success.

Keep Rails-owned handlers and the original purge job unchanged. Record their
original-job reproduction as DRB-025; native cleanup does not inherit target loss.

## Alternatives considered

- Immediate row deletion with durable keys retains retries but fails the required
  row-ordering invariant.
- Retaining rows without access revocation keeps obsolete native URLs usable.
- A separate purge-revocation table needs an additional schema/release seam;
  existing blob metadata is sufficient for this scoped lifecycle marker.
- Replacing the Rails consumer changes the explicitly preserved coexistence path.

## Consequences and verification

Blob locks span background storage I/O. Physical deletion cannot roll back;
missing-object deletion makes later storage/database-error retries idempotent.
Shared attachments protect blobs. Issued S3 URLs still depend on deletion or
expiry, and the retained Rails server does not enforce the native marker.

F2 tests eleven producer/mode combinations through real disk failures and actual
Oban retries, including variants, drain debt and serialized replay. F3 compares
the original Rails job with all three hand-back handlers. Both have recorded
RED/GREEN/mutation/restoration evidence. See [native media effects](native-media-effects.md),
[deferred Rails bugs](deferred-rails-bugs.md) and [fixed Rails bugs](fixed-rails-bugs.md).

Shared knowledge counterpart: AFFiNE document `OMdiuR28X8dfoxOAGppCn`, same title.

F4 regressions cover standalone and native-owned coexistence with two purged
poster roots sharing a child and further descendant, real parent/child storage
failures, still-broken retries, recovery and serialized replay. External parents
and references added after enqueue continue to protect their children and
subtrees. See `test/dawarich/a12f3b_e13_shared_variant_test.exs`.

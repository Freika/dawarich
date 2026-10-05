Status: Implemented
Date: 2026-09-30
Issue: https://github.com/Freika/dawarich/issues/3754

## Context
A NULL reverse_geocoded_at means a point has not completed geocoding; it does not mean the point has no pending job. Nightly force:true bypassed the existing claims. Their one-day TTL also expired while large queues were still draining. Releasing a claim when a lookup fails allows nightly to race Sidekiq retries.

## Decision
Nightly scheduling uses normal non-forced enqueueing. Point and bulk Continue share one atomic Lua claim operation. Newly acquired Redis claims have no TTL; existing expiring claims are persisted without enqueueing a duplicate.
Successful, skipped or missing-record jobs release their claims. Exceptions retain claims through Sidekiq's retry period; the retries-exhausted callback releases them after the configured three retries. Explicit forced reruns retain their existing override behavior and do not release a concurrent normal claim.

## Alternatives
A longer fixed TTL only postpones duplication and cannot represent arbitrary backlog duration. Scanning all queue entries per point is too expensive for hundreds of thousands of points. Adding another queue uniqueness dependency was unnecessary for the existing claim seam.

## Consequences and operations
No migration or external geocoding call is required. This prevents new duplicates; it does not remove duplicates already queued by older releases.
Claims survive slow queues. An operator who manually deletes queued jobs must also release the corresponding stale claims, after verifying no pending/running/retry job still owns them. Redis loss or a crash between acquiring a claim and enqueueing can require reconciliation; an explicit forced rerun remains an operator recovery path. Normal nightly jobs never remove claims simply because a day has passed.

## Verification
spec/jobs/points/geocoding_backlog_spec.rb covers Continue/nightly interaction, persistent claims, legacy TTL conversion, retry retention and retries-exhausted release. Existing Point, Jobs::Create and ReverseGeocodingJob specs cover enqueue failure cleanup, forced override and successful release.
Local source: docs/adr/20260930-geocoding-claims.md in fix/issues-3751-3752-3754-3756.

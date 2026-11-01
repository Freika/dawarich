# Delayed phone motion corrections

`PATCH /api/v1/points/motion` uses the same active API-key authentication and plan access as point ingestion. It is available to self-hosted and active Cloud Lite/Pro clients. No schema migration or settings change is required.

```json
{"updates":[{"id":123,"motion":["walking"]}]}
```

Send 1–1,000 entries with unique positive integer point IDs. `motion` accepts `walking`, `running`, `cycling`, `automotive`, and `stationary`; an empty array clears the phone hint. Generic vehicle activity does not distinguish a car from a train or bus.

```json
{"updated_ids":[123],"missing_ids":[]}
```

Only points owned by the authenticated user are updated. Missing/deleted and other-account IDs are reported identically in `missing_ids`, so a client can finish those queued corrections without recreating history. Coordinates, timestamp, point identity and archived raw data are untouched. Other motion metadata is preserved except the superseded `activity` scalar. `motion_data` is the canonical current hint, including for archived points. Affected tracks are reclassified asynchronously using the existing job, which preserves manual segment corrections.

The batch is validated before writing and row locks serialize repairs with deletes/moves. Repeated identical updates do not enqueue additional classification jobs. Clients must retain their local revision/scope guards for stale responses and retries. Older servers return 404/405; clients must keep corrections queued and never fall back to point creation/upsert.

## Validation

The 12 request examples were run against isolated PostGIS/Redis and the cached `freikin/dawarich:1.15.3` runtime with the new controller, service, route and specs overlaid. They cover deletion/retry, server relocation, ownership, invalid batches, authentication, active Cloud Lite, inactive accounts, empty hints and idempotent track reclassification. Ruby syntax and focused RuboCop also pass. This is compatibility validation; full current-`dev` validation must run in PR CI because the host has Ruby 4.0.6 rather than the required 4.0.9. No live account data was used.

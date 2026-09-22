# Map Matching in Dawarich

Status: proposed

## Summary

Dawarich will use Dawarich Atlas to derive road- and path-aligned geometry for eligible portions of a Track. Map matching is instance-wide, asynchronous, reversible, and display-only: recorded Points and `tracks.original_path` remain canonical.

The first release affects the main Map/Timeline only. Existing public API behavior, statistics, exports, shared views, Trips, Replay, Posters, speed coloring, import filtering, and transportation overlays continue to use original geometry.

Related decisions:

- [ADR-0013](../../adr/0013-map-matching-keeps-original-path-canonical.md)
- [ADR-0014](../../adr/0014-store-map-match-state-on-tracks.md)
- [ADR-0015](../../adr/0015-treat-atlas-as-a-private-service.md)
- [ADR-0016](../../adr/0016-match-transportation-segments-and-compose-the-track.md)
- [ADR-0017](../../adr/0017-enqueue-map-matching-explicitly.md)
- [ADR-0018](../../adr/0018-own-a-versioned-map-matching-quality-policy.md)
- [ADR-0019](../../adr/0019-preserve-original-geometry-in-the-public-api.md)

## Goals

- Improve the displayed shape of noisy GPS tracks without modifying recorded history.
- Support mixed-mode Tracks by matching eligible Transportation Segments independently.
- Fail safely to original geometry at Track and segment level.
- Make processing globally controllable from Instance settings.
- Preserve API compatibility and keep sensitive location payloads out of logs and telemetry.
- Provide a shadow rollout path for calibrating quality on real data.

## Non-goals

- Recalculating distance, speed, visits, or other statistics from matched geometry.
- Automatic backfill of existing Tracks.
- BRouter or gap reconstruction.
- Matching rail, air, boat, stationary, or unclassified segments.
- Matching speed-colored, import-filtered, shared, Trip, Replay, or Poster geometry.
- Public Atlas authentication or bundling Atlas into the Dawarich Compose stack.
- User-specific map-matching preferences or advanced Valhalla tuning controls.

## Domain invariants

1. Points and Original Path are the source of truth.
2. A Matched Path is derived, optional, and disposable.
3. A result is displayable only when the instance setting is on, shadow mode is off, its state is `matched` or `partial`, and it corresponds to the current input fingerprint.
4. Unsupported, rejected, failed, pending, skipped, or stale portions render their original geometry.
5. Provider confidence is diagnostic input; Dawarich's Quality Policy owns acceptance.

## Data model

Add nullable map-matching state to `tracks`:

| Column | Type | Purpose |
| --- | --- | --- |
| `matched_path` | `geometry(MultiLineString, 4326)` | Ordered composite display geometry; retains genuine discontinuities |
| `map_matching_status` | integer enum | `pending`, `matched`, `partial`, `rejected`, `skipped`, or `failed` |
| `map_matching_input_digest` | string | SHA-256 of the exact normalized Atlas inputs and segment modes |
| `map_matching_data` | JSONB, non-null, default `{}` | Compact provider, policy, per-segment diagnostics, and normalized errors |
| `map_matched_at` | timestamp | Time the current accepted or terminal result was produced |

Add a partial GiST index on `matched_path WHERE matched_path IS NOT NULL` and an ordinary index on `map_matching_status` only if operational queries demonstrate a need for it.

Do not store Atlas per-point correlations or the full request/response payload.

### `map_matching_data` shape

The JSON schema remains internal and versioned. Its initial shape is:

```json
{
  "schema_version": 1,
  "policy_version": 1,
  "provider": {
    "name": "atlas",
    "version": "...",
    "revision": "..."
  },
  "segments": [
    {
      "transportation_mode": "cycling",
      "atlas_mode": "bicycle",
      "result": "accepted",
      "point_count": 412,
      "stats": {
        "matched": 400,
        "interpolated": 10,
        "unmatched": 2,
        "mean_distance": 4.2,
        "p95_distance": 12.8,
        "max_distance": 31.0,
        "confidence_score": 0.91,
        "raw_score": 123.4
      }
    }
  ],
  "error": null
}
```

Errors contain a normalized code, HTTP status when present, attempt count, and a sanitized message. They never contain coordinates, request bodies, response geometry, or raw upstream bodies.

## State machine

```text
nil ──eligible input──> pending
                         │
                         ├── all portions accepted ─────────> matched
                         ├── accepted + fallback portions ──> partial
                         ├── no result passes policy ────────> rejected
                         ├── no eligible portions ───────────> skipped
                         └── transient retries exhausted ────> failed

matched/partial/rejected/skipped/failed
    └── input or mode changes ──> pending
```

When a Track becomes pending, an older `matched_path` may remain stored temporarily but is not displayable. Updating the digest and status before enqueueing prevents stale geometry from leaking while avoiding an eager destructive clear.

Turning map matching off does not mutate these fields. It changes rendering and makes queued jobs no-op when they re-check configuration.

## Input fingerprint

The digest must represent the exact logical request, not only `original_path`, because timestamps, accuracy, segment boundaries, and modes affect Atlas output.

Hash a deterministic serialization of:

- ordered non-anomaly Point coordinates, timestamps, and accuracy;
- Transportation Segments ordered by source position;
- each segment's boundaries and transportation mode;
- request-shaping parameters that affect geometry.

Do not include Quality Policy version: an existing result can usually be re-evaluated without calling Atlas again. Store that version in diagnostics instead.

## Instance settings and deployment

Register:

- `atlas_url`, pinned by `ATLAS_URL` when present;
- `map_matching_enabled`, pinned by `MAP_MATCHING_ENABLED`, default `false`.

Add a Map matching section to the existing self-hosted admin Instance settings page. It contains:

- Atlas URL;
- global enable switch;
- `Test connection` action;
- Atlas health/version status;
- an interactive MapLibre example using a 2.6 km route through central Berlin,
  with an Original/Matched switch that keeps the recorded GPS drift visible as
  context in the matched state;
- disclosure that coordinates, timestamps, and accuracy are sent to the configured Atlas service.

URL requirements:

- HTTP or HTTPS only;
- private addresses are allowed intentionally;
- embedded credentials and redirects are rejected;
- host resolution is pinned for each request, following the hardened Trek client pattern;
- a missing URL blocks enabling;
- failed health does not block saving or enabling, but produces a clear warning.

Production pins the ChibiGeo URL through environment configuration. Atlas remains inaccessible directly from the public internet.

## Flipper rollout

Register `map_matching_shadow_mode`, default `false`. Operations enables it explicitly while calibrating production.

```text
process jobs = map_matching_enabled

display matched geometry =
  map_matching_enabled
  AND NOT map_matching_shadow_mode
  AND status IN (matched, partial)
  AND result is current
```

Shadow mode stores paths and diagnostics but every user continues to see Original Path.

## Transportation mode mapping

| Dawarich mode | Atlas mode | Behavior |
| --- | --- | --- |
| walking, running | `pedestrian` | Match |
| cycling | `bicycle` | Match |
| driving, bus, motorcycle | `auto` | Match |
| stationary, train, flying, boat, nil | — | Preserve original portion |

Use `shape_match=map_snap`, `format=geojson`, and `include_directions=false`. Send `time` and `accuracy` for every Point where available. Do not expose search radius, breakage distance, or other Atlas tuning in the UI.

## Atlas client

Create an isolated client responsible for:

- `GET /api/v1/health`;
- `GET /api/v1/version`;
- `POST /api/v1/map-match`;
- URL validation and pinned resolution;
- JSON validation and normalized typed errors;
- open/read timeouts longer than Atlas's configured 60-second match timeout;
- never logging request or response bodies.

Error classes must preserve enough information for job policy:

- 400/422: terminal input or unmatchable result;
- 429: capacity exhaustion, honor `Retry-After`;
- 502/503, connection errors, and timeouts: transient;
- malformed successful responses: provider failure, retry with a finite limit.

## Processing flow

```text
TrackBuilder / Recalculator / Transportation Reprocessor
                         │
                         ▼
         Tracks::MapMatching::Enqueuer
        setting • demo • modes • digest • dedupe
                         │
                         ▼
              Tracks::MapMatchJob
          re-check setting and current digest
                         │
             one Atlas request per eligible
               Transportation Segment
                         │
              QualityPolicy per segment
                         │
      compose ordered MultiLineString with original
         fallbacks for unsupported/rejected parts
                         │
       conditional Track update if digest is current
                         │
           tile epoch bump + map broadcast
```

Use a shared `Tracks::MapMatching::Enqueuer` from explicit successful completion points rather than callbacks. It must cover normal construction, recalculation, transportation reprocessing, relevant merge/attachment flows, and restored Tracks. Demo Tracks are skipped.

The enqueuer:

1. exits when the instance feature is off or Atlas URL is absent;
2. computes the input digest;
3. exits when an accepted current result already exists;
4. atomically changes the Track to `pending` with the new digest;
5. deduplicates and enqueues by Track ID and digest.

The job receives both values, reloads the Track, and exits unless the setting and digest still match. Before publishing, it performs the same check in a transaction or conditional update so an older HTTP response cannot overwrite a newer edit.

## Composition

- Process Transportation Segments in source order.
- Normalize every Atlas `LineString` to a one-part `MultiLineString` and preserve returned multi-part geometry.
- Use original segment geometry for unsupported, rejected, over-limit, or terminally unmatchable portions.
- Do not draw synthetic connectors between parts.
- `matched` means every Track portion was accepted by matching.
- `partial` means at least one portion was accepted and at least one portion used original geometry.
- `rejected` means eligible requests completed but none passed policy.
- `skipped` means the Track had no eligible portion.

A segment above 10,000 input Points is rejected with reason `too_many_points` in the MVP. Chunking is deferred.

## Queue and retry policy

Add a dedicated `map_matching` queue with a `sidekiq-limit_fetch` cap controlled by `MAP_MATCHING_CONCURRENCY`, default `2`.

- Retry timeout, 429, 502, 503, connection, and malformed-provider failures with exponential backoff.
- Honor `Retry-After` where available.
- Stop after five attempts and mark `failed` if the Track and digest remain current.
- Treat 400/422 as terminal for that segment, allowing the Track to become `partial` or `rejected`.
- Discard missing Tracks and superseded digests without changing newer state.

## Quality Policy

Implement a versioned `MapMatching::QualityPolicy` that returns an acceptance decision plus machine-readable reasons for one segment.

Inputs include:

- valid non-empty geometry;
- matched/interpolated/unmatched coverage;
- mean/p95/max displacement;
- Atlas confidence/raw score when present;
- input and output segment counts.

The policy must not treat Atlas confidence as guaranteed to be normalized or present. Initial numeric thresholds are set only after shadow-mode calibration on real walking, cycling, and automotive Tracks.

When policy version changes:

1. re-evaluate saved aggregate diagnostics where sufficient;
2. enqueue a fresh Atlas request only when required inputs were not retained;
3. update status/path publication under the normal digest guard.

## Rendering and API

### Display path

Centralize geometry selection so vector tiles and the selected-Track endpoint cannot disagree:

```text
Matched Path when visible, current, and status is matched/partial;
otherwise Original Path.
```

The MVT spatial predicate must branch between indexed `matched_path` and `original_path` conditions instead of wrapping both in an unindexed `COALESCE` expression. Add the visible map-matching state to the tile cache schema/ETag, and bump the Track tile epoch whenever publication changes between original and matched geometry.

### Public Track API

The existing default response remains Original Path. Explicit variants:

- `geometry=original` — existing behavior and default;
- `geometry=display` — geometry currently used by the main map;
- `geometry=matched` — current Matched Path or `null`;
- `geometry=compare` — explicit response containing both Original and Matched geometry plus status.

Do not place the second full geometry in MVT properties.

### UI

- The ordinary Timeline remains visually unchanged until a Track is selected.
- `pending`: “Improving route…” in selected Track details.
- `matched`: quiet “Matched to roads” status.
- `partial`: “Partially matched” with fallback explanation in details.
- `rejected`, `failed`, `skipped`, feature off, or stale: show original geometry; technical details remain admin/log-only.
- Original / Matched / Compare changes only the selected rendering layer and is not stored as a preference.

## Original-only surfaces in the MVP

- speed-colored tiles;
- import-filtered geometry;
- Transportation Segment overlays;
- shared maps;
- Trips;
- Replay;
- Posters;
- statistics and Timeline metrics;
- exports and restore payloads.

## Privacy and observability

Never emit coordinates, timestamps, accuracy, request bodies, response geometry, or raw provider responses to application logs, metrics labels, or error reporting.

Record aggregate telemetry only:

- enqueued/completed/rejected/skipped/failed counts by mode and reason;
- request duration and point count;
- accepted/partial rates;
- aggregate displacement summaries;
- Atlas HTTP/error code;
- queue depth and latency.

Structured logs may include Track ID, digest prefix, mode, attempt, duration, point count, state, and sanitized error code.

## Migration and performance

- Add all columns nullable except `map_matching_data`, which defaults to `{}`.
- Add the GiST index without blocking writes on large installations.
- Do not backfill existing Tracks in the migration.
- Existing records begin with `map_matching_status = NULL`.
- Enabling the feature affects only newly created or subsequently recalculated/reclassified Tracks.
- A separate manual period backfill is a later iteration.

## Test strategy

### Unit

- mode mapping and unsupported modes;
- deterministic fingerprinting and changes caused by coordinates, time, accuracy, boundaries, or mode;
- Quality Policy decisions and versioning;
- URL validation, health/version parsing, payload construction, and sanitized errors;
- composition ordering and preservation of discontinuities.

### Job and service

- feature off, missing URL, demo, duplicate, and current-result exits;
- successful matched and partial results;
- terminal segment rejection;
- retryable Atlas errors and exhausted retries;
- digest change during HTTP request cannot publish stale geometry;
- turning the feature off makes queued jobs no-op;
- oversized segment fallback.

### Database and rendering

- MultiLineString persistence and GiST query behavior;
- MVT uses Matched Path only under valid visible conditions;
- default API remains Original Path;
- explicit display/matched/compare variants;
- tile epoch and cache-key invalidation when result or feature visibility changes;
- original-only special modes remain unchanged.

### UI/system

- configure/test/enable Atlas from Instance settings;
- missing URL validation and unhealthy warning;
- visual example and privacy disclosure;
- selected Track pending/matched/partial/fallback states;
- Original / Matched / Compare interaction;
- global off immediately returns the map to Original Path.

## Rollout

1. Deploy schema, settings, client, job pipeline, and observability with map matching off.
2. Configure the private ChibiGeo Atlas URL in production.
3. Enable `map_matching_shadow_mode` in Flipper, then enable the instance setting.
4. Process new/recalculated Tracks and review a representative sample for each supported Atlas mode.
5. Fix the first Quality Policy version and verify latency, rejection, failure, and Atlas capacity.
6. Disable shadow mode for a limited production cohort or time window.
7. Enable normal display after the release gates in ADR-0018 pass.
8. Design manual backfill, additional visual surfaces, chunking, and BRouter as subsequent iterations.

## Proposed pull-request sequence

### PR 1 — Persistence and instance configuration

- migration and Track validations/helpers;
- InstanceSettings keys and predicates;
- Instance settings section, visual example, test-connection endpoint;
- Flipper flag registration;
- glossary/ADR/RFC documentation.

### PR 2 — Atlas client and policy foundation

- hardened Atlas client;
- request/response value objects and typed errors;
- mode mapper, fingerprint builder, composer, and Quality Policy interface;
- unit tests with representative LineString and MultiLineString fixtures.

### PR 3 — Background processing

- Enqueuer and explicit completion hooks;
- dedicated queue/concurrency configuration;
- idempotent job, retries, conditional publication, metrics, and tile invalidation;
- shadow-mode persistence.

### PR 4 — Rendering and UX

- indexed Displayed Path selection in MVT;
- explicit Track geometry API variants;
- selected-Track statuses and Original / Matched / Compare;
- cache-key changes and JS/request/system tests.

### PR 5 — Calibration and release

- diagnostic sampling/report task;
- first calibrated Quality Policy thresholds;
- production runbook and rollout verification;
- removal of any temporary calibration-only code that is no longer needed.

## Definition of done

- All invariants and ADRs are reflected in code and tests.
- Existing API and original-only visual surfaces remain backward compatible.
- No stale result can win a race against an edited Track.
- No sensitive Atlas payload appears in logs, metrics, or error reporting.
- Global off and shadow mode both reliably render Original Path.
- Atlas failures never prevent the map from displaying the recorded route.
- The main Map/Timeline can render, inspect, and compare an accepted Matched Path.

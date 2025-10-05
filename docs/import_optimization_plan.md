# Import Optimisation Plan

## Goals
- Prevent large imports from exhausting memory or hitting IO limits while reading export archives.
- Maintain correctness and ordering guarantees for all imported entities.
- Preserve observability and operability (clear errors and actionable logs).

## Current Status
- ✅ Replaced `File.read + JSON.parse` with streaming via `Oj::Parser(:saj).load`, so `data.json` is consumed in 16KB chunks instead of loading the whole file.
- ✅ `Users::ImportData` now dispatches streamed payloads section-by-section, buffering `places` in-memory batches and spilling `visits`/`points` to NDJSON for replay after dependencies are ready.
- ✅ Points, places, and visits importers support incremental ingestion with a fixed batch size of 1,000 records and detailed progress logs.
- ✅ Added targeted specs for the SAJ handler and streaming flow; addressed IO retry messaging.
- ⚙️ Pending: archive-size guardrails, broader telemetry, and production rollout validation.

## Remaining Pain Points
- No preflight check yet for extreme `data.json` sizes or malformed streams.
- Logging only (no metrics/dashboards) for monitoring batch throughput and failures.

## Next Steps
1. **Rollout & Hardening**
   - Add size/structure validation before streaming (fail fast with actionable error).
   - Extend log coverage (import durations, batch counts) and document operator playbook.
   - Capture memory/runtime snapshots during large staged imports.
2. **Post-Rollout Validation**
   - Re-run the previously failing Sidekiq job (import 105) under the new pipeline.
   - Monitor Sidekiq memory and throughput; tune batch size if needed.
   - Gather feedback and decide on export format split or further streaming tweaks.

## Validation Strategy
- Automated: streaming parser specs, importer batch tests, service integration spec (already in place; expand as new safeguards land).
- Manual: stage large imports, inspect Sidekiq logs/metrics once added, confirm notifications, stats, and files restored.

## Open Questions
- What thresholds should trigger preflight failures or warnings (file size, record counts)?
- Do we need structured metrics beyond logs for long-running imports?
- Should we pursue export format splitting or incremental resume once streaming rollout is stable?

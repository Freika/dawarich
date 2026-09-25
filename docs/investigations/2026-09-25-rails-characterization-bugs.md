# Rails defects found during Phoenix characterization and C2

Date: 2026-09-25. Base: local `dev` at `f73605cb9`. Each fix is on its own local branch; none has been pushed or merged.

| Defect | Cause | Rails repair |
|---|---|---|
| `/stats/:year/:month` returns 500 without a stat | The month partial dereferences a missing `Stat`. | Render the existing localized empty state when the stat is absent. |
| Preheating creates an unfinished yearly digest | `Cache::PreheatInsightsDigests` selects the current year. | Select completed years; hide already persisted current-year digests from the web and API lists. |
| Release 1.0.2 transportation backfill enqueues nothing | Migration `20260125100000` references the removed `TransportationModes::BackfillJob` and filters integer `imports.source` against text values. | Keep released history intact. A new migration queues a batched walker for tracks missing segments or having an unknown mode, and queues import backfills using the five integer enum values. The new walker excludes deleted users and uses the current `ReclassifyTrackJob`. It does not invoke the fleet-wide job reserved for a manual post-anchor run. |
| Track-split defaults disagree | The `users.settings` column still defaults to 1000 m and 60 min while SafeSettings and the map panel use 500 m and 30 min. | A new migration changes the column default for new users; existing saved settings remain untouched. |
| Map “Reset to defaults” can lose its save and retain miles | The controller reloads before the asynchronous save finishes, and the reset payload lacks `distance_unit`. | Queue the reset after earlier saves, await it before reload, and explicitly reset distance and nested map filters. |
| Manual image build publishes `latest` | `workflow_dispatch` has no prerelease flag and takes the stable-release tag branch. | Add `latest` only for release events. |

## Ecto port consequence

C2 ports current Rails behavior, including the released 1.0.2 migration's absent backfill. Do not edit or reinterpret that migration in the Ecto port. C2 needs counterparts for the new repair and track-split default migrations after these Rails branches enter the integration branch. C3 must port the repair's job chain; C4 should verify a 1.0.1 snapshot through both migrators with row-level checks after the jobs complete. Neither change belongs in C2's owned worktree during this handoff.

The two migration branches both change `db/schema.rb`. When combined, regenerate it at version `2026_09_25_100100` with the `500`/`30` column default.

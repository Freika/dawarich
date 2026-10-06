# Trips native closure

Package T adds the native standalone trip journey to the existing read models, web commands and LiveViews. Source parity remains the contract, including Rails bugs. Per-key Sidekiq ownership remains a coexistence fence; this package does not activate global registry entries.

## Implemented journey

Trip index/new/edit render in self-hosted, explicit Cloud and unset-default modes. Trip show retains future itinerary and studio rendering. Missing scoped trips terminate with 404. In standalone mode domain refusals terminate with an error instead of requiring an absent Rails web process; configured coexistence upstreams keep their existing admission behavior.

Show calculation admits the existing `command:trips.calculate` Oban producer in Cloud mode. Future imported trips bypass calculation. Name-only updates do not enqueue another calculation. Invalid Turbo create preserves the Rails MissingTemplate status of 500 without writing a trip. Existing cooldown, concurrency, owner fencing, completion and rollback tests remain in place.

`Trips.Photos.load(user, started_at, ended_at, zone)` consumes the existing `Photos.Index.fetch/3` result/cache contract. It groups provider timestamps in the user timezone, preserves source ordering, chooses up to twelve previews from the dominant orientation and builds source browser links. The show and day components render the thumbnail links; the existing Stimulus photo toggle remains the map consumer.

`Trips.RichContent` retains the strict legacy `TripDescription` parser and adds a separate bounded ActionText path. The captured description corpus renders byte-identically, including HTML repairs, source sanitizer behavior, Trix external image attachments, entities and void tags. Create/update store canonical attachment markup; dependent deletion handles rich texts without blob attachments. Notes preserve leading newlines, local-noon upserts, actor/trip scope and plain-text HTML escaping. Named-month dates now follow the existing native DateParts parser. Exports use the existing locale approximations and the trip's local start date.

## Native producer contracts

`Trips.ShowCalculation.run(repo, user, id, context)` calls `Trips.WebCommands.calculate!` with actor-scoped trip, units and source clock. It persists a UUID/version-1 `trips.calculate` command, aggregate/dedupe identity and scheduled time under the existing owner lock. No native path publishes a `trips.calculate` reverse effect. Accepted-work completion remains with the existing calculation worker and shared owner APIs.

Trip export calls the existing PointExports producer under `command:exports.points`, using the scoped actor, format, original UTC bounds and source filename. The exporter owns worker completion and blob attachment. No exporter codecs or storage primitives changed here.

## Source capture and verification

O source captures were not yet merged. The existing trips and description generators were extended in this worktree to write `test/fixtures/trips/a12f3a-t01.json` through `a12f3a-t10.json`. Two recording passes were byte-identical. A later named-month note case was appended, preserving earlier fixture identities; another two passes were byte-identical. The prepended CloudDrain client required fault injection to wrap constructed Sidekiq clients instead of an unsupported any-instance stub.

New selectors T01/T02/T03/T04/T05/T06/T08/T10 were RED before implementation; each named production mutation failed and restored checks passed. Existing T07 cooldown and T09 scope tests were reconciled rather than inventing a new initial RED. Their named mutations failed at the exact cooldown and foreign-note assertions. Detailed counts, logs and final gates are in the controller-assigned execution report.

## Open parity variants and integration handoff

This is the ruling-15 native journey cut, not complete package or Ruby-free release acceptance. T04 blob/SGID attachables and ActiveStorage dependent purge/analyze attachment graphs remain refused with existing content retained. Arbitrary non-image embeds and complete sanitizer/storage capability parity remain open under NE-6; no content deletion or product-scope reduction is authorized. T09 trip notes are plain-text Rails columns; merged visit rich notes remain package V's responsibility.

T01/T02/T05/T08/T10 still need the complete plan envelope tables beyond the captured/common journey, including inactive-account redirects, malformed envelopes, legacy coercions, locales and detailed error payloads. DateParts covers named-month dates but is not claimed to implement all Ruby Date.parse inputs. Uncharacterized settings and mixed-owner plan graphs remain refused. T07/T09 aggregate named selectors were not added because equivalent existing tests were already green; a controller reconciliation is needed before marking those plan tasks complete.

O06–O08 own route and source-capture reconciliation. The shared public `TripsGate.open?/2` remains strict for its Map/Places callers; only private trip route admission permits native standalone terminal errors. Existing O02 dispatch and A8 remaining-corpus tests were reconciled with native Cloud writes, embedded descriptions and configured photos while preserving shared transport/refusal checks. These two additional compatibility test files need O reconciliation. Minimal reachability changes here are domain preflight/action admission only; no shared route, global parser, registry or expected-diff file changed. `components/trip_days_list.ex` is the sole additional UI seam needed for day photos. O should reconcile generator additions, appended fixture IDs and the native terminal-error branches. The integration seed, browser, stand/image and release acceptance remain controller work.

## Verified gate

Implementation head `55d77ff29`: required seed-404 controller runner completed all three partitions with 8,696 tests and zero failures. Partitions: 2,768 / 2,925 / 3,003 tests; existing 11 exclusions and 3 skips unchanged, no invalid cases. Forced compilation with warnings-as-errors, format check, 81 scoped Rails examples, changed-generator RuboCop and four-commit gitleaks scan passed. The trip target batch passed 178 tests before the scoped admission correction; the correction passed 35 targeted regressions and then the full suite. No test retries, additional skips or longer timeouts were introduced. Private test services stopped; schema and Swagger restored.

These gates validate the committed native journey and existing compatibility coverage. The open variants above remain unclosed, so full package T acceptance is not claimed. AFFiNE counterpart: `Dawarich — Phoenix trips native journey implementation (A12f-3a T)` (`JDyxiASamTer-5opLQFby`).

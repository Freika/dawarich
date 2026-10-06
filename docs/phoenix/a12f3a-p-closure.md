# A12f-3a P: native places, providers and maintenance commands

Implementation cut, 2026-10-06. Plan C P01–P10, NE-3 retained, controller rulings
13–15. The Rails 1.15.3 source and existing A8/A12d2/A12e implementations remain
available for coexistence and source drain. This cut does not activate job keys,
remove Rails, or declare release acceptance.

## Native user journey

The existing places list, drawer, create, update, adoption, tag and dependent
removal services remain the domain implementations. Standalone drawer requests
for missing or foreign places return scoped native 404s. The domain write gate
admits standalone Cloud requests using the existing authentication, CSRF and
form parser. It does not widen the shared transport parser.

Configured nearby HTML calls `Dawarich.Places.Nearby.fetch/6`. It preserves Ruby
numeric prefix coercion, defaults (0.5 km, five results for HTML), provider result
order, source formatting, escaping and the radius expansion control. Disabled
providers and the zero location return empty results without a lookup. The
existing API nearby/search implementation is reused for result formatting; API
routes remain with A12f-2B.

`Geocoding.Search.nearby/3` uses the existing provider query, HTTP response cache
and result decoder, with the source interactive reservation budget of one
second. The background `reverse/3` contract is unchanged. Optional nearby result
caching uses the native TTL cache, a SHA-256 config digest, four-digit coordinate
grid, radius and limit, one-hour TTL and skip-nil behavior. Handled provider
failures produce empty results with redacted diagnostics. Configuration and
rate-limit failures are reported without provider URL, key or coordinates.

## CLI and aliases

All commands accept no arguments and reject extra arguments before writes:

| Native command | Legacy spelling | Result |
|---|---|---|
| `dawarich places backfill-names` | `dawarich:backfill_place_names` | One bulk-name command |
| `dawarich places cleanup-suggested` | `dawarich:cleanup_suggested_places` | One cleanup command per non-deleted user |
| `dawarich places orphan-count` | None | Integer and newline; zero means source drain count is empty |

Empty legacy brackets are safe aliases too; nonempty brackets and trailing
arguments fail. Enqueue commands emit no stdout/stderr on success, matching the
source task output with logging excluded. Failures return exit 1 through the
existing CLI error handler. The drain remedy is `dawarich places orphan-count`.

Cleanup uses ID-range batches of 100, the source unordered pluck within each
batch, and cumulative 0.1-second spacing across batch boundaries. Every accepted
publication gets a distinct event UUID. Repeated invocation intentionally
publishes again, as the source does. Orphan count preserves the exact source
`where.missing(:visits, :taggings)` predicate: tombstoned and declined visits
still exclude a place from this count, unlike worker active-visit eligibility.

## Owner and caller handoff

| Caller | Contract | Native result / key | Identity and due time |
|---|---|---|---|
| Web/ingest callers | `Places.JobCommands.name_fetch(repo,user,place)` | `places.name_fetch`, `command:places.name_fetch` | Scoped place/user; fresh event UUID; current due time |
| Visit/ingest callers | `orphan_places(repo,user,ids)` | `places.delete_if_orphan`, matching command key | Unique scoped IDs; one event per place |
| CLI cleanup | `orphan_cleanup(repo,user,scheduled_at \\ nil)` | `places.orphan_cleanup`, matching command key | User aggregate; supplied UTC due time retained |
| CLI backfill | `bulk_name_fetch(repo)` | `places.bulk_name_fetch`, matching command key | Empty payload, nil aggregate; fresh event UUID |

Each producer takes the existing persisted owner lock inside its publication
transaction. Oban-owned commands enter `public.job_outbox`, version 1, producer
`phoenix.places`; they create no reverse Rails command. Sidekiq pins retain the
existing reverse kinds. Cleanup adds optional `scheduled_at` only to the reverse
payload. `Places::JobCommands.reverse_user` consumes it and republishes with the
same due time; old payloads keep their previous current-time behavior. Existing
typed worker decoders, event fences, accepted leases and source drain owners are
unchanged. Source/native job entries remain unclaimable pending the sibling
payload/cron/registry readiness work. No new registry or ownership framework.

## Source evidence and task reconciliation

The base already covers supported list/drawer, writes, dependent deletion and
native producer/worker paths. P05 and P06 use their existing named tests and the
assigned production mutations; no new initial RED is claimed for those inherited
implementations. P01/P02/P03/P04/P07/P08/P09/P10 add aggregate tests with actual
missing-behavior RED, GREEN, assigned mutation failure, restored GREEN.

O03 captures were not merged at this base. Under the execution brief's explicit
exception, package P extended the existing `places_fixtures_spec.rb` generator
with `places_closure_capture.rb` and wrote the exact `a12f3a-p01.json` through
`a12f3a-p10.json` paths. It reuses the generator's clock, synthetic IDs, scrubber
and normalized JSON; it adds no independent corpus driver or named generator
test. Old fixture bytes remain unchanged. The controller's O08 source refresh
should retain these cases, including nearby HTML/coercion/cache, producer
payloads, CLI scheduling, and the conservative orphan count.

Additional source seam evidence: the existing Rails job-command spec fails when
cleanup due time is dropped, passes with the seam, fails under the due-time
mutation and passes after restoration. Swagger and schema are restored after
source batches. Exact run counts and mutation assertions live in the assigned
execution report. The branch gate uses seed 404; controller runs seed 202 after
integration.

## Integration and deferred envelopes

No router or shared parser edit is needed: existing routes already point at the
extracted Places request gates and native navigation. The minimal extra seam is
the existing `NearbyPlaces` component, extended to render nonempty cards.
Existing navigation/corpus tests now distinguish native nearby results from the
historical hand-back and supplementary source captures from the original corpus.

Ruling 15's edge-envelope work remains explicit: malformed stored settings or
geometry, unsupported form/format shapes, and rich-text/storage dependent
deletions preserve safe terminal errors in standalone mode; exact source wire
parity for those rare envelopes remains follow-up work. Coexistence retains
pre-effect hand-back for its previously unsupported forms. Global HEAD, parser,
format constraints, route activation and source-free cut-over belong to O and
A12f-2. Do not interpret these unit gates as retirement of cache jobs or activation
of native producers. Real browser/stand/image/G42–49 and final physical source
removal remain controller release work.

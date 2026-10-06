# Import codecs, continuations and extraction

Last updated: 2026-10-06. Branch: feat/a12f3a-f. This is the standalone
priority cut; complete package F closure remains open.

## Implemented contracts

Common point codecs from A7 remain native: CSV, Google Records, Semantic
History, Phone Takeout, GeoJSON, KML, OwnTracks and GPX. The inherited codec
baseline passes 160 tests. Integration regression now passes 1,432 tests with
seed 404 across import/extraction/ingest directories, HTTP ingestion goldens,
F and RX closure tests, and endpoint/map neighbours. This covers the earlier
508-test F regression.

Standalone preparation returns native errors for unsupported storage and
unsafe archives. Coexistence retains source handback. The F01 aggregate tests
dispatch and rejected preparation with a real executing import lease, without
points, reverse commands or handoffs. Its complete transport envelope is open.

`NormalResume.driver(lease, state, context)` establishes or validates the
existing import-run attachment receipt and adds `resume_lease` and
`resume_offset` to the codec context. `GpxResume` uses that contract with its
explicit attachment predicate. `start!` preserves counters on retry;
`source!` validates the detected normal source. The receipt contains the
attachment snapshot, source and committed prepared-row cursor. No migration
or general admission framework was introduced.

`NormalResume.batch(context, offset, size, fun)` commits the writer and cursor
advance together under the existing event, job, attempt, actor and token fence.
`NormalBatch`, GPX and Semantic History skip previously committed prepared
rows. Atomic Phone Takeout and GeoJSON retain whole-import rollback. Tests
interrupt a real batch and resume 1001 points without duplicates. Changed GPX
blob identity rejects resume. Semantic History retains Rails' zero raw_points
quirk. These tests prove the batch contract, not complete worker admission or
all terminal/owner-change phases.

Standalone progress publishes through existing native PubSub. Shared lifecycle
and progress changes now retain RX-IMPORTS' native admission and effect
publication alongside the fenced codec receipt. `LeaseLost` escapes before
lifecycle completion, preserving the committed cursor and processing status.
Normal terminal publication uses one native event after the terminal
transaction, matching GPX, while coexistence keeps its fenced source command.

`Postprocessing.Commands` and `Postprocessing.Native` remain the single
publication path for native month stats, achievement checks, calendar visit
suggestions, track ranges, point counters and GPX extraction. RX-IMPORTS'
upload, purge, extraction removal and destruction effects are retained.
Unsupported native extraction sources keep their explicit native error;
the later F18 follow-up below supplies the non-GPX worker dispatcher.

The merged lifecycle regression interrupts actual GPX and CSV imports after
1000 committed points, rejects changed attachment identity, resumes to 1001
points, and retries a failed terminal marker. It proves counters, saved cursor,
replay-stable native followups and one terminal progress event. Mutations of
completion, cursor reuse, native stats and terminal publication fail its named
assertions; each restored version passes.

F23–F26 expose `reduce(path, import, context, acc, fun)` on
`SemanticAdapter`, `PhoneAdapter`, `RecordsAdapter` and `PolarstepsAdapter`.
The callback receives string-keyed extracted visit/track rows matching the
Rails translator records. Context contains captured zone and clock. GPX
retains its existing place stream. These adapters do not persist children or
claim complete extraction orchestration.

| Adapter | Complete captured table | Preserved behavior |
| --- | ---: | --- |
| Semantic History | 21 cases | Visit confidence, activity end/duration, place identity and segment order |
| Phone Takeout | 44 cases | Semantic segments and frequent places; raw signals ignored |
| Records | 20 cases | No extracted rows, including malformed input |
| Polarsteps | 18 cases | Step visits; location trails yield no visits |

The source generator serializes nested Ruby Data objects by fields.
F23/F24/F26 captures were written twice and byte-compared. Integration keeps
all structured cases and adopts the source-packet isolation and minification
under `app-phoenix/test/fixtures/a12f3a_source/`. Legacy aggregates retain their
values; producer-prefixed source packets supersede the old alias writer.
Current Rails assertion mode passes 34 examples against the merged packets.
No Rails production interface was removed.

KML's prepared spool uses bounded 64 KiB buffering to avoid per-point writes.
The existing interpolation regression passes in 5.1 seconds with its original
60-second deadline. No host load generator or timeout increase was used.

## TDD and mutation evidence

Each new named aggregate has recorded initial RED, GREEN, mutation RED and
restored GREEN. F23–F26 compare complete captured row tables and native errors.
F01, F15 and F16 use real import-run receipts, executing Oban rows and fences.

| Task | Mutation that fails the named test |
| --- | --- |
| F01 | Dispatch CSV as GeoJSON |
| F15 | Accept a changed captured attachment |
| F16 | Resume from zero instead of the committed offset |
| F23 | Omit activity end |
| F24 | Emit raw signals as visits |
| F25 | Emit an accuracy-derived row instead of the source no-op |
| F26 | Swap latitude and longitude |

F25's planned accuracy/place mutation conflicts with Rails 1.15.3's no-op.
The reconciled mutation tests that no-op directly. Inherited F02–F14 and
F20–F22 have regression GREEN; their planned new aggregate/mutation closure
has not been claimed.

## Final gates

Forced compilation with warnings as errors (1,608 files), whole-tree format
checking, 34 targeted Rails examples and RuboCop pass. The required controller
runner completes seed 404 with 8,934 tests and zero failures. Existing skips
and exclusions are unchanged. No timeout increase or skipped assertion was
introduced; Swagger and schema remain unchanged.

The initial import merge at integration head `8adb5890f` passed 1,332 targeted
tests but exposed an inherited absent-versus-nil authentication configuration
cleanup leak in the full suite. Integration was refreshed through `851c5b31b`,
including the upstream `c526bdedd` repair. Its endpoint/map checks and final
full gate pass. The source-packet conflicts in that refresh retained F's
structured place/segment records instead of inspection strings.

## Integration handoff and remaining work

RX-IMPORTS owns native lease admission and downstream effect publication.
Package I owns the HTTP upload/manual-extraction path. Package O owns Registry
readiness and final wiring. Keep shared entries inert until integration proof;
this branch does not advertise a Rails-free end-to-end HTTP worker journey.

The original priority cut left F17–F19 open. The follow-up sections below
record their gap audit and completed native continuation, extraction, and
postprocessing work, reusing RX-IMPORTS and the existing Q/P/W/V APIs.
Complete F01/F15/F16 edge envelopes also remain open. These are unfinished
tasks, not successful source drain or retirement evidence.

Legacy Google Takeout and resume class interfaces remain intact under NE-4.
Accepted old source work and serialized payload disposition stay with the
source drain owner and sibling row21/A12f-3c. No drain or release readiness is
claimed here.

AFFiNE counterpart: Dawarich — Phoenix import codecs and extraction closure
(docId: ovFWRqfzsy2Jb5n1NB4Qc).

## F17 follow-up audit and continuation

The F17–F19 follow-up audits the merged F/RX implementations before adding
missing behavior. F17 now accepts a typed native `continuation` containing
`locations` objects and a nonnegative `current_index` on ProcessWorker's
existing import command. It uses the existing fenced writer and receipt,
with a digest of the complete continuation as its captured identity. Replay
skips committed source-array rows; changed payloads lose the fence. Progress
retains Rails' constant `current_index` for the supplied locations batch.
Serialized Sidekiq payloads remain with the source drain owner.

The named F17 selector initially fails on the absent adapter, passes after
implementation, fails when the committed cursor advances twice, and passes
after restoration. Retained Rails characterization passes 34 examples.

## F18 native extraction follow-up

The existing GPX extractor is retained. `EnhancedImport.Adapters` dispatches
Phone, Semantic History, Records' source no-op, Polarsteps and GPX streams.
`NormalWorker` runs supported non-GPX extraction under the shared import and
per-user track locks. Every write checks the executing attempt, actor, source,
attachment, extraction event/action, and current ownership. Existing State
writes accept that fence; deadline cancellation, bounded lock waiting and
retry status follow the retained source behavior.

The existing PlaceWriter supports Photon source for non-GPX rows and retains
GPX waypoint adoption. Native item/track/segment writers reuse the track
builder and geometry/transportation APIs. Visits deduplicate by owner, place
and start; tracks preserve device separation and adopt an already generated
track. Source segments clip around corrected or higher-priority segments.
Trust disabled resets source segments and uses inference. Extraction removal
reuses RX's fenced worker and DestroyExtraction, retaining raw points and
adopted tracks while resetting extraction state.

Manual non-GPX admission is a small extension of ManualExtraction's existing
producer. Source-owned coexistence still publishes its retained source
command; native selected work uses the new direct child worker. Shared job
registry/readiness entries are unchanged. Records intentionally remains
unavailable for manual extraction, matching Translator.supported?.

F18's named test fails first on unsupported manual extraction, passes native
persistence/destroy/retry/fence cases, fails the Phone-as-GPX mutation, and
passes after restoration. The extraction/GPX/R09 regression passes 46 tests.

## F19 postprocessing follow-up

Postprocessing retains RX's single native publication path and source step
order. The missing automatic non-GPX extraction handoff now calls
`NormalWorker.enqueue!(repo, import, context)`. It captures actor/source/blob,
locale and zone, derives the child UUID from the existing import event and
payload, and preserves it across terminal replay. No new effect framework or
reverse consumer is introduced.

The named aggregate verifies both zone-local months, native stats/achievement/
visit/count/extraction publication, extraction suppressing generic track
ranges, stable child args on replay, all-skipped localization, a real failed
count update with later effects retained, parser failure without followups,
and deletion with affected-month stats and terminal replay. It runs in
self-hosted, explicit Cloud and unset default modes. Dropping the last stats
month fails the exact December/January assertion; restored code passes.

### Caller contracts and ownership handoff

| Caller | Callee / contract | Event, fence and source owner |
| --- | --- | --- |
| ProcessWorker typed continuation | GoogleTakeoutResume.call(lease, state, context, payload) | Existing process_normal import event/attempt/token; constant Rails progress index; old serialized work stays with source drain |
| ManualExtraction native non-GPX | NormalWorker.enqueue!(repo, args, event, at) | Existing extraction event/action and actor/source/blob; queued on existing extraction lane |
| Postprocessing.Native extract | NormalWorker.enqueue!(repo, import, context) | Stable child of import-run UUID; captured locale/zone and clock; executes after import completion |
| NormalWorker | Extract.process(repo, import, storage, event, deadline, context) | Import and per-user locks; every child/status write uses the current executing-job and extraction identity fence |
| ExtractionRemovalWorker | DestroyExtraction.call(lease, source) | Existing RX removal fence; raw points survive; source labels/corrected segments retain Rails semantics |
| Native stats/visits/tracks/achievements/cache | Existing Q/V/W/P/RX owner APIs | Existing payloads, due times, and dedupe contracts unchanged |

F17–F19's missing behavior and named tests/mutations are complete in the
follow-up. This does not claim completion of other package F tasks or release,
source-drain, production claimability, deployment, or shutdown readiness.

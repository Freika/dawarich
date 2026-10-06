# Import codecs, continuations and extraction

Last updated: 2026-10-06. Branch: feat/a12f3a-f. This is the standalone
priority cut; complete package F closure remains open.

## Implemented contracts

Common point codecs from A7 remain native: CSV, Google Records, Semantic
History, Phone Takeout, GeoJSON, KML, OwnTracks and GPX. The inherited codec
baseline passes 160 tests. The final affected codec, lifecycle and worker
regression passes 508 tests with seed 404.

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
and progress changes are the minimum seam needed by these codecs; RX-IMPORTS
must reconcile them with its native admission and effect work.

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

The source generator now serializes nested Ruby Data objects by fields.
F23/F24/F26 captures were written twice and byte-compared. Source assertions
pass 34 examples. Existing package I producer aliases retain their bytes and
key order. No Rails production interface was removed.

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

Forced compilation with warnings as errors, format checking, 34 targeted
Ruby examples, Rubocop and gitleaks pass. The full seed-404 gate at the code
head runs 8860 tests with four failures. Swagger/poster dependency setup was
corrected and their two failing selectors now pass. Two inherited producer
contracts remain outside F ownership: realtime visits expects an obsolete
direct worker, and TeslaMate effects receives an incomplete test context.
The required full-suite gate remains failed; no skip or timeout was added.

## Integration handoff and remaining work

RX-IMPORTS owns native lease admission and downstream effect publication.
Package I owns the HTTP upload/manual-extraction path. Package O owns Registry
readiness and final wiring. Keep shared entries inert until integration proof;
this branch does not advertise a Rails-free end-to-end HTTP worker journey.

F17's strict native Google Takeout continuation adapter is not implemented.
F18 still needs non-GPX adapter dispatch, fenced extraction worker, durable
visit/track/segment attribution and destroy orchestration. F19 still needs
native postprocessing/effect ordering with Q/P/W/V APIs and RX-IMPORTS.
Complete F01/F15/F16 edge envelopes also remain open. These are unfinished
tasks, not successful source drain or retirement evidence.

Legacy Google Takeout and resume class interfaces remain intact under NE-4.
Accepted old source work and serialized payload disposition stay with the
source drain owner and sibling row21/A12f-3c. No drain or release readiness is
claimed here.

AFFiNE counterpart: Dawarich — Phoenix import codecs and extraction closure
(docId: ovFWRqfzsy2Jb5n1NB4Qc).

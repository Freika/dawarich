# Import codecs, continuations and extraction

Package F retains common-format native parsing from the merged A7 implementation.
The inherited targeted codec/worker baseline passes 160 tests with seed 404.
This is reconciliation evidence, not completion of every planned edge envelope.

Semantic History enhanced extraction now streams the existing JSON section
reader into typed visit and track rows, preserving source durations, Google
place identity, confidence, activity mode and segment ordering. Its F23
source-backed aggregate covers all successful captured inputs. Initial RED was
the missing native adapter; GREEN passes, omitting an activity end fails the
exact row comparison, and restored GREEN passes.

The existing Rails generator now serializes nested Ruby Data objects by fields.
The enhanced captures were written twice with identical bytes. Unrelated
package I aliases emitted by the existing format generator were restored to
their base bytes. No source production interface was removed.

Records extraction remains a source no-op; point activity metadata belongs to
the point importer. The plan's proposed accuracy/place mutation for F25 does
not match Rails 1.15.3 and must be reconciled with that source behavior.

RX-IMPORTS owns native followup publication and standalone lease admission.
Package I owns the HTTP request path. Package O owns final route wiring and
the shared job Registry; entries remain inert pending readiness integration.
Legacy Google Takeout and resume interfaces retire only after accepted work
drains. Native continuation, full enhanced orchestration and complete planned
edge envelopes remain open until their own evidence is recorded.

AFFiNE counterpart: Dawarich — Phoenix import codecs and extraction closure.

F24 streams Phone Takeout semantic segments and frequent places, ignores raw
signals, and preserves profile ordering and captured zones. The complete source
table passes; emitting a raw signal as a visit fails, then restored GREEN passes.

F25 retains the source Records no-op even for malformed files. All captured
inputs pass. The reconciled mutation emits an accuracy-derived row; it fails
the empty-output assertion, and restored GREEN passes.

F26 streams step visits from Polarsteps arrays and steps objects while location
trails emit no extracted visits. The complete source table passes. Swapping
latitude and longitude fails the exact place comparison; restored GREEN passes.

F15’s standalone GPX continuation stores the prepared-row cursor in the existing
import-run attachment receipt. The executing event, job, attempt, actor, source
and blob fence applies before every batch. Points, counters, tile effects and
cursor advance commit together. Retries skip committed prepared rows and retain
counters. A changed attachment raises LeaseLost without another point or handoff.
The new NormalResume module is the minimal shared cursor seam required by F15;
F16 reuses it. Coexistence keeps its existing source-owned handback behavior.

Evidence: missing GpxResume was RED; the aggregate passes; bypassing the saved
attachment check fails the changed-blob assertion; restored affected GPX tests
pass (54 tests). Progress uses the existing native PubSub stream in standalone.

F16 uses the same fenced receipt for CSV, Records, OwnTracks, Semantic History,
GeoJSON, Phone Takeout and KML. The existing NormalBatch has the minimum cursor
seam needed by these codecs; atomic formats retain whole-import rollback.
Semantic History retains Rails’ zero raw_points counter quirk. Initial RED
exposed the missing normal batch interruption/checkpoint behavior; GREEN passes.
Forcing resume_offset to zero fails retry; restored GREEN passes. The Semantic
History table extension had its own missing-checkpoint RED and GREEN.

F01’s priority envelope rejects unsupported storage and unsafe archives as
native errors in standalone, retaining source fallback in coexistence. RED
returned a legacy tuple; GREEN returns an error without points or handoff.
Mapping CSV to GeoJSON fails the dispatch assertion; restored GREEN passes.
The complete planned source/transport aggregate remains open.

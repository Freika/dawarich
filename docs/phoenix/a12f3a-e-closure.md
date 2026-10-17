# Exports and user-data closure

The native standalone journey now submits an export, writes and attaches the
backup ZIP, imports its signed blob ID for the current user, and restores a point
through the actual Oban import worker. The closure test checks the restored point
counter and absence of Rails commands for this journey. Export index snapshots,
JSON/GPX bytes and ordering, monthly UTC/Berlin/New York splits, portable files,
restore counters and boundary batches use the existing Rails captures.

Native export submission preserves Rails format coercion, source civil-date
filenames, date normalization, archive rows without a points job, blank formats,
and the empty 422 response with redirect and alert cookie. Array/object fields
reach the source validation response through the existing A8 form decoder.
Current-user backup authority ignores supplied target IDs. Foreign export deletion
returns the source 404; shared attachment deletion retains the other attachment.
A deleted user cannot claim or complete a points export.

Native restore point inserts bump the existing opaque tile epochs directly through
`Dawarich.Redis.cache_command/1` while their accepted-work fence is active. The
context flag is set by the native import worker; coexistence primitive callers
retain their original effect. Terminal import failures preserve the source service
and job notifications, then mark the event processed in the fenced job effect so
re-delivery cannot repeat the terminal notifications.

## Handoffs and limits

| Caller | Existing interface and identity | Native terminal result / handoff |
| --- | --- | --- |
| `PointExports.create/3` | `command:exports.points`, v2 export/user/time_zone, event UUID, current scheduled time | Native outbox publication and points worker; T10 can keep this interface. Archive format creates the source row without a points command. |
| `UserDataController` | `command:users.export_data`, current user and captured locale/zone; `command:users.import_data`, current-user source-8 import, signed/raw archive | Native outbox; independent of settings key; shared dispatcher retains admission/ownership control. |
| `ExportWorker.run/3` | `ExportState` accepted event, user and export claim; storage upload before attachment fence | ZIP attachment, one success notification, processed event; ownership loss removes unaccepted storage. |
| `ImportWorker.run/3` | Existing `Imports.Lease.with_import/5`, source-8 snapshot, user/import/blob/event identity | Restore transaction, source post-commit filter, actual points counter, terminal processed event. |
| `Restore.Tracks` | `Tracks.Effects.write!/3` | **Open:** existing provider publishes `tracks_changed`; W and shared effect rows must provide the native terminal effect. E does not duplicate that provider. |
| `Restore.filter/4` | `Points.AnomalyFilter.call/5` with zone and effect fence | **Open:** flagged points invoke shared tile, stats, achievement and track follow-up sinks; shared providers must close these before full Ruby-free acceptance. |
| `Restore.PointWriter` | Native context, cache Redis interface and existing yearly tile epoch key | Minimal E-owned seam; shared cache provider should centralize this interface when supplied. |

`ExportRoutes` and `UserDataRoutes` have only the focused decoder wiring needed
for the domain to be reachable; O06–O08 still own final dispatch/wiring.
Changes to the two existing generator files and two existing native tests are
minimum source/contract seams. The point generator now pins attachment/blob and
notification sequences and captures container errors; the user-data generator
captures archive container errors. Each was written twice and byte-compared.

The eleven named aggregate tests have passing restored selectors and failing
named mutations. E01/E02/E03/E04/E10/E11 exposed missing behavior; E05–E09 mostly
reconcile already-green source-backed implementations. No fictitious initial RED
is claimed for those existing behaviors. In particular the reversed v1 archive
retains the source's missing-entity discrepancies.

Package-wide source-free acceptance remains open for shared follow-up providers,
full envelope variants and worker ownership changes beyond the exercised live-user,
accepted-event and blob fences. This is a native journey implementation and parity
regression cut, not Ruby-free release acceptance. The assigned execution report
records exact gate counts and the remaining task variants.

## Verification

The scoped Rails batch passed 48 examples; both changed generator files passed
RuboCop. The native domain batch passed 73 tests. After installing the vendor
poster dependencies and restoring the existing form logging tag, the root-fix
batch passed 22 tests including the complete closure file and real poster styles.
All eleven restored selectors pass; the native batch test also checks the actual
cache epoch token and verifies duplicate rows do not change it.

AFFiNE counterpart: **Dawarich — Implementation: A12f-3a E native exports and backup
journey**, document `3jnCJWRTo80DsateIkxcL`; synchronized and verified by readback.
The assigned execution report records final seed-404 gate counts and cleanup.

The final required seed-404 gate at `33ba78df8` completed 8,829 tests with one
failure in P08 places CLI scheduling, outside package E. Its test assumes ascending
user IDs for due-time assignment, while the second CLI query has no ordering and
Rails uses an unordered `batch.pluck(:id)` too. A private temporary-table probe
reproduced batch-first ID 1 versus scheduled-first ID 100. P owns reconciliation
under ruling 13; adding a production sort here would change source parity.
All E checks passed. The full gate remains failed; no unchanged-suite retry or
places-file change was made. The report preserves both full runs and all summaries.

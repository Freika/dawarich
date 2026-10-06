# Accepted import failure recovery

Plan E SOURCE-IMPORTS review R1, 2026-10-07. The canonical AFFiNE counterpart is
`Dawarich — Phoenix imports HTTP and producer closure` (`OICwyQJkkxfUDp6macMX9`).

A handled GPX failure commits its failed status, failure notification, coexistence
progress command and terminal import-run attachment snapshot in one fenced
transaction. This applies to preparation errors, including a missing attachment,
and parsing errors. Native progress broadcasts follow the committed failure.

The processed-command marker remains a separate terminal transaction. If its
publication fails, the next executing attempt resumes the terminal receipt without
downloading, parsing, writing points or creating another failure notification.
The handover also settles that receipt. Failed imports never enqueue extraction.
Import, actor, event, executing attempt, token and attachment checks remain active.

A failed notification transaction rolls back the failure status and receipt. The
run stays in processing and can retry the actual work. Lease loss and interrupted
point processing retain their existing cursor recovery; a failed status alone is
not evidence of handled terminal effects.

`a12f3b_e09_test.exs` replaces the fabricated GPX failed receipt with the actual
worker, a rejected processed-marker insert and attempt-two recovery through both
the worker and handover. A database trigger counts committed failure-processing
passes. The test requires one pass, one notification, no points, no extraction and
stable replay. Its second regression rejects notification insertion and proves
atomic rollback followed by normal recovery. Both names have RED, GREEN, named
mutation failure and restored GREEN evidence in `fix-a12f3b-e-imports.report.md`.

The retained Rails GPX admission excludes completed imports but accepts failed
imports (`app/services/imports/gpx_legacy.rb:20`), and processing creates a fresh
failure notification (`app/services/imports/create.rb:47`). An accepted job retry
after those effects commit can therefore repeat the notification. The Phoenix
receipt closes that retry gap. The shared ED/DRB ledgers remain controller/HOT
owned; this scoped fix report records the source behavior and native correction.

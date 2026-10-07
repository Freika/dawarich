# Load-sensitive exports, import leases and visit sweeps

Monthly exports consume at most 1,000 rows at a time, group that batch by month,
and write each month's iodata in one file operation. The first batch for a file
truncates an existing file; subsequent batches append. Month-local row order,
JSON escaping, newlines, file names, counts and metadata remain compatible with
the former per-row writer and the retained Rails oracle fixtures. Export metadata
contains no row payloads. File operations complete within each batch, so no open
file handles survive enumeration errors.

Import lease concurrency tests wait for the monitored task's stage message or its
exit before inspecting ownership or releasing work. The ordinary ExUnit test
watchdog remains the limit. A 100 ms assertion window cannot synchronize a stage
that first acquires leases and executes database queries. The existing database
lock-wait assertion still verifies that ownership transfer blocks behind a live
stage, then invalidates its next effect.

The secure import downloader's four-attempt timeout test waits for each writer
to report that it has written its partial bytes, then delivers the deadline
through the existing timer seam. A short wall-clock timer can expire before a
writer is scheduled and therefore cannot prove how many streams started. The
deterministic probe retains the attempt limit and file cleanup assertions;
production timeout and retry settings are unchanged.

Bulk visit sweeps validate all distinct candidate timezone names and the ambient
fallback with one `pg_timezone_names` scan per nonempty user page. Rails aliases
are mapped to IANA names; invalid user zones fall back to the validated ambient
zone, then UTC. Results live only for the current page. PostgreSQL's timezone view
computes timezone information for every name even when the query filters one
name; scanning it for every user adds substantial CPU work. The observed timeout
was the whole-test watchdog expiring while Postgrex received a query result.
Scratch-repo activity samples showed no blocking sessions or lock waits.

Regression coverage includes byte comparisons with a preserved legacy writer,
bounded-batch observations, retained Rails fixtures across three timezones,
monitored import stage barriers and task exits, timezone query-count assertions,
aliases and fallbacks. Deterministic batch-boundary and query-budget probes plus a
gated import effect reproduce the causes under `ELIXIR_ERL_OPTIONS="+S 1:1"`.
Named mutations, repeated green runs and integration-gate results are recorded in
the controller's task report. Host-wide stress must never be used on the shared
machine.
No retries, skips, quarantine or numeric timeout increases are part of the
export, import and visit sweep fixes.

The Rails schedule-cutover regression compiles the test-mode Phoenix application
before starting its interactive peer, then runs the peer with `--no-compile`.
Compilation failure fails the example before the peer starts. The peer must send
its explicit `A12D3:ready` message after test database setup within a 120-second
startup bound. Subsequent ownership and scheduling protocol replies retain their
five-second bounds. A five-second startup wait includes VM boot, test-file
compilation and scratch database preparation, even when application compilation
has already finished. The source/native slot, lock, owner-flip, rollback and
single-fanout assertions remain intact.

The timezone execution plan is a function scan, with the name filter applied
after enumeration; it is not a lookup into an indexed user table. PostgreSQL
[documents the view's timestamp-dependent timezone calculation](https://www.postgresql.org/docs/current/view-pg-timezone-names.html).

Shared counterpart: AFFiNE document **Dawarich — Load-sensitive export, lease and
visit sweep root fixes**, document `IQjDYgmYAZw0iq5D6Q0pM`. Related synchronization precedent: **Dawarich — LiveView
channel join test synchronization**, document `fhv7GPzGN7Cp-t_Y8Nhnb`.

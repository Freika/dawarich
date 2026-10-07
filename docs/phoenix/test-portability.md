# Phoenix test runner portability

Immediate outbox dispatch assertions use `Dawarich.JobsCase.db_now(repo)` and
pass that value through `Dispatch.run/1`'s existing `now:` option. The helper
reads PostgreSQL `clock_timestamp()`, matching database-generated availability
timestamps. Fixtures with an injected producer clock use the same clock for
production and dispatch. Explicit due-time boundary tests retain their supplied
clock; advancing a host clock or adding a grace interval cannot make future
work due. Host and container clocks need not agree for these assertions.

Video preview comparisons decode both the response and retained Rails fixture
into RGB PPM frames. PPM includes image dimensions and pixel bytes, so encoder
comments and compression differences do not affect equality, while changed
pixels or dimensions still fail. Decoding errors also fail. HTTP status, cache
identity, disposition and content type remain asserted. Encoded byte equality
remains in tests for transfers and representations that preserve source bytes.
The runner needs the existing `ffmpeg` and `pdftoppm` preview tools.

Cross-runtime tests derive their database names from `PHOENIX_TEST_DATABASE`
and `MIX_TEST_PARTITION`, including the appropriate scratch suffix. Source and
native helpers verify that the chosen database agrees with the configured or
fixture database. Protocol helpers also require test mode and a local database
host and reject shared development/default test databases. Private allocations
are runner configuration, not a fixed naming prefix in these tests. Ruby
processes receive an explicit private `REDIS_URL`; native subprocesses receive
`PHOENIX_TEST_REDIS_URL`.

The retained test in `test/dawarich/release/native_test.exs`, named **native lock
connection preserves IPv6 socket options and session parameters**, requires a
real PostgreSQL session over IPv6 loopback. PostgreSQL must be reachable on
`::1` at `DATABASE_PORT`, and `localhost` must resolve to IPv6 loopback. For a
container runner, publish the PostgreSQL port on both IPv4 and IPv6 loopback
and configure PostgreSQL listening and authentication for the IPv6 session.
An IPv4-only Docker publication does not satisfy this requirement. Check both
transports before starting a full suite; do not skip this test or change its
assertion that the advisory-lock session has IPv6 client address `::1/128`.
The controller owns the Mac mini PostgreSQL IPv6 bind change.

These are test and runner requirements. Native Cloud lifecycle continues to
refuse every mode until the external L1 handoff. No production dispatcher,
release guard, retry, sleep or timeout change is involved.

Related repository guidance: [load-sensitive tests](load-sensitive-tests.md).
Shared runner counterpart: AFFiNE **Dawarich — Mac mini suite runner runbook**,
document `Y2M2jORYedr3DOVoy8lg_`.

# ExUnit partitions

Install both JavaScript dependency sets before running the suite, from the
repository root. Use a private cache when sharing the machine:

```sh
npm ci --cache "${TMPDIR:-/tmp}/dawarich-test-npm-cache"
npm ci --prefix vendor/poster_renderer --cache "${TMPDIR:-/tmp}/dawarich-test-npm-cache"
```

The root install supplies Swagger UI assets. The poster renderer has its own
lockfile and requires `@maplibre/maplibre-gl-native`; root `npm ci` does not
install it. A `MODULE_NOT_FOUND` error in `a12f3b_p02_test.exs` or
`NativeRenderer.run/3` means the vendor install is missing. These dependencies
are setup requirements for native poster coverage, including partitioned runs.

Run from any directory:

```sh
PHOENIX_TEST_DATABASE=dawarich_phoenix_test_part \
PHOENIX_TEST_REDIS_URL=redis://127.0.0.1:7271/1 \
  app-phoenix/scripts/test_partitions.sh 3 --seed 404
```

The runner pins Elixir 1.20.4 / OTP 27.3.4.1 and starts one Mix process per
partition. Set PostgreSQL connection variables before running it. Create the
main databases first and load the Rails schema into each one. For example, from
the repository root, with the private Rails Redis URL configured:

```sh
RAILS_ENV=test DATABASE_NAME=dawarich_phoenix_test_part1 \
  bundle exec rails db:schema:load
```

Repeat for each partition database. `test_helper.exs` creates and migrates their
scratch repos; it does not create the Rails tables in the main database.
The default database base requires `dawarich_phoenix_test_part1` through `partN` for N partitions (1 to 8).
Start private Redis servers on ports 7271 through 7270+N, with database 0 for the
cache and database 1 for jobs. With another Redis URL, its port is the base port.
Each partition adds its number minus one to that port.

The database base gets the `MIX_TEST_PARTITION` suffix. Scratch databases add
`_scratch`, `_scratch_case`, and `_scratch_tracks` after it. Cable prefixes,
generated locale/achievement inputs, and the PostgreSQL no-CREATE test role also
include the partition. `TMPDIR` becomes `app-phoenix/tmp/partitions/k/system`,
isolating spool files, storage fixtures, subprocess files, and VM-local integer
filenames. ExUnit's tagged temporary directories identify the test module and
test name; Mix assigns each test file to exactly one partition. They therefore
remain disjoint across partitions.

The suite's actual TCP listeners use port 0. Fixed ports in command/URL fixtures
do not bind listeners. The fixed auth HTTP stand port belongs to the standalone
parity script, outside `mix test`. Rails parity tests remain excluded as before;
the regular suite launches no Rails database peer. Named ETS tables, registered
processes, telemetry handlers, and persistent terms are private to each BEAM.
The two-node tests start unnamed peers over standard I/O and pass their own
partition's scratch configuration. Oban notifications use that database; Redis
keys, flushes, and channels use that partition's Redis server.

For a single partition, use the same runner with `1`. For an individual process:

```sh
cd app-phoenix
MIX_TEST_PARTITION=2 PHOENIX_TEST_DATABASE=dawarich_phoenix_test_part \
PHOENIX_TEST_REDIS_URL=redis://127.0.0.1:7271/1 mix test --partitions 3 --seed 404
```

Always pass the base database and Redis URL, including for individual processes.
Keep separate runs over the same resources sequential. Extra arguments after
the seed go to `mix test`; all processes receive the same seed. Logs default to
`app-phoenix/tmp/partition-logs/partition-k.log`; override their directory with
`PHOENIX_TEST_PARTITION_LOG_DIR`. The runner waits for every process, prints its
log and seed, and prints the summed test/failure counts. A failed process,
missing/ambiguous summary, or missing seed makes the runner exit nonzero. Elixir 1.20 prints `Result: N passed` or `Result: P/N passed` instead of the old `N tests, F failures` line; `scripts/test_summary.awk` accepts both and aggregates failures without weakening the process exit-status checks.

When limiting the local parent's scheduler count, use `ERL_AFLAGS='+S 4:4'` rather than `ERL_FLAGS`: several peer tests explicitly launch two schedulers, and trailing `ERL_FLAGS` would override that contract. After an interrupted run use fresh private databases: committed peer fixtures may remain. Tests that launch Rails peers also require `DATABASE_PORT`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`, and an installed Ruby selected through asdf. Use isolated PostgreSQL databases and one isolated Redis server per partition.

Whole-suite runs still require the controller's `slot.sh` around this runner.

The 2026-10-05 sync of `feat/phoenix-port` was checked for new shared resources.
Pending-import cleanup/purge fixtures use `System.tmp_dir!()`, and the new
schedule, drain, geocoding, and visit tests use the configured scratch repos.
The schedule Rails peer test remains excluded by `:rails_parity`; its database
assertion belongs to the standalone peer protocol rather than this suite.

Verification on `f8638719f` (2026-10-05), through the controller's `slot.sh`:

| Partitions | Seed | Tests | Failures | Wall seconds | Starting load averages |
| --- | --- | --- | --- | --- | --- |
| 1 | 404 | 7143 | 1 | 650.47 | 7.88 / 11.24 / 16.16 |
| 3 | 404 | 7143 | 1 | 290 | 18.41 / 20.83 / 24.73 |
| 3 | 202 | 7143 | 3 | 440 | 15.57 / 18.20 / 21.80 |

Both three-partition runs completed all summaries with counts
2118 + 2403 + 2622 = 7143, matching the single-partition baseline.
Every partition reported the requested seed. Seed 404's observed speedup was
2.24 times. The controller's session-3 ruling reused the earlier N=1 timing;
these measurements span sessions and have different host loads.

Both seeds hit the acknowledged `ProcessWorkerTest` localized failure-prefix
assertion defect. Seed 202 also hit `SecureFileDownloaderTest`'s four-attempt
assertion (three attempts observed with a 40 ms deadline) and `RailsProxyTest`'s
Puma request-forwarding test (`RawHTTP.accept/1` socket timeout). Each additional
test passed three isolated runs with seed 202 and its original partition.
These results support timing sensitivity, but the two tests are outside the
brief's explicitly named load exceptions; controller disposition remains
pending. The runner correctly exited nonzero for both full runs.

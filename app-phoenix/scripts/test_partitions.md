# ExUnit partitions

Run from any directory:

```sh
PHOENIX_TEST_DATABASE=dawarich_phoenix_test_part \
PHOENIX_TEST_REDIS_URL=redis://127.0.0.1:7271/1 \
  app-phoenix/scripts/test_partitions.sh 3 --seed 404
```

The runner pins Elixir 1.18.3 / OTP 27.3.4.1 and starts one Mix process per
partition. Set PostgreSQL connection variables before running it. Create the
main databases first and load the Rails schema into each one. For example, from
the repository root, with the private Rails Redis URL configured:

```sh
RAILS_ENV=test DATABASE_NAME=dawarich_phoenix_test_part1 \
  bundle exec rails db:schema:load
```

Repeat for each partition database. `test_helper.exs` creates and migrates their
scratch repos; it does not create the Rails tables in the main database.
The default database base requires `dawarich_phoenix_test_part1` through `part4`.
Start private Redis servers on ports 7271 through 7274, with database 0 for the
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
missing/ambiguous summary, or missing seed makes the runner exit nonzero.
Whole-suite runs still require the controller's `slot.sh` around this runner.

The 2026-10-05 sync of `feat/phoenix-port` was checked for new shared resources.
Pending-import cleanup/purge fixtures use `System.tmp_dir!()`, and the new
schedule, drain, geocoding, and visit tests use the configured scratch repos.
The schedule Rails peer test remains excluded by `:rails_parity`; its database
assertion belongs to the standalone peer protocol rather than this suite.

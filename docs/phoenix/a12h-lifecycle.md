# A12h native release lifecycle

Last updated: 2026-10-06.

The default-off, self-hosted lifecycle now owns public upgrades, private schema
setup, registration-policy copy and ordinary install seeds. Rails/Puma remains
the request fallback and Sidekiq remains the coexistence worker. This implements
a bounded first cut of inventory row 14; it does not authorize live activation.
The plan is `2026-10-05-phoenix-a12h-plan.md` in the project plans repository;
the implementation report is `SP/orch/out/impl-a12h.report.md`.

## Commands and boot

`DAWARICH_PHOENIX_LIFECYCLE` accepts only literal `true` or `false`; absence means
false. Other values fail before lifecycle work. True requires the existing
self-hosted policy. Cloud true refuses before either migrator runs.

With true, `dawarich migrate` upgrades public, phoenix and oban schemas, inserts
new native release jobs and copies registration policy. `dawarich db:migrate`
is its native-only alias. `dawarich seeds` and `dawarich db:seed` require current
public/private schemas and run ordinary seeds. Successful commands return 0;
refusals return 1 and preserve the existing floor remedy. `data:migrate` keeps
its existing pre-floor retirement explanation.

Native `docker/web-entrypoint.sh` preserves asset synchronization, database
creation/wait and privilege handling, then runs:

1. `dawarich migrate`.
2. `dawarich seeds`.
3. For a server, `dawarich eval 'Dawarich.Release.halt_unless_ready()'`.
4. Phoenix supervising Puma with the original server arguments; arbitrary
   commands retain `exec bundle exec "$@"` after successful lifecycle work.

Migration, seed or readiness failure exits without automatically starting Rails.
Native readiness requires both private ledgers and a current public ledger;
it never migrates or inserts jobs. Missing/behind schemas retain exit 3 and
no database connection retains exit 5.

Native `docker/release.sh` runs migrate then seeds and stops on either failure.
`docker/cloud-entrypoint.sh`, when explicitly used for self-hosted native mode,
checks public-aware readiness and stops on failure. Actual Cloud native mode
refuses. Both worker entrypoints retain real Sidekiq and never migrate or seed.

With the flag absent/false, the self-hosted web sequence remains:

1. Assets, database selectors, creation and database wait.
2. `bundle exec rails db:migrate`.
3. `bundle exec rake data:migrate`.
4. `bundle exec rails db:seed`.
5. `dawarich eval 'Dawarich.Release.migrate()'` installs private schemas and
   copies registration policy.
6. Successful server commands run under Phoenix; Phoenix failure retains the
   existing Rails fallback. Other commands retain their original arguments.

Flag-off `dawarich migrate` remains private-schema-only; `db:migrate`, seeds and
`db:seed` refuse native work while disabled. Flag-off release keeps Rails schema
migration then private Phoenix migration: Cloud failure stops deploy, while
self-hosted failure retains the fallback notice. Cloud web retains its existing
private readiness/fallback behavior. Route/auth/job-owner flags stay independent.

## Write coordination and source parity

Unsupported, below-floor, foreign and newer public ledgers refuse before private
schema writes. The floor is schema release 0.37.2, corresponding to product 1.0.0.
The remedy is to start Dawarich 1.15.3 once for Rails upgrades, then retry.
This final Rails release shares 1.15.2's schema state.
Pending data migrations refuse rather than silently skipping work.

Like Rails, native creates empty schema_migrations/ar_internal_metadata with
IF NOT EXISTS before taking Rails' exact migrator advisory key
`2053462845 * crc32(current_database)`. No native version or registration rows
are written before exclusion. A fresh metadata race can fail loudly without
partial native version, job or registration writes; stronger bootstrap exclusion
than Rails provides is not claimed.

A dedicated Postgrex connection stays pinned for the whole native migrate/seed
call, outside transactions. Completed pg_try_advisory_lock queries precede the
required session pg_advisory_lock; blocking lock queries retain snapshots that
would prevent CREATE INDEX CONCURRENTLY. Both lock counts release in an after
path, and disconnect releases locks on crash. Private migrations use existing
Ecto locking; the existing lease/fences span public migration, registration copy
and seed writes. Release-level tests cover fresh/current migration concurrency,
Rails try-lock refusal, seed concurrency and migrate-versus-seeds exclusion.

The dedicated connection preserves the Repo's connection settings, including
IPv6 socket options. It stops on disconnect with no supervisor restarts; its
link terminates the native write caller on backend loss. It never reconnects
or reacquires a lost lock, and both unlock results must confirm release.

With documented `DATABASE_ADVISORY_LOCKS=false`, native takes no session lock,
using Visits.Persister's parsing. This is Rails source parity: the operator's
single-migrator rule applies across both runtimes, including PgBouncer transaction
pooling. Never take a session lock through a transaction pooler. ED-534 records
this setting as source parity, not a native gap. Native coordination does not
coordinate Rails db:seed; stop old boot/deploy seed writers before activation.

## Release concurrency test synchronization

`test/dawarich/release/native_test.exs` uses monitored workers for the fresh
migration race and lock-connection-loss proof. Test-only `Dawarich.NativeWorker`
reports stages, the actual migration result and process exit separately. Each
write barrier requires an explicit continuation. Completion requires both the
result and normal exit, after migration cleanup has released the session lock.
An exit before readiness reports its reason immediately. ExUnit's existing
whole-test deadline still bounds a stalled worker; there is no independent
five-second deadline on bootstrap or the complete DDL path.

The loss proof captures only the dedicated test connection through Repo
configuration. It verifies the caller link, closes that connection's TCP socket
and requests a driver ping to deliver the disconnect immediately. It awaits the
caller's monitored exit before trying the Rails advisory key and checking that
native rows, jobs, versions and registration copy remain unwritten. It does not
terminate a PostgreSQL backend. This probe depends on the pinned DBConnection
state shape and must be checked when upgrading that dependency.

Run the two tests with `ELIXIR_ERL_OPTIONS="+S 1:1"`, using the existing
`PHOENIX_TEST_DATABASE` and `PHOENIX_TEST_REDIS_URL` isolation settings. Named
mutations cover worker identity, readiness failure, completion result, abnormal
exit after a result, worker crash, lock exclusion and the caller link. Controlled
barriers reproduce stalled progress without host-wide CPU load. The shared
knowledge-base counterpart is titled **Dawarich — Native release concurrency
test synchronization** (AFFiNE document `bzWCSl5BdwdP0bkQzz_-w`).

## Jobs and ordinary seeds

Live migration uses explicit enqueue mode. Version effects, public ledger, raw
intent and Oban job insertion share the version transaction. Worker options and
delay remain intact; invalid/deferred decisions fail the version. Existing
nontransactional DDL retains source partial-failure semantics. Record-only C4
mode remains unchanged. A12rel achievement and import adapters close all recorded
self-hosted vectors; Cloud family adapters remain a separate prerequisite.

Raw intents have no execution/disposition marker and may be offline proof output
or work already performed under Rails. Establish a known migration baseline and
resolve recorded-but-unperformed work with the release owner's existing jobs
procedure. Never replay every stored intent. No job-owner or cron flip is implied.

Seeds run bootstrap user, countries, regions, then tags. They preserve scoped
User.none?, unscoped Country.none?, Region.none? and global Tag.none? predicates.
Only country loading owns a whole-load transaction. Invalid countries roll back
their load; empty countries refuse regions and later tags. Region geometry uses
the existing load/repair effect. Partial tag rows prevent further automatic
seeding. Source partial effects remain after a later seed failure.

Bootstrap preserves database defaults, bcrypt, random API keys, committed creation
before self-hosted activation and the Rails calendar expiry/pro plan. Shared admin
persistence still requires authorization. ED-532 suppresses credential output;
clock, salt and random input injection is confined to corpus tests. Country bytes
resolve from packaged priv assets; image/asset smoke execution remains deferred.

## Upgrade, rollback and release boundaries

| Case | Implemented behavior and evidence |
|---|---|
| Fresh / supported 1.0.0+ self-hosted | Native orchestration, real-vector decoder closure, guarded ordinary seeds and public readiness; real release rehearsal remains required. |
| Unsupported public state | Refusal before private writes, with floor/foreign/newer diagnostics. |
| Concurrent native calls | Complete write coordination and Release-level race tests; advisory-lock-disabled operators must enforce a single migrator. |
| Cloud true | Explicit refusal; native Cloud provisioning is a follow-up. |
| Route hand-back | Real upstream request/body receipt for DAWARICH_RAILS_ROUTES rails_key and DAWARICH_RAILS_SLICES, with auth and job-owner behavior unchanged. |
| Same image, native on then Rails off | Real native public version/job insertion followed by actual Rails db:migrate, data:migrate and db:seed on the same private test database. Rails recognizes the versions without reinserting work; complete pending Oban rows retain IDs, payloads and state. |
| Older Rails image / backup restore | Requires compatible public DDL/data, explicit native-job disposition and G48 rehearsal; same-image hand-back does not prove this. |

Pending Oban work remains explicitly undisposed when lifecycle is disabled. Stop
boot writers/workers and inspect it before operational rollback; existing owner/
rehome tools cover only their documented jobs. Release-only jobs need an explicit
release-owner disposition. Route hand-back neither restores schemas nor cancels
workers. G48 needs the existing snapshot/restore procedure and job disposition;
G49 final drain remains A12d3.

The branch gate is existing resync-check.sh (seed 404) and seedrun.sh (seed 202),
with Elixir 1.18.3/OTP 27, allocated private DBs/Redis and slot.sh for full suites.
The controller owns the third seed. Scoped tests and named mutations run directly.
The existing Rails fixture generator runs twice identically, then verifies without
WRITE_PHOENIX_FIXTURES. Its same-image case records complete ledgers/raw intents/
Oban rows and normalizes only the fixture clock, without masking random fields.
Reports carry actual results; these instructions are not substitute gates.

Browser/stand, Docker images, release/asset smokes, C3/C4 and topology checks are
**deferred to the controller mini lane**. G47's existing scripts still need the
plan's separately authorized test-env/asdf/Redis/no-env-hashing fixes; G48 still
needs its release procedure. Local tests do not close those release gates or
authorize activation. No AFFiNE writes occur because seeds touch credentials.

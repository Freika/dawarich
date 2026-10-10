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
| Stock Rails 1.15.3, same DB/storage | Controller rulings 4/7: fence producers, pin every key to Sidekiq, drain native work without transfer, stop Phoenix, then start Rails. Preserve Phoenix-era writes; deferred G48 proves the exact image/data boundary. |

Pending Oban work remains debt when lifecycle is disabled: disabling an opt-in
neither releases persisted owners nor cancels workers. Controller rulings 4 and
7 supersede the earlier snapshot/restore and pending-rehome rollback proposal.
Keep native relay/workers alive after every-key pinning until accepted outbox,
Oban, release operations and durable successors finish naturally. Unknown,
quarantined, dead, future and reverse work blocks the affected transition; no
native-to-Sidekiq transfer is built or invoked. Stop all native/control-plane
writers before starting stock Rails **1.15.3** on the same database/storage.

The complete manual procedure, additive-boundary amendment for ADR0015/G48 and
Cloud/self-hosted deferred rehearsal are in
[a12f-ruby-free-release.md](a12f-ruby-free-release.md#a12f-3c-same-database-rollback-to-rails-1153).
Same-image hand-back above remains historical coexistence evidence, not a stock
1.15.3 rollback proof. G48/G49 require separately authorized release resources;
backup hygiene is recommended, never a rollback restore prerequisite here.

Controller ruling 14 sets the branch gate to seedrun.sh seed 404 only; seed 202
runs once on the integration head after each merge batch. Use Elixir 1.18.3/OTP
27 and allocated private DBs/Redis; seedrun.sh owns its suite slot. Scoped tests
and named mutations run directly.
The existing Rails fixture generator runs twice identically, then verifies without
WRITE_PHOENIX_FIXTURES. Its same-image case records complete ledgers/raw intents/
Oban rows and normalizes only the fixture clock, without masking random fields.
Reports carry actual results; these instructions are not substitute gates.

Browser/stand, Docker images, release/asset smokes, C3/C4 and topology checks are
**deferred to the controller mini lane**. G47's existing scripts still need the
plan's separately authorized test-env/asdf/Redis/no-env-hashing fixes; G48 still
needs its release procedure. Local tests do not close those release gates or
authorize activation. Operational documentation is mirrored without credentials;
seed payloads and secrets must never enter the shared knowledge base.


## A12f-3c Cloud handoff (2026-10-06)

[Package P's two checkpoints](a12f-ruby-free-release.md#a12f-3c-operator-cut-over-and-old-shutdown-handoff)
separate NEW traffic activation from OLD final shutdown. Native argv mapping
and source fences are integrated preparation; explicit Cloud/native lifecycle
still refuses at the package P inspection head. L1/B must supply real Cloud
provisioning, source-equivalent trial/family/callback effects, registration-copy
authority, migration exclusion and shared row/object proofs before traffic moves.
Do not turn a self-hosted guard off to fabricate this handoff. Read-only readiness
must not migrate/seed or duplicate callbacks. D's reviewed every-key pin/drain
contract and E's two-deployment stop evidence remain acceptance prerequisites;
local tests do not close G48/G49.

## L1 preparation handoff (2026-10-07)

Packages A–E are composed through preparation-only `Dawarich.Release.Cloud` in `release/cloud_handoff_test.exs`: fresh precreated schema-owner provisioning without database CREATE, actual populated Rails rows, default registration/creation/referral intent publication, typed Dispatch/Oban delivery, ordinary trial/mail, deletion/unlink and both family backfill effects. Reentry preserves identities and historical state; callback transport failures remain retryable and pending family data closes readiness. Endpoint-specific package suites retain their source-distinct browser/mobile/Apple/provider contracts. This is component-level proof; no public native Cloud success is claimed.

Public native Cloud lifecycle remains refused in every mode, including Rails off. Task 12 is outside this package and requires controller acceptance plus independent security review. Local receipts do not guarantee exactly-once remote effects across accepted-send/process-death. Manager keeps the controller's Rails-parity replay limitation; live receiver and SMTP acceptance remain external.

The [L1 rollout procedure](l1-cloud-rollout.md) supplies exact conditional release/web/worker commands, direct/session-capable database requirements alongside the pooled application URL, configured Manager/Partnero contracts, staging rehearsal and same-DB Rails 1.15.3 rollback. Eugene runs all remote changes. Cloud seeds omit the demo administrator by Eugene's 2026-10-07 ruling (ED-552); administrators are provisioned manually. Signup publication atomicity and Partnero diagnostics are registered as FRB-068/069, ED-553/554 and DRB-038/039. No ownership activation, traffic switch, old-app shutdown or G48/G49 acceptance follows from this handoff.

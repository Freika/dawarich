# L1 Cloud rollout handoff

Status: preparation only. Public native Cloud migrate, seeds and readiness remain refused with `SELF_HOSTED=false` in every Rails mode, including `DAWARICH_RAILS=off`. Tasks 10–11 do not change this guard. Task 12 requires controller acceptance and independent security review of the integrated candidate. Eugene executes every staging/production change himself under separate rollout authorization. No local test authorizes traffic switching or OLD shutdown.

The versioned procedure is this document; shared decision history is in AFFiNE **Dawarich — Phoenix Ruby-free release operator contracts**. Authority: `2026-10-07-phoenix-l1-cloud-lifecycle-plan.md`, tasks 10–11, and the master A12f plan's controller rulings. Cloud demo administrator omission is Eugene's 2026-10-07 ruling, registered as ED-552. Empty Cloud seeds create no account or creation effects. Provision administrators manually through an approved account workflow; never deploy known demo credentials. Populated and soft-deleted account reentry does not recreate accounts.

## Candidate Docker preparation

Build the native runtime target from the reviewed source candidate using the existing Docker build pipeline:

```sh
docker --context orbstack build --target native_runtime -f docker/Dockerfile -t dawarich:phoenix-candidate .
```

This is an operator instruction, not evidence that an image was built in package F. Keep the exact image digest/source head, retain the Rails 1.15.3 image, and validate existing image/release/Cloud smoke before use. The repository retains Rails source for same-database rollback. Preserve storage mounts, permissions, object keys, signing inputs and cookie-file setup from the current deployment. The image contains the native release at `/opt/dawarich/bin/dawarich`; its front maps known compatibility argv to Phoenix. Do not replace the entrypoints with ad hoc `mix` or Rails tasks.

## Secret-managed environment

Set values through Dokploy's secret/environment management, never embedded credentials in command strings. Use the candidate's existing cookie and application secret provisioning.

| Variable / dependency | Required contract |
| --- | --- |
| `RAILS_ENV=production`, `SELF_HOSTED=false`, `DAWARICH_RAILS=off`, `DAWARICH_PHOENIX_LIFECYCLE=true` | NEW native configuration, usable only after task 12. Never use an override to bypass current refusal. |
| `DATABASE_URL` | Existing application database. A PgBouncer transaction-pool URL at port `6432` may serve ordinary application queries. |
| `DATABASE_SESSION_URL` | Direct PostgreSQL or explicitly session-capable connection to the **same database**, separately configured for advisory migration/callback locks. A transaction/statement pool, including port `6432`, is refused. Use the approved TLS mode and hostname verification. |
| Schemas and role | DBA precreates `public`, `phoenix`, `oban`, PostGIS and pgcrypto; provisioner has schema/table ownership or approved role membership. Cloud provisioning never creates database, role or schema. Use the approved schema owner, not an application role with insufficient table rights. |
| Pool / leases | Preserve the existing minimum two lease connections plus dedicated session-lock connections. Verify production proxy semantics and concurrent release exclusion; ordinary pooled queries do not retain advisory locks. |
| `REDIS_URL` | Approved deployment Redis, with established cache/job database separation. L3 copy must be readable on first provisioning; PostgreSQL registration state becomes authoritative and preserves false/nil. Never reset it from environment on reentry. |
| `MANAGER_URL`, `JWT_SECRET_KEY` | Existing configured Manager origin and compatible signing key. Manager paths are fixed `/api/v1/users` and `/api/v1/users/unlink`; user input cannot select a destination. A missing required signup key refuses; blank Manager keeps the source worker skip contract and does not certify configured delivery. |
| `PARTNERO_API_KEY` | Existing Partnero key when attribution is enabled; fixed `https://api.partnero.com/v1/customers`. Blank key/referral skips as Rails does. Browser and ordinary OAuth attribute new accounts; Apple/mobile retain source omissions. |
| SMTP, domain, application signing and storage secrets | Preserve the existing native mail/storage configuration, `DOMAIN`, `SMTP_FROM`, and the source-compatible signing inputs. Missing required configuration must be remedied before acceptance; disabled delivery is not callback proof. |
| Listener / cookie | Preserve `PORT` and the known Procfile Cloud port `5000` where applicable; provide readable `DAWARICH_COOKIE_FILE` according to the existing image setup. Never log its contents. |
| Error reporting | Keep required Sentry/GlitchTip DSN/environment contract. Record sanitized reason classes/counts only; no provider bodies, customer identities, JWTs or connection configuration in evidence. |

Both private ledgers (`phoenix.phoenix_schema_migrations`, `oban.phoenix_schema_migrations`) and both source ledgers (`public.schema_migrations`, `public.data_migrations`) must match the candidate. Queued or recorded-but-unperformed data work is not complete. Below-floor, foreign, newer and unknown source states refuse with the retained-Rails remedy. Readiness is SELECT-only and performs no migration, seed, Redis copy, provider call or queue drain.

## Exact Dokploy commands after task 12

NEW release command remains:

```sh
release.sh
```

After the guard is separately reviewed and activated, the release must perform this sequence in the existing secret-managed environment, stopping at any nonzero exit:

```sh
SELF_HOSTED=false DAWARICH_RAILS=off DAWARICH_PHOENIX_LIFECYCLE=true dawarich migrate
SELF_HOSTED=false DAWARICH_RAILS=off DAWARICH_PHOENIX_LIFECYCLE=true dawarich seeds
SELF_HOSTED=false DAWARICH_RAILS=off DAWARICH_PHOENIX_LIFECYCLE=true dawarich eval 'Dawarich.Release.halt_unless_ready()'
```

Current `release.sh` runs migrate/seeds only in admitted self-hosted native mode; it refuses Cloud before either migrator. Until task 12 supplies and proves Cloud admission plus the final readiness step, Eugene must not use it as a successful Cloud-native release command. The three explicit commands above remain refused now.

NEW web command:

```sh
cloud-entrypoint.sh puma -C config/puma.rb
```

The known Procfile variant `cloud-entrypoint.sh puma -C config/puma.rb -p 5000` is also supported; preserve the deployment's actual PORT/argv contract. Native web clears inherited Rails args, observes readiness, then maps the supported argv to Phoenix. It never migrates or seeds, and never falls back to Rails on native readiness failure. Exit `3` means missing/behind/unreadable schemas or incomplete readiness, `4` cookie preparation failure, `5` database connection failure; other failures also keep NEW closed. Current guard still makes native Cloud readiness refuse.

NEW compatibility worker command:

```sh
cloud-sidekiq-entrypoint.sh sidekiq -C config/sidekiq.yml
```

This maps to native `sidekiq_idle`, preserving the worker slot/health contract without Repo children or a source Sidekiq consumer. Native jobs run under the real application queue configuration. The idle slot is not a migration-maintenance consumer. Unknown argv refuses.

OLD retains only its known source worker command with `SELF_HOSTED=false`, `DAWARICH_PHOENIX_LIFECYCLE=false`, `DAWARICH_CLOUD_DRAIN_ONLY=true`, and no native/idle process role. No OLD web, release, manual producer, cron/cache boot or reverse poller may publish fresh work. Preserve accepted scheduled/retry/dead work and apply the existing A12f-3c producer fences and owner-specific drain proofs.

## Staging rehearsal performed by Eugene

1. Record reviewed candidate head/digest, independent security acceptance, approved environment and role/session semantics. Use an isolated staging deployment with retained Rails 1.15.3 data/storage and a separate empty database for fresh schema-owner provisioning. Verify no database CREATE privilege is required and missing schema/table rights refuse before writes.
2. Complete supported source migrations/data work on the retained Rails image before native activation. Rehearse false/nil registration-copy authority. Precreate schemas/extensions and apply the approved manual-administrator policy for the empty Cloud case.
3. Run the release sequence. Observe all four ledgers, release operations and actual child effects. Reentry must retain API keys, historical subscription/trial state, family membership, mail due times and callback identities. Trial and delayed mail use source calendar days across DST; browser checkout accounts retain pending-payment state.
4. If pending data is reported, keep NEW traffic closed. `dawarich jobs resume OPERATION_ID` is enqueue-only with no queue consumer and cannot settle the deadlock. Use the retained-Rails pending-data remedy unless the L2 owner supplies a separately tested native maintenance command/evidence. Do not stamp completion, extend timeouts, silently delete work or open web to consume required migration work.
5. Exercise configured synthetic staging signup/referral, ordinary creation mail, deletion snapshot/unlink and both family phases. Verify rollback publishes nothing, failures remain retryable, and committed replay retains the same identities. Confirm actual configured receiver behavior separately from local transport fixtures.
6. Verify readiness refusal for every missing ledger/pending operation without any SQL writes or network effects. Confirm web readiness-only mapping, worker idle role and malformed/drain-conflicting flags before proceeding with existing Cloud smoke and release-tier G02/G42/G47 evidence.
7. Rehearse the rollback below on the same staging database/storage, then obtain separate traffic/G48/G49 authorization. L1 does not close L2's recorded-job census, L3 retirement, image/process closure, HTTP parity, SMTP policy or OLD shutdown.

## Remote acceptance and external handoff

Local `release/cloud_handoff_test.exs` composes A–E through the preparation-only Cloud component: fresh restricted schema-owner migration/seeding; populated Rails rows; real default registration and durable callbacks; typed Registry/Dispatch/Oban, ordinary mail/trial, deletion snapshot and family operations; retry/readiness/reentry. Endpoint-specific B/C/D/E suites retain browser/mobile/Apple/provider/deletion and pagination/error proofs. No success callback is injected in place of a producer. Synthetic HTTP/SMTP transports verify locally observed effects, not production receiver guarantees.

Exactly-once local publication and suppression after a committed receipt are proved. Manager creation/unlink accepted-send followed by process death before receipt can repeat the remote effect under the controller's Rails-parity ruling. No dedup header or receiver guarantee is invented. Partnero preserves the user-ID customer key and treats 409 as accepted; live behavior still requires release-owner validation. SMTP retains its separately qualified delivery contract. Ten-second verified-TLS callback transport, fixed destinations, bounded bodies and no redirects are retained. Final external acceptance and independent security review remain controller-owned; task 12 is excluded from this package.

| Closure rows | Integrated owner / observed effect |
| --- | --- |
| C0874/J0490/I0895 | B default creation context → one Manager creation intent/delivery; atomic signup state. |
| C0875/J0492/I0895 | C hard deletion → captured user/email snapshot, committed unlink, stable replay receipt. |
| C0876/J0446/I0897 | D configured Partnero customer payload, new-account attribution and spent referral. |
| C0877/J0402/J0403 | E both source decoders → operation, real family creation/member sync, readiness blocked until completion. |
| I0898–I0900 | B actual mobile/provider/Apple endpoint tests; source-distinct callbacks and existing identity suppression. |
| C0868/L3/ordinary seeds | A schema-owner component and false/nil copy; B approved empty-Cloud omission; public admission still refused. |

## Same-database rollback to Rails 1.15.3

Eugene runs the existing approved ownership operations: pin **every** ownership key back to Rails/Sidekiq, allow Phoenix to drain accepted native Oban/outbox/release work to zero, verify operation/lease/debt absence, stop Phoenix, then start the retained Rails 1.15.3 deployment and route traffic back. Keep DB/storage/signing inputs shared and verify Phoenix-era rows/attachments are readable from Rails. There is no native-to-Sidekiq transfer, inverse migration or backup restore step. Unknown/dead/unreadable accepted work blocks the affected transition until explicitly dispositioned; never delete it for an empty status. Retain the image for Eugene's release window and record G48/G49 evidence separately.

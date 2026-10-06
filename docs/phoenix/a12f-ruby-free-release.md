# A12f Ruby-free release preparation

## A12f-3c current topology and ownership census

Observed 2026-10-06 at `8d6368fc3187db758151a4d401547d93612d26bb`
(Rails 1.15.3 sync already integrated), in `feat/a12f3c-a`. This is a source
census, not a production audit or permission to switch traffic. Cloud means
explicit `SELF_HOSTED=false` throughout this section.

Authority: project plan
`superpowers/plans/2026-10-06-phoenix-a12f-3c-cloud-cutover-drain-plan.md`,
tasks 1, 2 and 5; master `2026-10-05-phoenix-a12f-ruby-free-release-plan.md`,
controller rulings 2, 4 and 7. The controller assigns separate worktrees to
lifecycle, ownership/chains, observation/shutdown and actual image/runtime work.

### Old and new deployment roles

| Role | Current source contract | Required cutover boundary / owner |
| --- | --- | --- |
| OLD web | `Procfile.cloud`: `cloud-entrypoint.sh puma -C config/puma.rb -p 5000`; bootstrap, DB wait, private readiness, Phoenix-supervised Puma or standalone Rails fallback | Stop/unpublish OLD web at traffic switch. It must not be NEW's upstream. Task 5 fences OLD, not HTTP parity. |
| NEW web | No Phoenix-only Cloud selection at this head. `exec_under_phoenix` serializes `bundle exec puma ...` into `DAWARICH_RAILS_ARGS`; `Front.plan` allocates a loopback upstream | A12f-1 supplies native argv/front helpers; task 2 consumes them; A12f-4 owns final boot selection. Port 5000 and declared health contract must survive without Puma or upstream. |
| OLD worker | `cloud-sidekiq-entrypoint.sh sidekiq -C config/sidekiq.yml`; DB wait then `exec bundle exec` | Consume only previously accepted safe source work; fence new roots, children, cron, cache boot and reverse Poller. Task 7 supplies chain eligibility. |
| NEW worker | Existing `DAWARICH_PROCESS_ROLE=sidekiq_idle` selects `Application.children(:sidekiq_idle) == []` | Idle release process, no Repo, Sidekiq, Oban or cron. Native jobs run in NEW web's existing supervision tree. |
| Release/provisioner | Flag-off `release.sh`: Rails public migrations, then `Release.migrate()` private migrations. Native lifecycle is default-off and Cloud refuses in both shell and `Release.Lifecycle` | Package B/L1 supplies real Cloud provisioning, family decoders and account callbacks. NEW release owns migrations/seeds; web readiness observes only. Retain refusals until handoff. |

`app.cloud.json` probes `/api/v1/health` on 5000, startup attempts 10/wait 10.
It defines no predeploy script. Accepted Procfile argv should remain compatible.
Readiness failure currently permits Rails fallback in legacy mode; opt-in NEW
must stop on exits 1/3/4/5. This census does not relabel that coexistence as
native acceptance.

### Shared database, queue, storage and identity

Source Sidekiq uses `REDIS_URL` with `RAILS_JOB_QUEUE_DB` default **1**, independently
of the URL path. Native runtime uses the same queue selector; cache DB defaults
to 0. Source queues are the 24 named queues in `config/sidekiq.yml`; source cron
has 24 registrations in `config/schedule.yml`. Do not use cron loading alone as
a fence: installed sidekiq-cron 2.4.0 ScheduleLoader checks `enabled`, whereas
Launcher constructs the poller from positive `cron_poll_interval` independently.
Stored cron registrations must remain observable through drain.

Both deployments retain the same public rows, `public.job_outbox`, `phoenix.*`
and `oban.*`; private schemas are additive. Rails source public migrations and
native `Release.Native` share the exact Rails advisory key
`2053462845 * crc32(current_database)`. Native also uses migration lease/fences
and recorded release operations. Native migrations own private/Oban ledgers;
ordinary web readiness must not create tables, migrate, seed or invoke callbacks.
Cloud database CREATE/schema-owner rights and L1 provisioning are unproved at
this head; source schema-loading for tests does not prove NEW provisioning.

Registration copy authority is `ReleaseMigrations.V1_13_1.copy_registration_setting`:
the migration owner copies the source Redis cache entry
`dawarich/registration_enabled` into `phoenix.registration_setting`, preserving
an existing native row; a missing cache entry uses the explicit
`ALLOW_EMAIL_PASSWORD_REGISTRATION` environment policy. Copy happens under
existing exclusion. Do not derive it from new self-hosted
account defaults or run an independent web-time copy.

Storage service names remain `test`/`local`/`s3` (`config/storage.yml`,
`Dawarich.Storage.services!`), preserving each blob's stored `service_name` and
key. Local Rails and native layouts use `storage/<key[0:2]>/<key[2:4]>/<key>`;
test service uses `tmp/storage`. NEW/OLD need the same mount/object bucket and
signing/encryption inputs (`RailsSecret`, signed-storage owner A12b). Never copy
secret values into this census. Cloud bootstrap defaults UID/GID to 32767,
reexecutes with `gosu` and `HOME=APP_PATH/tmp`, and changes existing tmp/storage
ownership only when needed. Persistent public asset/storage mounts and access
by the retained 1.15.3 image require actual release-lane proof.

`JobOwnership` and native `Jobs.Ownership` share persisted owners and ordered
`FOR SHARE` effect locks; missing owners mean Sidekiq. The Lite archival cron
and archival mail keys form a joint unit. Owner flips are not permission to
invent an event: `JobCommands.produce` carries payload `source_job_id` into
outbox `event_id`, and `forward` accepts the original explicit ID. Delays,
locale, zone, operation and cron-slot identity must survive accepted forwarding.
Source enqueues made by accepted work are still new application publication;
retry/scheduled bookkeeping is distinct and must remain observable.

### Retained HTTP rows and envelopes

The supplied census lives at project `.scratch/route-ownership/`:
`route-ownership.md`, `classified-routes.json`, `counts.json`, `crosscheck.json`.
It inspected `4628a6659cf75db62b4cb09c813151268b01c630`, not this head: 374
rows (2 native, 195 conditional, 175 Rails, 2 redirect) for its self-hosted stand.
Its Cloud comparison leaves SELF_HOSTED unset, which still defaults true; its
2/184/186/2 totals do **not** prove explicit Cloud=false coverage. No custom
route-census harness or production queries were run here.

| Source registration | Native declaration/gate at this head | Disposition |
| --- | --- | --- |
| GET `/api/v1/health`, GET `/api/v1/ready` (`routes.rb:314–315`) | Neither is declared natively. Source health includes JobHealth; ready queries SQL/Redis and returns 503 on failure | Retained, unsupported natively here. A12f-1/2 owns envelope, status, headers and HEAD parity. No fabricated 200. |
| POST `/api/v1/subscriptions/callback` (`routes.rb:464`) | No native route; source SubscriptionsController owns authenticated subscription/family/cache effects | Retained, A11/A4/A12f-2 owner closure needed: auth, dedupe/watermark, rollback on failure. Route callbacks to NEW only after closure. |
| GET/POST `/users/sign_in` (Devise `routes.rb:268`) | AuthGate credentials handler requires opted-in flow and literal SELF_HOSTED=true | Retained; explicit Cloud=false cannot claim native credentials here. Provider/session tails belong to A11/A12f-2. |
| GET `/rails/active_storage/blobs/proxy/:signed_id/*filename` | Generic storage matching is insufficient; StorageGate explicitly returns false for blob proxy | Retained, A12b/A12f-2 owns signed proxy/representation/envelope parity and HEAD body suppression. |
| GET `/settings/background_jobs` (`routes.rb:66`) | A10Routes declares LiveView; AdminGate.background? requires self-hosted, supported user/settings and admitted GET/HEAD envelope | Retained, Cloud destination closure belongs to A12f-3 task 17/A12f-3o. Query duplicates, client markers and Turbo headers can hand back. |

Native redirects are not retirements. Unsupported Cloud envelopes, HEAD,
formats/content types, authenticated API keys and provider callbacks must be
closed by route owners before NEW is selected. Flipper/server PostHog/Heroku
retirement and Swagger/metrics/error-reporting are A12f-3o decisions, not this
package's changes.

### Accepted source work and native dependencies

The executable class census is `app-phoenix/test/support/rails_job_owners.ex`
and its inventory test: 125 application classes plus framework Active Storage
and Action Mailer jobs. `docs/phoenix/a12d3-schedules-drain.md` retains the
accepted-work dispositions; class labels alone never authorize deletion.
Accepted chains include Trips::CalculateAllJob, Tracks::ParallelGeneratorJob,
Tracks::RealtimeGenerationJob, Tracks::DailyGenerationJob, data migration
point/transportation/anomaly walkers, raw-data archive/verify/clear user chains,
integration schedulers (AirTrail/TeslaMate/Trek), digest scheduling/mail,
GoogleTakeout/GPX resumptions, EnhancedImport extraction and family callbacks.
Task 7 must settle any path requiring a fresh source child before switching.

Current dependencies remain: cache cron wrapper delegates to Rails; native
RailsCommands reverse kinds are not closed; source RailsCommands::Poller starts
on worker startup; cache_jobs publishes Cleaning/Preheating on Rails server boot;
Cloud User callbacks create welcome/explore/Manager and family work; Cloud family
release adapters refuse. L1/J1/J2 and source/native chain collision proofs are
external owner handoffs, not fulfilled by disabling these producers.

Source JobDrain observes queued/scheduled/retry/dead/busy/unknown work and SQL
bridge debt but lacks explicit reserved-fetch observation. Native Drain reports
outbox/reverse/release/Oban/generation/owner debt as observations, not permission
to stop OLD. Tasks 9/10 and actual G49 must close those observations. Ruling 7
rollback pins every key to Sidekiq, drains native work, stops Phoenix, then starts
Rails 1.15.3 on the same DB/storage; no transfer or backup restore is built here.

Baseline characterization: both existing Cloud/lifecycle regression files,
RSpec seed 101, **49 examples, 0 failures**. Allocated test resources:
Redis 7317, Rails `dawarich_test_a12f3c_a`, Phoenix
`dawarich_phoenix_test_a12f3c_a`. Swagger was copied aside/restored and no
schema/Swagger drift occurred. Implementation evidence is recorded separately
in `.scratch/orch/out/impl-a12f3c-a.report.md`.

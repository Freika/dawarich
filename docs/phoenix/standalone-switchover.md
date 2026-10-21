# Switching an existing self-hosted install to standalone

`DAWARICH_RAILS=off` refuses web startup while retained Rails work is present
or cannot be inspected. Historical ActiveJob/Sidekiq envelopes and all 78
reverse-command kinds remain in their original queues for the retained Rails
app to finish. The native boot check never imports, executes, acknowledges,
deletes or reschedules them. Fresh native jobs continue to use Oban.

This is a self-hosted transition procedure. Cloud native lifecycle remains
refused until the external L1 handoff; this procedure does not authorize Cloud
activation. Ordinary coexistence and the idle worker role are unchanged.

## Drain before switching

1. Keep the retained Rails image/app, shared database, Redis and storage
   available. Back them up. Use the existing coexistence deployment to finish
   accepted native work as well as source work. Fence external producers:
   remove web traffic, pause trackers/import clients and manual maintenance,
   and stop other cron publishers. A quiet worker alone does not fence producers.
2. Stop the ordinary Rails workers, then run this **one command** from the
   retained Rails app with its existing deployment environment. It starts the
   normal Sidekiq consumer and reverse Poller, disables cron loading and cron
   polling, and permits accepted jobs to publish their original continuations:

   ```sh
   RAILS_ENV="${RAILS_ENV:?}" DATABASE_NAME="${DATABASE_NAME:?}" REDIS_URL="${REDIS_URL:?}" bundle exec ruby -rsidekiq/cli -rsidekiq-cron -e 'Sidekiq::Cron.configure { |c| c.enabled = false; c.cron_poll_interval = 0 }; cli = Sidekiq::CLI.instance; cli.parse(["-C", "config/sidekiq.yml"]); cli.run'
   ```

   Use the same queue selector `RAILS_JOB_QUEUE_DB` as the old deployment
   (default **1**, overriding the Redis URL path). Preserve other existing
   settings, including storage, database and job ownership. Do not use the
   Cloud drain-only flag: it intentionally refuses source continuations and
   disables the reverse Poller. Jobs routed to native owners require the
   existing coexistence native workers to stay available until settled.
3. Observe `bundle exec rails dawarich:jobs:drain_status` and the existing
   native `dawarich jobs drain-status` under quiescence. Keep explicit
   `RAILS_ENV`, `DATABASE_NAME` and `REDIS_URL` on Rails commands. Future and
   retry jobs must finish at their accepted due times. Unknown or dead work
   requires its domain owner's repair and reviewed disposition. Do not clear
   Redis, delete commands, rewrite schedules or copy envelopes to Oban to make
   the check pass. Existing native drain status may still list residual
   producer dispositions; inspect its concrete debt alongside source status.
4. Quiet the retained worker, allow busy work to finish, then stop it gracefully
   using Sidekiq's normal TSTP/TERM lifecycle. Stop the existing native workers
   after their accepted work settles. Stop retained Rails web and manual
   processes after their in-flight requests settle. Reinspect after stop,
   including reservations and fresh worker heartbeats. Follow the heartbeat
   recovery step below before retrying standalone startup. The retained
   [source-drain procedure](a12d3-schedules-drain.md) covers unresolved work.
5. With producers still fenced, start the self-hosted web with
   `DAWARICH_RAILS=off`, using the same database, Redis queue database and
   storage. The check runs after existing release readiness and before the
   listener, Oban, native cron, ownership claims or relay starts. Re-enable
   traffic and native producers only after successful startup.

## Refusal and recovery

The operator error starts with `Standalone switch-over refused` and contains
only fixed reason names and counts. It links to this runbook. No payload,
credentials, process identity or exception details are emitted by the check.

The check observes all `queue:*` lists, including queues missing from Sidekiq's
queue registry; scheduled/retry/dead sets; live source processes; orphan work
hashes; and limit-fetch reservations, probes, live fetchers and heartbeat keys.
A standard Sidekiq registration counts as live while its `beat` is at most
60 seconds old, using Redis server time. Missing process hashes and expired
beats are ignored, matching Sidekiq's process liveness window. A present process
hash with a missing or malformed beat refuses inspection. A limit-fetch
registration counts as live only while its heartbeat key exists (the installed
plugin expires it after 20 seconds). Orphan heartbeat keys still block. Stored
cron definitions, queue names and queue limits alone are not pending work. SQL checks cover all retained reverse rows (due, future, leased
and retrying), reverse dead rows, pending forward outbox and quarantined outbox.
Existing native Oban jobs are not historical Rails envelopes and are not copied
or blocked by this source check.

### After the final worker stops

The limit-fetch plugin can leave `limit:processes` registrations permanently
after a graceful shutdown. With producers fenced, every retained worker and
Rails web/manual process stopped, and all accepted work/reservations settled,
run:

```sh
sleep 60
```

Then retry the same standalone startup from step 5. This lets the last Sidekiq
process heartbeat (60 seconds) and limit-fetch heartbeat (20 seconds) expire.
The observer ignores their stale registrations without deleting them. Waiting
is sufficient only after shutdown: a live worker renews its heartbeat and still
refuses startup, even with empty queues. Queued, scheduled, retry, dead, busy,
reserved, probed and SQL debt continue to block regardless of registration age.
If refusal remains, inspect the reported work counts and finish or repair that
work with the original consumers; do not remove registrations or payloads to
bypass the check.

Missing Redis configuration, wrong Redis types, unreadable Redis/SQL or missing
source tables refuse startup. Restore access/configuration, finish the normal
release migrations if needed, and retry. A partially drained queue or two
accepted copies of a job still blocks; repeated boot attempts change neither.

The check observes fenced stores; it cannot atomically lock SQL and Redis or
prevent an unfenced producer from enqueueing after inspection. Producer fencing
and worker shutdown are required even when counts are zero. This mechanism
adds no duplicate execution or work loss during switch-over. It preserves
Rails' existing at-least-once crash/retry behavior and does not promise
exactly-once external mail or webhook delivery.

# Single-process Rails deployment

The default `docker/docker-compose.yml` runs Puma and Sidekiq 8 in one Ruby
process with `SIDEKIQ_EMBEDDED=true`, `WEB_CONCURRENCY=0`, and
`BACKGROUND_PROCESSING_CONCURRENCY` defaulting to **2**. Use an image containing
this change:

```sh
docker compose -f docker/docker-compose.yml up -d
```

Redis and PostgreSQL remain separate required data services. Jobs consume every
queue in `config/sidekiq.yml`, including reverse geocoding, and load
`config/schedule.yml` through sidekiq-cron. Puma starts workers after boot and
drains them on shutdown or restart. Compose allows 60 seconds for shutdown.
The app healthcheck still uses `/api/v1/health`; no worker-container dependency
or worker-process healthcheck is needed. Embedded worker metrics are served by
the web process without fetching a separate container. Set `SIDEKIQ_METRICS_URL`
only to aggregate an additional standalone worker.

## Upgrade from a separate worker

Use the **old Compose file**, before replacing it, to stop and remove the old
worker gracefully:

```sh
docker compose -f docker/docker-compose.yml stop -t 60 dawarich_sidekiq
docker compose -f docker/docker-compose.yml rm -f dawarich_sidekiq
```

Then replace the Compose file and update the image to a release containing this
change. If the old worker was created by another Compose project or file, use
that project's original command to stop and remove it first. Stop any worker
that was started with the former override as well. Keep the same Redis/database
configuration and volumes: queued, scheduled and retry jobs stay in Redis and
are picked up by the web process. Do not delete Redis data or start both worker
setups unintentionally.

```sh
docker compose -f docker/docker-compose.yml up -d
```

The former embedded override has been removed. No additional Compose file or
profile is required. Existing environment files with
`BACKGROUND_PROCESSING_CONCURRENCY=10` should be reviewed: unset it or use `2`
for the small default. The default Compose file fixes `WEB_CONCURRENCY=0` and
`SIDEKIQ_EMBEDDED=true` to keep one application process.

## Capacity and other deployments

Keep `RAILS_MAX_THREADS` unset for the small default: Puma uses 5 web threads
and the database pool defaults to 10, covering the 2 embedded job threads.
If overriding thread counts, provision database connections for both requests
and jobs. Imports share Puma's heap and CPU.

Larger installations may still run standalone Sidekiq to isolate job resources.
For a custom deployment, unset `SIDEKIQ_EMBEDDED` (or set it to `false`) on the
web process and run `bundle exec sidekiq` separately with the same Redis,
database and shared storage. The image retains `sidekiq-entrypoint.sh` for this
use. Clustered Puma also supports embedding in each worker after forking.
The Cloud staging Compose file retains its explicit web/worker topology and
metrics URL; the devcontainer retains its interactive development setup.
Neither is the default self-hosted stack.

Verification: `spec/lib/dawarich/embedded_sidekiq_boot_spec.rb` boots real Puma
with isolated test resources, verifies an enqueued job and a cron job execute
with Puma's PID, then checks that Sidekiq drains and exits successfully.

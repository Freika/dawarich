# Single-process Rails profile

Set `SIDEKIQ_EMBEDDED=true` and `WEB_CONCURRENCY=0` to run Puma and Sidekiq 8 in
one Ruby process. `BACKGROUND_PROCESSING_CONCURRENCY` defaults to **2** in this
mode; the separate Sidekiq process retains its existing defaults. Embedded jobs
consume every queue in `config/sidekiq.yml`, including reverse geocoding, and
load `config/schedule.yml` through sidekiq-cron on startup. Puma starts the
workers after boot and drains them on shutdown or restart. Clustered Puma is
also supported: each worker starts its own embedded Sidekiq after forking.

Use the Compose override with an image containing this change:

```sh
docker compose -f docker/docker-compose.yml -f docker/docker-compose.embedded.yml up -d
```

The override moves the standalone Sidekiq service behind the `separate-workers`
profile and allows 60 seconds for shutdown. When switching an existing install,
stop its old Sidekiq service first. Redis and PostgreSQL remain required; this
profile combines the application processes, not the data services. Do not also
start a standalone worker unless the additional concurrency is intentional.

Without the override or switch, the existing separate-services setup is
unchanged. Keep `RAILS_MAX_THREADS` unset for the small profile: Puma defaults
to 5 web threads and the database pool defaults to 10, covering the 2 embedded
job threads. If overriding thread counts, provision database connections for
both web requests and jobs. Memory-heavy imports still share Puma's heap and
CPU; separate workers remain useful for larger installations.

Verification: `spec/lib/dawarich/embedded_sidekiq_boot_spec.rb` boots the real
Puma configuration with isolated test resources, verifies both an enqueued job
and a cron job execute with Puma's PID, then terminates Puma and checks that
Sidekiq drains and exits successfully.

# Dawarich Cloud staging on Dokploy

This config moves **staging only** from Dokku to the existing Dokploy server
`gigawarich`. It runs the Cloud app in `RAILS_ENV=production`, with one web
container and one Sidekiq container. Uploads stay in Cloudflare R2. Production
remains on Dokku until staging has been verified and its cutover rehearsed.

Use [`compose.dokploy.staging.yml`](../compose.dokploy.staging.yml) as a Dokploy
Compose service from this repository. The app image must contain this PR's
Cloud entrypoint and a reviewed release commit. Pin `DAWARICH_IMAGE` to a
published `freikin/dawarich@sha256:…` digest; never use `latest` for the
migration.
The Compose service uses `cloud-entrypoint.sh` from this PR to run Puma,
Sidekiq, and one-off migrations as UID 32767. It deliberately bypasses the
self-hosted `web-entrypoint.sh`, which would run schema migrations, data
migrations, and seeds on every web restart. Build the image from a commit
containing this PR before using the Compose file.

## Before creating the app service

1. Record the current Dokku staging commit, the names of all environment
   variables, process counts, R2 bucket/endpoint, PostgreSQL version/size,
   Redis queue depth, and watched-import directory contents. Transfer secret
   **values** directly into Dokploy's Environment tab; never put them in Git,
   a PR, or AFFiNE. Confirm the R2 bucket and Manager URLs belong to staging.
2. Create dedicated staging PostgreSQL/PostGIS and Redis services on Dokploy.
   Restore a recent staging database copy for rehearsal and verify PostGIS and
   row counts. This copy will be replaced after old staging writes are stopped.
   Restore Redis state if queued/scheduled jobs must be retained; otherwise
   first drain the old Sidekiq queues and document which transient caches can
   be discarded. Keep both backing services private on `dokploy-network` and
   configure persistent storage and backups there. Do not point staging at
   `dawarich_production` or a production Redis instance.
3. Publish the Docker image for the chosen release commit (including this
   entrypoint) and note its digest. Rehearse migrations from the restored
   staging schema to that commit's schema.
   The GitHub image workflow can build a selected branch manually; verify the
   resulting image digest and architecture before assigning it to Dokploy.
4. Add the variables below in Dokploy. Dokploy writes them to `.env`; the
   Compose `env_file` passes the remaining existing Cloud settings to web,
   worker, and the release task. The explicit Compose values override `.env`
   where staging must be fixed. Do not set `DATABASE_URL` as a substitute for
   the discrete database variables: `config/database.yml` reads those keys.
   [`compose.dokploy.staging.env.example`](../compose.dokploy.staging.env.example)
   lists the required names without secret values.

| Variable | Staging value / purpose |
| --- | --- |
| `DAWARICH_IMAGE` | Published immutable image digest. |
| `WEB_REPLICAS`, `WORKER_REPLICAS` | Set both to `0` for the initial restore/release; set web to `1` for checks, then worker to `1` after stopping Dokku workers. |
| `STAGING_HOST` | `staging.dawarich.app` after confirming the live domain. |
| `APPLICATION_HOSTS` | Comma-separated staging and temporary preview hostnames. |
| `MANAGER_URL` | HTTPS URL of **staging** Manager. |
| `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USERNAME`, `DATABASE_PASSWORD` | Dedicated staging PostGIS connection. |
| `REDIS_URL` | Dedicated staging Redis base URL; app code selects its own cache and Sidekiq DB numbers. |
| `RAILS_MASTER_KEY`, `SECRET_KEY_BASE` | Existing staging values, so encrypted data and sessions remain usable. |
| `AUTH_JWT_SECRET_KEY`, `JWT_SECRET_KEY`, `SUBSCRIPTION_WEBHOOK_SECRET` | Existing staging secrets; the last two must match staging Manager. |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `AWS_BUCKET`, `AWS_ENDPOINT_URL` | Existing staging R2 credentials, bucket, region, and endpoint. |

Carry over the other **staging** Dokku settings required by the app: OTP
encryption keys, SMTP, OAuth, Photon, metrics credentials and exporter flag,
feature flags, and integrations. Check each key against the running staging
environment; the repository's `.env.example` is incomplete for Cloud. The
Compose file sets `SELF_HOSTED=false`, `STORAGE_BACKEND=s3`, and HTTPS. If
staging uses the same R2 bucket as production, check that test uploads and
deletions cannot affect production objects before starting the new workers.

## Release and cutover

1. In Dokploy, create the Compose service from the repository file and set its
   environment with `WEB_REPLICAS=0` and `WORKER_REPLICAS=0`. This permits
   image pull and volume/network setup without starting app processes against
   an unfinished restore. Configure a preview
   hostname for the `web` service on container port `3000`. Do not publish the
   worker's port `9394` or either backing service publicly. Dokploy's Domains
   tab can route to the web service; no host port mapping is needed.
2. With the rehearsal database and selected image, run the one-off
   `release` profile (`docker compose -f compose.dokploy.staging.yml run --rm
   release`) from the Dokploy service's Compose directory, or execute
   `bundle exec rails db:migrate` once in the matching image through Dokploy's
   terminal. The release profile does **not** run on ordinary deploys. Run any
   release-specific data migration separately if that release requires one.
3. Set `WEB_REPLICAS=1` and redeploy. On the preview hostname, test
   `/api/v1/health`, sign-in, map rendering, Sidekiq enqueueing, an R2
   attachment, and SMTP. The old Dokku worker remains the only active worker;
   the new Redis queues will be replaced at final restore. Preview writes to
   the copied database will also be discarded. Check web logs and `/metrics`
   if enabled.
4. Freeze staging writes: stop the old Dokku web and workers and wait for
   in-flight jobs to finish. Set `WEB_REPLICAS=0` on Dokploy and redeploy so
   the preview app cannot write either. Take a **final** staging database and
   Redis backup, restore them to Dokploy, and compare row counts and queue
   depths. Rerun the release migration against this final copy. Carry over
   any watched-import files that need processing.
5. Set `WEB_REPLICAS=1` and `WORKER_REPLICAS=1`, redeploy, and switch
   `staging.dawarich.app` to Dokploy. Verify Sidekiq processing and schedules,
   DNS, TLS, redirects, host authorization, a mobile points upload,
   import/export, and a staging Manager callback. Confirm staging Manager's
   `DAWARICH_URL`. Keep Dokku available for rollback.
6. To roll back, stop Dokploy web/worker before restarting Dokku and reverse
   the route. Recheck the database schema against the old image first; a
   non-backward-compatible migration can make an image-only rollback unsafe.
   After cutover, new writes and jobs exist only in Dokploy's database/Redis;
   reconcile or transfer them before using the old Dokku state. Preserve the
   same R2 bucket and keep only one active worker fleet.

The named `watched-imports` volume preserves the directory consumed by
`Import::WatcherJob`. R2 holds Active Storage objects, so no local storage or
public-assets volume is needed; compiled assets remain inside the image.
Update the monitoring target after the switch. The existing production
Prometheus configuration still points to `my.dawarich.app` and is outside
this staging PR.

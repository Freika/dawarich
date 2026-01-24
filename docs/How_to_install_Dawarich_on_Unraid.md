# How to install Dawarich on Unraid

> [!WARNING]
> **Do not use autoupdate** and **do not update** any Dawarich container **without** [**backing up your data**](https://dawarich.app/docs/tutorials/backup-and-restore) first and checking for breaking changes in the [updating guides](https://dawarich.app/docs/updating-guides)!
>
> *Dawarich is still in beta and a rapidly evolving project, and some changes may break compatibility with older versions.*

This guide is written for:

- Unraid OS 7.1.4
- Dawarich 0.33.0

## Installation methods: CA Templates vs. Docker Compose

For Dawarich to run 4 docker containers are required:

- `dawarich_db` - PostgreSQL database
- `dawarich_redis` - Redis database
- `dawarich_app` - Dawarich web application
- `dawarich_sidekiq` - Sidekiq worker (for background jobs)

> [!NOTE]
> Some containers depend on others to be running first. Therefore this guide will follow this order: `dawarich_db` >> `dawarich_redis` >> `dawarich_app` >> `dawarich_sidekiq`.

[Usually](https://dawarich.app/docs/intro/) all 4 containers are created and started together using [Docker Compose](https://docs.docker.com/compose/). Unraid [does not support Docker Compose natively](https://docs.unraid.net/unraid-os/using-unraid-to/run-docker-containers/overview/). Instead, it uses its own implementation of `DockerMan` for managing Docker containers via [Community Applications (CA)](https://docs.unraid.net/unraid-os/using-unraid-to/run-docker-containers/community-applications/) plugin.

However, there is a [Docker Compose Manager](https://forums.unraid.net/topic/114415-plugin-docker-compose-manager/) plugin that can be used to [setup and run Dawarich using Docker Compose](https://github.com/Freika/dawarich/discussions/150). This method is not covered in this guide.

*Feel free to contribute a PR if you want to add it.*

## Support for Unraid CA Templates

> [!IMPORTANT]
> Since [Freika is not maintaining the Unraid CA templates](https://github.com/Freika/dawarich/issues/1382), all Unraid-related issues should be raised in the appropriate repositories or Unraid forum threads:
>
> - `dawarich_db` & `dawarich_redis` [Github](https://github.com/pa7rickstar/unraid_templates) and [Unraid forum](https://forums.unraid.net/topic/193769-support-pa7rickstar-docker-templates/)
> - `dawarich_app` & `dawarich_sidekiq` [Github](https://github.com/nwithan8/unraid_templates) and [Unraid forum](https://forums.unraid.net/topic/133764-support-grtgbln-docker-templates/)

There is an official [PostGIS](https://hub.docker.com/r/postgis/postgis) CA you can use for `dawarich_db` and an official [redis](https://forums.unraid.net/topic/89502-support-a75g-repo/) CA you can use for `dawarich_redis`. However, if you don’t want to set up the correct volume paths, environment variables, health-checks and arguments by yourself, [Pa7rickStar](https://github.com/pa7rickstar) has created CA for [`dawarich_db`](https://github.com/pa7rickstar/unraid_templates/blob/main/templates/dawarich_db.xml) and [`dawarich_redis`](https://github.com/pa7rickstar/unraid_templates/blob/main/templates/dawarich_redis.xml) which are preconfigured for an easy Dawarich installation.

For [`dawarich_app`](https://github.com/nwithan8/unraid_templates/discussions/273) and [`dawarich_sidekiq`](https://github.com/nwithan8/unraid_templates/discussions/310) [grtgbln](https://forums.unraid.net/profile/81372-grtgbln/) aka. [nwithan8 on Github](https://github.com/nwithan8) is [maintaining](https://github.com/Freika/dawarich/issues/928#issuecomment-2749287192) Unraid CA templates.

> [!NOTE]
> All 4 CA use the official docker hub repositories of redis, PostGIS, Dawarich and Sidekiq.

## Installation

> [!IMPORTANT]
> This guide assumes you will name the containers `dawarich_redis`, `dawarich_db`, `dawarich_app` and `dawarich_sidekiq`. You can use other names, but make sure to adjust the settings accordingly or use IP addresses and ports instead.

### 1. (Optional) Setup user-defined bridge network

The [docker-compose file](https://github.com/Freika/dawarich/blob/master/docker/docker-compose.yml) usually used to set up Dawarich creates a user-defined bridge network for Dawarich containers so they are isolated in their own network and are still able to communicate with each other. This step is optional, but [it is a good practice](https://trash-guides.info/File-and-Folder-Structure/How-to-set-up/Unraid/#setting-up-the-containers) to do so.

> [!NOTE]
> Check out this [video on YouTube](https://www.youtube.com/watch?v=bKFMS5C4CG0) if you want to learn how different network drivers work in Docker.

#### 1. Set Unraid to preserve user-defined networks

By default user created networks are removed from Unraid when Docker is being restarted. This is done to prevent potential conflicts with the automatic generation of custom networks. If you want to use a user-defined bridge network for Dawarich containers, you need to change this behavior. Go to `Settings` -> `Docker` -> enable `Advanced View` and set `Preserve user defined networks` to `Yes`.
Docker has to be stopped so that the setting can be changed.

> [!WARNING]
> Change this setting to preserve user defined networks, but it is the responsibility of the user to ensure these entries work correctly and are conflict free.

#### 2. Create the user-defined bridge network

To create an user-defined bridge network called `dawarich`, open the terminal on your Unraid server and run:

```bash
docker network create dawarich
```

> [!NOTE]
> You can check if the network was created successfully by running:
>
> ```bash
> docker network ls
> ```

### 2. Install `dawarich_db` container

Install the `dawarich_db` CA template from `Pa7rickStar's Repository`.

- The container Name `dawarich_db` will be used by other containers instead of an IP address and port. If you use this method, you don't need set the `Database port` in this template (there is also no need to access the database directly).
- You can leave the `Extra Parameters` as is.
- `--restart=always` in the `Extra Parameters` field (you have to turn on `ADVANCED VIEW` in the top right corner to see this field) will make sure the container is restarted automatically if it crashes.
  > [!NOTE]
  > This will cause the container to start after you boot the host [even if autostart is set to off](https://forums.unraid.net/topic/57181-docker-faq/page/2/#findComment-600177).
- If you have set up a user-defined bridge network in the first step, select it under `Network Type`. Otherwise, leave it at `bridge`.
- The default `Database username` is fine. You should set a strong `Database password`.
  > [!NOTE]
  > You can change the `Database password` without having the old one from the Unraid (host) Terminal by running:
  >
  > ```bash
  > docker exec -it dawarich_db \
  >  psql -U postgres -d postgres -c "ALTER ROLE postgres WITH PASSWORD 'NEW_STRONG_PASSWORD';"
  >```
  >
  > Replace `NEW_STRONG_PASSWORD` with your new password and keep the `''`.

### 3. Install `dawarich_redis` container

Install the `dawarich_redis` CA template from `Pa7rickStar's Repository`.

- The container Name `dawarich_redis` will be used by other containers instead of an IP address.
- `--restart=always` in the `Extra Parameters` field (you have to turn on `ADVANCED VIEW` in the top right corner to see this field) will make sure the container is restarted automatically if it crashes.
  > [!NOTE]
  > This will cause the container to start after you boot the host [even if autostart is set to off](https://forums.unraid.net/topic/57181-docker-faq/page/2/#findComment-600177).
- If you have set up a user-defined bridge network in the first step, select it under `Network Type`. Otherwise, leave it at `bridge`.
- If you have no port conflicts, leave the `Redis Port` at default value. Otherwise, change it to a free port. This port has to be used later in the `dawarich_app` and `dawarich_sidekiq` containers.

### 4. Install `dawarich_app` container

Install the `dawarich_app` CA template from `grtgbln's Repository`.

- You do not need to change the container Name to `dawarich_app` as other containers won't establish a connection by themselves.
- Set `Extra Parameters` (you have to turn on `ADVANCED VIEW` in the top right corner to see this field) to:
  
  ```bash
  --entrypoint=web-entrypoint.sh --restart=on-failure --health-cmd='wget -qO- http://127.0.0.1:3000/api/v1/health | grep -q "\"status\"[[:space:]]*:[[:space:]]*\"ok\"" || exit 1' --health-interval=10s --health-retries=30 --health-start-period=30s --health-timeout=10s
  ```

  > [!NOTE]
  > The `--restart=on-failure` parameter will make sure the container is restarted automatically if it crashes. This *might* cause the container to start after you boot the host [even if autostart is set to off](https://forums.unraid.net/topic/57181-docker-faq/page/2/#findComment-600177).
- If you have set up a user-defined bridge network in the first step, select it under `Network Type`. Otherwise, leave it at `bridge`.
- If you have no port conflicts, leave the `Web Port` at default value. Otherwise, change it to a free port. This port will be used to access the Dawarich web interface. In this case make sure to set the same port for `WebUI` (default value is `http://[IP]:[PORT:3000]/`).
- If you haven't changed any file paths in the previous containers, you can leave all the paths at default values. Otherwise, set the correct paths.
- Set the `Redis URL` to `redis://dawarich_redis:6379/0` if you are using the container name `dawarich_redis` and the default port in the redis container.
- Set the `PostGIS - Host` to `dawarich_db` if you are using the container name `dawarich_db`. Otherwise use the IP address.
- Set `PostGIS - Username`, `PostGIS - Password` and `PostGIS - Database` to the same values you used in the setup of your `dawarich_db` container.
- For any other settings refer to the [official documentation for environment variables and settings](https://dawarich.app/docs/environment-variables-and-settings).

  > [!WARNING]
  > The CA template sets `PHOTON_API_HOST` to `photon.komoot.io` and `STORE_GEODATA` to `true` by default. This means the container will try to translate your location data (longitude, latitude) to addresses, cities etc. and [save the result in the database](https://github.com/Freika/dawarich/discussions/1457). In order to do so, the app will [send your data to the service provider, which might raise privacy concerns](https://dawarich.app/docs/tutorials/reverse-geocoding/). If you don't want this behavior you should leave `PHOTON_API_HOST` empty! You cold also [set up your own reverse geocoding service](#setup-reverse-geocoding).

### 5. Install `dawarich_sidekiq` container

Install the `dawarich_sidekiq` CA template from `grtgbln's Repository`.

- The same notes as for the `dawarich_app` container apply here.
- Set `Extra Parameters` (you have to turn on `ADVANCED VIEW` in the top right corner to see this field) to:
  
  ```bash
  --entrypoint=sidekiq-entrypoint.sh --restart=on-failure --health-cmd='pgrep -f sidekiq >/dev/null || exit 1' --health-interval=10s --health-retries=30 --health-start-period=30s --health-timeout=10s
  ```

  > [!NOTE]
  > The `--restart=on-failure` parameter will make sure the container is restarted automatically if it crashes. This *might* cause the container to start after you boot the host [even if autostart is set to off](https://forums.unraid.net/topic/57181-docker-faq/page/2/#findComment-600177).

> [!WARNING]
> The CA template sets `PHOTON_API_HOST` to `photon.komoot.io` and `STORE_GEODATA` to `true` by default. This means the container will try to translate your location data (longitude, latitude) to addresses, cities etc. and [save the result in the database](https://github.com/Freika/dawarich/discussions/1457). In order to do so, the app will [send your data to the service provider, which might raise privacy concerns](https://dawarich.app/docs/tutorials/reverse-geocoding/). If you don't want this behavior you should leave `PHOTON_API_HOST` empty! You cold also [set up your own reverse geocoding service](#setup-reverse-geocoding).

## Post installation

### 1. Starting the containers

The containers should start automatically when you are setting them up for the first time. If not, start them manually in the Unraid web interface. Use the correct order: `dawarich_db` >> `dawarich_redis` >> `dawarich_app` >> `dawarich_sidekiq`.

### 2. Health checks

According to the [Unraid documentation](https://docs.unraid.net/unraid-os/using-unraid-to/run-docker-containers/overview/#health-checks), colored health indicators next to each container’s icon are shown in the Unraid web interface when health checks are configured in the containers. Depending on the selected theme the container health might be indicated by text in the `uptime` column instead.

You can check the health status of the containers from the Unraid (host) Terminal:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

This should show something like this:

```bash
root@tower# docker ps --format 'table {{.Names}}\t{{.Status}}'
NAMES              STATUS
dawarich_sidekiq   Up About a minute (healthy)
dawarich_app       Up About a minute (healthy)
dawarich_db        Up About a minute (healthy)
dawarich_redis     Up About a minute (healthy)
```

If not, you can check the health status of each container individually:

```bash
docker inspect --format '{{json .State.Health}}' dawarich_db | jq
docker inspect --format '{{json .State.Health}}' dawarich_redis | jq
docker inspect --format '{{json .State.Health}}' dawarich_app | jq
docker inspect --format '{{json .State.Health}}' dawarich_sidekiq | jq
```

> [!NOTE]
> There is a difference between `liveness` and `readiness` probes. Simply put:
>
> - `liveness` = "is the process up?"
> - `readiness` = "can it do useful work?"
>
> The health checks configured in the `dawarich_app` and `dawarich_sidekiq` containers are `liveness` probes. This means that they will show `healthy` as long as the main process is running, even if the application is not fully started yet. So it might take a while until Dawarich is actually ready to use, even if the health check shows `healthy`. This also means that the health check will show `healthy` even if the application is not fully functional (e.g. if it can not connect to the database). You should check the logs of the `dawarich_app` container for any errors if you suspect that something is wrong.

### 3. Check the logs

You should check the Logs of each container for any errors.

> [!NOTE]
> You might see this warning in the `dawarich_redis` container:
>
> ```bash
> # WARNING Memory overcommit must be enabled! Without it, a background save or replication may fail under low memory condition. Being disabled, it can also cause failures without low memory condition, see https://github.com/jemalloc/jemalloc/issues/1328. To fix this issue add 'vm.overcommit_memory = 1' to /etc/sysctl.conf and then reboot or run the command 'sysctl vm.overcommit_memory=1' for this to take effect.
> ```
>
> The `sysctl vm.overcommit_memory=1` command referenced there has to be run on the Unraid host (not in the container). As of now the author of this guide can not confidently advice on this, so please check the [Unraid forum](https://forums.unraid.net/) for help.

## Setup Reverse Geocoding

> [!NOTE]
> Please check out the Dawarich [docs on reverse geocoding](https://dawarich.app/docs/tutorials/reverse-geocoding).

### 1. Install `Photon` container

If you want to [set up your own reverse geocoding service](https://dawarich.app/docs/tutorials/reverse-geocoding/#setting-up-your-own-reverse-geocoding-service) install the `Photon` CA template from `Pa7rickStar's Repository` and change the [environment variables](https://github.com/rtuszik/photon-docker?tab=readme-ov-file#configuration-options) to your liking.

- To reduce the load on the official Photon servers you can use the [community mirrors](https://github.com/rtuszik/photon-docker?tab=readme-ov-file#community-mirrors).
- The default value for `REGION` is `planet` which might be more than you need.

  > [!WARNING]
  > Large file sizes! This might take more than 200GB depending on the selected region. See here for the [available regions](https://github.com/rtuszik/photon-docker#available-regions).

### 2. Post installation

Check the logs after the container started. Photon should download the index files for the `REGION` you set.

After the index files are downloaded and Photon is ready, you can check if it is working by opening in a webbrowser:

```zsh
http://localhost:[PORT]/api?q=Berlin
```

### 3. Configure Photon for Dawarich

In your `dawarich_app` and `dawarich_sidekiq` containers:

- Set the `Photon API - Host` to `[IP]:[PORT]` of your `Photon` container (without the `[]`).
- Set `Photon API - Use HTTPS` to `false`.
- Restart the containers in the [correct order](#1-starting-the-containers).

*2025-10-07 by [Pa7rickStar](https://github.com/Pa7rickStar) with contributions from [nwithan8](https://github.com/nwithan8).*

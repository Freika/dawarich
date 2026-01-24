# How to install Dawarich using Docker

> To do that you need previously install [Docker](https://docs.docker.com/get-docker/) on your system.

To quick Dawarich install copy the contents of the `docker-compose.yml` file from project root folder to dedicated folder in your server and run `docker compose up` in this folder.

This command use [docker-compose.yml](../docker/docker-compose.yml) to build your local environment.

When this command done successfully and all services in containers will start you can open Dawarich web UI by this link [http://127.0.0.1:3000](http://127.0.0.1:3000).

Default credentials for first login in are `demo@dawarich.app` and `password`.

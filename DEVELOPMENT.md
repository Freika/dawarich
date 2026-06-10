If you want to develop with dawarich you can use the devcontainer, with your IDE. It is tested with visual studio code.

**NOTE:** On Apple Silicon (M1/M2/M3), `postgis/postgis:17-3.5-alpine` is not available due to architecture mismatch.
In `.devcontainer/docker-compose.yml`, replace it with `imresamu/postgis:17-3.5-alpine` instead before building the container.

Load the directory in Vs-Code and press F1. And Run the command: `Dev Containers: Rebuild Containers` after a while you should see a terminal.

Now you can create/prepare the Database (this need to be done once):
```bash
bundle exec rails db:prepare
```

Afterwards you can run sidekiq:
```bash
bundle exec sidekiq

```

And in a second terminal the dawarich-app:
```bash
bundle exec bin/dev
```

You can connect with a web browser to http://127.0.0.1:3000/ and login with the default credentials.

---

## Native setup (without devcontainer)

### Prerequisites

- **Ruby** — version specified in `.ruby-version` (currently 3.4.6). Use `rbenv`, `asdf`, or `mise`.
- **PostgreSQL ≥ 14** with the **PostGIS** extension, listening on `localhost:5432`.
- **Redis**, listening on `localhost:6379`.

### Environment

```bash
cp .env.example .env
# Edit .env and fill in the required values (see comments in .env.example).
```

`config/database.yml` reads discrete `DATABASE_HOST`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`, `DATABASE_NAME`, and `DATABASE_PORT` variables — **not** a single `DATABASE_URL`.

### First run

```bash
bundle install
bundle exec rails db:prepare    # creates databases and runs migrations
bundle exec sidekiq &           # background job worker (keep running)
bundle exec bin/dev             # starts the web server + asset pipeline
```

Open http://127.0.0.1:3000/ and log in with the default credentials:

- **Email:** `demo@dawarich.app`
- **Password:** `safepassword`

### Running the test suite

```bash
RAILS_ENV=test bundle exec rspec
```

Dotenv automatically loads `.env.test` so no extra setup is needed.

> ⚠️ **Never run `rails db:test:prepare` or `rails db:schema:load` against an existing local database that has the `tiger_geocoder` extension** (common on long-lived local Postgres installs). The schema load fails midway and leaves `dawarich_test` empty. If your test DB breaks, rebuild it by cloning a known-good database with `pg_dump`/`pg_restore` — fresh databases (new containers, CI) load `db/schema.rb` without issue.

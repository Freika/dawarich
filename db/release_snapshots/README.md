# Release schema snapshots

One snapshot per migration state in `db/release_migrations.json` (87 states covering 259 release tags), plus every
shipped `db/schema.rb` that differs from its state's snapshot. The Ecto migrator (ADR 0015, roadmap step C2) consumes
them. Everything the README cites lives in this directory; `tmp/schema_parity/` (git-ignored) only holds local run
output: logs, diffs, `summary.txt`, `summary_schemarb.txt`.

| File | Contents |
|---|---|
| `<state>.image.sql.gz` | The state as a released Docker image built it by running migrations from an empty database (fallbacks: see `provenance.tsv`) |
| `<state>.replay.sql.gz` | The state as `scripts/schema_parity/replay.rb` built it by running the state's migration versions with current code; no release of the state has an image on Docker Hub |
| `<release>.schemarb.sql.gz` | That release's shipped `db/schema.rb`, loaded with current code, with the ledger a real fresh install of that release wrote. Stored only when it differs from its state's snapshot |
| `provenance.tsv` | Per state: file, method, image tag used, state it was upgraded from, Docker Hub digest of that tag |
| `schemarb.tsv` | Per shipped `db/schema.rb` blob and state: the releases that shipped it, `identical`/`differs`/`unloadable`, diff line count, stored file |

Every `.sql.gz` is `pg_dump --schema-only` followed by the data of `schema_migrations`, `ar_internal_metadata` and,
when it exists, `data_migrations`.

## Coverage

| States | From images | Replayed | Failed |
|---|---|---|---|
| 87 | 75 | 12 | 0 |

`provenance.tsv` gives the method of each state:

| Method | States | Meaning |
|---|---|---|
| `image` | 68 | The first release's own image, from an empty database |
| `image-upgrade` | 4 | 1.3.2 (from 1.3.1), 1.7.0 (from 1.6.0), 1.7.1 (from 1.7.0), 1.7.2 (from 1.7.1): the release's own image could not migrate from an empty database, so it upgraded the previous state's snapshot |
| `image-sibling` | 3 | 0.12.0 with the 0.12.1 image, 0.37.0 with 0.37.1, 0.29.0 with 0.29.1: a later release of the same state built it from an empty database |
| `replay` | 12 | 0.0.8 to 0.8.3: none of the 51 release tags of these states has an image (the Docker Hub tags API returned 404 for every one on 2026-09-24) |

The Hub digests were read from the tags API on 2026-09-24; they identify the images available now, not necessarily the
bytes a user pulled when the release came out.

### Why the fallbacks exist

Every image snapshot runs migrations from an empty database with the `db/schema.rb` fast path switched off
(`SCHEMA=/tmp/schema_parity_no_fast_path.rb`). A real fresh install of these releases never ran those migrations; it
loaded `db/schema.rb` (see "Which fresh install"). The fallbacks are therefore harness workarounds, not installation
paths. The migration defects behind them, and one the schema.rb drift causes, did hit real users on upgrades:

- **1.3.2**: `20260112192240 SetExistingUsersToMapV1` loads the `User` model, whose `enum :plan` column arrives later
  in the same run (`20260301201446`): `Undeclared attribute type for enum 'plan' in User`. Upgrades from 1.0.0 or
  earlier into 1.3.2 crash; fixed in 1.3.3 by `160741ee1` (raw SQL, issue #2362).
- **1.7.0 to 1.7.2**: `20260301202147 SetPlanForExistingUsers` loads `User`, whose `enum :subscription_source` column
  arrives later (`20260420190307`): `Undeclared attribute type for enum 'subscription_source' in User`. Upgrades from
  1.3.1 or earlier into 1.7.0 to 1.7.2 crash; fixed in 1.7.3 by `73cbcb1ee` (issue #2576).
- **0.37.0**: `20251227223614 ChangeDigestsDistanceToBigint` calls `safety_assured`, which `strong_migrations`
  provides only in the development and test bundles. Every 0.36.x to 0.37.0 upgrade stops there; fixed in 0.37.1
  (`6ed6a4fd8`).
- **0.19.2 and 0.19.3 fresh installs**: their shipped schema.rb already has `points.reverse_geocoded_at`, but
  `20241202114820 AddReverseGeocodedAtToPoints` is not in their ledger and has no guard in 0.19.4 and 0.19.5.
  Reproduced: restoring `0.19.2.schemarb.sql.gz` and running the 0.19.4 image's `db:migrate` stops with
  `PG::DuplicateColumn: column "reverse_geocoded_at" of relation "points" already exists`. 0.19.6 added
  `return if column_exists?` (`b1c48076e`).
- **0.12.0**: the data migration `20240808133112 RunInitialVisitSuggestion` calls `VisitSuggestingJob.perform_in`,
  which an ActiveJob class does not have. `rake data:migrate` aborts on every 0.12.0 install, fresh or upgraded, so
  0.12.0 installs reached the schema state without `20240808133112` and `20240822094532` in `data_migrations`; fixed in
  0.12.1 (`d11cfd864`). The snapshot, built by 0.12.1, has both.

Harness artefacts fixed along the way: `rails db:seed` runs before `rake data:migrate` for every image (0.9.x's
`20240713103122 MakeFirstUserAdmin` calls `User.first.update!`, and a real `db:prepare` seeds first), and every image
run gets dummy `OTP_ENCRYPTION_*` values (1.7.0 refuses to boot in production without them). Neither changes a schema.

## Which "fresh install"

Three different builds are called "fresh" in this work:

1. **Release code, migrations from empty**: every `.image.sql.gz` (the image runs its own migrations, fast path off).
2. **Current code, migrations from empty**: the reference `compare.sh` diffs against (`bin/rails db:migrate` on an
   empty database with `SCHEMA` pointing at a throwaway file, so the fast path is off).
3. **Shipped schema.rb**: what a real fresh install of every release did. 0.0.8 to 0.21.x run `db:create` and
   `db:prepare` (`dev-docker-entrypoint.sh`), which load `db/schema.rb` when `schema_migrations` does not exist yet.
   From 0.22.0, `docker/web-entrypoint.sh` creates the database and runs `db:migrate`; since Rails 8.0.0
   (activerecord CHANGELOG: "When running `db:migrate` on a fresh database, load the databases schemas before running
   migrations") that also loads `db/schema.rb` first. No release ships a migration newer than its schema.rb
   `define(version:)`, so a real fresh install is exactly the schema.rb load, with the ledger `{define version} ∪
   {release migrations below it}`, followed by all of the release's data migrations.

## Upgrade from each snapshot (current `db:migrate`) vs build 2

`compare_all.sh`: restore the snapshot, run current `bin/rails db:migrate`, canonicalise, diff against build 2.
All 87 states: 0 diff lines. The same check on the 29 `.schemarb.sql.gz` variants (`summary_schemarb.txt`) is not
clean: 20 of them keep a difference (see "Shipped schema.rb drift").

## Image vs replay (build 1 vs current code replaying the same versions)

| Release | Diff lines | What differs |
|---|---|---|
| 0.23.0 | 11 | `unique_points_index` in the image, `unique_points_lat_long_timestamp_user_id_index` in the replay (see "State 0.23.0 has two schemas") |
| 0.37.0, 0.37.2, 1.0.1, 1.0.2, 1.1.0, 1.3.0, 1.3.1, 1.3.2, 1.3.3, 1.3.4, 1.4.0, 1.5.0, 1.6.0, 1.7.0, 1.7.1 (15) | not reproducible | Their migration set includes `20251228163703_install_rails_pulse_tables.rb`, which reached release history through `8d2ade1bd` (the 0.37.0 release commit, #2067) and was deleted from `db/migrate` by `a5172cc1f` ("Remove RailsPulse"); 1.7.2's own `20260429180000_drop_rails_pulse_tables.rb` drops the tables. `compare.sh` reports `replay:not-reproducible missing:20251228163703` |
| the other 59 image states, including 0.29.0 | 0 | |

### State 0.23.0 has two schemas

0.23.0 shipped `20250120154555_add_unique_index_to_points.rb` creating `unique_points_index`; 0.23.1 to 0.23.3 ship
the same version creating `unique_points_lat_long_timestamp_user_id_index` (renamed by `4c6baad5d`). The cleanup
`20250221194430` (first in 0.25.0) removes only the new name, so installs that started at 0.23.0 keep
`unique_points_index` until `20260714090000` (1.10.1) drops `points.latitude` and the index with it. The snapshot holds
the 0.23.0 variant; replaying with current code, and the shipped schema.rb of 0.23.1 to 0.23.3, give the other one.
Docker Hub also has a `0.23.4` image that no release tag matches; git has only `0.23.4-rc`, whose migration set equals
state 0.23.0's and whose `20250120154555` uses the new name.

### Migration files edited within a state

13 other states contain a migration file whose content changed between their releases. None of these edits changes
the resulting schema once the migration has run:

| State | File | Releases per version | Effect |
|---|---|---|---|
| 0.12.0 | `db/data/20240713103122_make_first_user_admin.rb` | 0.12.0–0.13.3, 0.13.4–0.15.7 | data only |
| 0.12.0 | `db/data/20240808133112_run_initial_visit_suggestion.rb` | 0.12.0, 0.12.1–0.15.7 | `perform_in` → `perform_later` (the 0.12.0 crash above) |
| 0.15.8 | `db/data/20240610170930_remove_points_without_coordinates.rb` | 0.15.8–0.15.9, 0.15.10–0.15.13 | data only |
| 0.19.6 | `db/data/20241202125248_set_reverse_geocoded_at_for_points.rb` | 0.19.6–0.20.0, 0.20.1–0.21.2 | data only |
| 0.21.3 | `db/data/20240610170930_remove_points_without_coordinates.rb` | 0.21.3–0.21.6, 0.22.0–0.22.4 | data only |
| 0.25.0 | `db/migrate/20250120154555_add_unique_index_to_points.rb` | 0.25.0–0.25.1, 0.25.2–0.25.3 | adds a duplicate-row `DELETE` before the index; same schema |
| 0.25.4 | `db/data/20240808133112_run_initial_visit_suggestion.rb`, `db/data/20241206163450_create_telemetry_notification.rb` | 0.25.4, 0.25.5–0.26.0 | data only |
| 0.26.2 | `db/data/20250518174305_set_default_distance_unit_for_user.rb` | 0.26.2, 0.26.3–0.28.1 | data only |
| 0.30.1 | `db/migrate/20250721204404_add_index_on_places_geodata_osm_id.rb` | 0.30.1, 0.30.2 | whitespace |
| 0.34.1 | `db/migrate/20250926220114`, `…220135`, `…220158` (families), `…220345_validate_family_foreign_keys.rb` | 0.34.1–0.34.2, 0.35.0–0.35.1 | foreign keys created `NOT VALID` then validated by `…220345`, vs created valid with `…220345` commented out: both end valid |
| 0.34.1 | `20250513164521_add_visited_countries_to_trips.rb`, `20250918215512_add_h3_hex_ids_to_stats.rb` | 0.34.1–0.35.0, 0.35.1 | `safety_assured` commented out |
| 0.37.0 | the two files above and `20251227223614_change_digests_distance_to_bigint.rb` | 0.37.0, 0.37.1 | `safety_assured` removed (the 0.37.0 crash above) |
| 1.7.2 | `db/migrate/20260301202147_set_plan_for_existing_users.rb` | 1.7.2, 1.7.3–1.7.4 | rewritten in raw SQL (#2576) |
| 1.7.8 | `db/migrate/20251228000000_remove_unused_indexes.rb`, `20260508093702_backfill_user_id_on_places.rb` | 1.7.8, 1.7.9–1.7.10 | also drops invalid indexes on `points`; backfill body rewritten; same schema on a healthy database |
| 1.12.0 | `db/migrate/20260730210150`, `…210200`, `…210250` (dedupe and unique index) | 1.12.0, 1.12.1 | scratch tables `TEMPORARY` → `UNLOGGED`, dropped in `ensure`; same schema |

## Shipped schema.rb drift

`schemarb_all.sh` loads every distinct shipped `db/schema.rb` (85 blobs across all 259 release tags) into a scratch
database with current code (`bin/rails db:schema:load`), canonicalises it exactly like `compare.sh` does, and diffs it
against the snapshot of each state whose releases shipped it (91 blob/state pairs). Result: 61 identical, 30 differ,
0 unloadable. The 30 differing pairs cover 59 release tags in 30 states; the 29 distinct blobs behind them are stored as
`<first release of the blob>.schemarb.sql.gz`. Every row is in `schemarb.tsv`.

**The method holds.** For 1.5.0 and 0.34.1, the release's own image ran its fresh-install path (`db:migrate`, then
`rake data:migrate` and `db:seed`, fast path on) on an empty database. Both images (activerecord 8.0.3) loaded
`db/schema.rb` and ran no schema migration; their ledgers were exactly `{define version} ∪ {release migrations below
it}`; and their canonical schemas were identical (0 diff lines) to the current-code load of the same schema.rb. Loading
an old schema.rb with current Rails therefore reproduces what that release's fresh install built, down to types,
defaults, index options and `NOT VALID` flags. Limit: only `ActiveRecord::Schema[8.0]` files (0.21.3 to 1.10.1) were
checked against an image. The `[7.1]` files (0.0.8 to 0.15.7, including the 0.8.1 to 0.9.4 drift), the `[7.2]` files
(0.15.8 to 0.21.2, including the 0.19.2 drift) and the `[8.1]` files (1.10.2 on, none drifting) rely on Rails' schema
compatibility layer without that check.

**After current `db:migrate`** is `compare_all.sh`'s check of each stored variant: restore it, run current
`bin/rails db:migrate`, diff against a current fresh install (current `db/schema.rb` and current migrations from empty
give the same canonical schema). 9 of the 29 variants converge; 20 keep a difference that current migrations never
repair, so installs created from those releases' schema.rb still differ today.

| Releases (blob file) | State | Diff lines | schema.rb vs migrations | After current `db:migrate` |
|---|---|---|---|---|
| 0.8.1–0.8.2 (`0.8.1`), 0.8.3–0.8.7 (`0.8.3`), 0.9.0–0.9.2 (`0.9.0`), 0.9.3–0.9.4 (`0.9.3`) | same as first | 11 each | `users.settings` default has `"fog_of_war_meters": "200"` in schema.rb, `"100"` from migrations | 11 each: the `"200"` default stays |
| 0.19.2 (`0.19.2`) | 0.19.2 and 0.19.3 | 18 each | `points.reverse_geocoded_at` and `index_points_on_reverse_geocoded_at` exist only in schema.rb; the migration that adds them, `20241202114820`, ships in 0.19.4 without a guard (`return if column_exists?` arrives in 0.19.6, `b1c48076e`) | 0 |
| 0.23.1–0.23.3 (`0.23.1`) | 0.23.0 | 11 | `unique_points_lat_long_timestamp_user_id_index` in schema.rb, `unique_points_index` in the 0.23.0 snapshot | 0 |
| 0.25.0–0.25.1 (`0.25.0`) | 0.25.0 | 10 | unique index `index_places_on_name_and_lonlat` on `places (name, st_astext(lonlat))` only in schema.rb; no migration creates or drops it (`b8e6b1a37` added it to schema.rb directly, `dbd9b7f31` removed it for 0.25.2) | 10: the unique index stays |
| 0.30.0, 0.30.1–0.30.2, 0.30.3–0.30.5, 0.30.6–0.30.10, 0.30.11 (5 blobs) | same as first | 11 each | `tracks.distance` is `integer` in schema.rb, `numeric(8,2)` from migrations | 0 |
| 0.34.0 (`0.34.0`) | 0.34.0 | 53 | family indexes: schema.rb has `index_family_invitations_on_{email,expires_at,family_id,status}`, `index_family_memberships_on_family_id` and `…_on_family_id_and_role`; migrations have `index_family_invitations_on_{family_id_and_email,family_status_expires,status_and_expires_at,status_and_updated_at}` and `index_family_memberships_on_family_and_role`; the five family foreign keys are `NOT VALID` in schema.rb | 59: both index sets and the `NOT VALID` flags stay |
| 0.34.1–0.35.1 (`0.34.1`) | 0.34.1 | 22 | `users.provider`, `uid`, `patreon_access_token`, `patreon_refresh_token`, `patreon_token_expires_at` only in schema.rb | 12: the three `patreon_*` columns stay |
| 0.36.0–0.36.1 (`0.36.0`), 0.36.2 (`0.36.2`) | same as first | 10 each | `index_users_on_provider_and_uid` missing from schema.rb | 0 |
| 0.37.2–1.0.0 (`0.37.2`) | 0.37.2 | 8 | foreign key `fk_rails_points_raw_data_archives` (`points.raw_data_archive_id`, `ON DELETE SET NULL NOT VALID`) only in schema.rb | 8: it stays |
| 1.0.1 (`1.0.1`) | 1.0.1 | 16 | `index_visits_on_user_id_and_status_and_started_at` and `fk_rails_points_raw_data_archives` only in schema.rb | 16: both stay |
| 1.0.2–1.0.4 (`1.0.2`), 1.1.0–1.2.0 (`1.1.0`) | same as first | 10 each | `index_track_segments_on_track_and_indices` missing from schema.rb | 10: it stays missing |
| 1.3.0 (`1.3.0`), 1.3.1 (`1.3.1`) | same as first | 153 each | tables `notes` and `video_exports` with their indexes and foreign keys, and `index_points_on_archivable`, only in schema.rb; `index_track_segments_on_track_and_indices` missing (`notes` is created later by `20260207075817` with `if_not_exists: true`) | 91: `video_exports` and `index_points_on_archivable` stay, the index stays missing |
| 1.3.2 (`1.3.2`), 1.4.0 (`1.4.0`) | same as first | 75 each | table `video_exports` (no migration creates or drops it) with its indexes and foreign keys only in schema.rb | 76: `video_exports` stays |
| 1.3.3 (`1.3.3`), 1.3.4 (`1.3.4`) | same as first | 43 each | `users.deleted_at` is `timestamp` (no precision) in schema.rb; `index_stats_on_h3_hex_ids` missing; `points_raw_data_archives.user_id` foreign key `NOT VALID`; `points.raw_data_archive_id` foreign key named `fk_rails_points_raw_data_archives … NOT VALID` instead of `fk_rails_98d7bdf4ad` | 28: the `deleted_at` precision, the missing `index_stats_on_h3_hex_ids` and the `NOT VALID` `user_id` key stay |
| 1.5.0–1.5.1 (`1.5.0`), 1.6.0–1.6.1 (`1.6.0`) | same as first | 85 each | `points.altitude numeric(10,2)` in schema.rb vs `altitude integer` plus `altitude_decimal numeric(10,2)` from migrations; `video_exports` only in schema.rb | 86: both stay |
| 1.7.7 (`1.7.7`) | 1.7.7 | 11 | `stats.distance` has `DEFAULT 0` only in schema.rb | 11: the default stays |

Every other release's schema.rb matches its state's snapshot, including 1.7.0 to 1.7.2, whose snapshots were built by
upgrading.

## Ledgers

A real install's `schema_migrations` and `data_migrations` are supersets of the state's set in
`db/release_migrations.json`:

- Installs that passed through 0.37.0 to 1.7.1 keep `20251228163703` after 1.7.2 removed the file (the 1.7.2 snapshot,
  built by upgrading 1.7.1, carries it).
- Installs that passed through 1.10.0 or earlier keep the data versions `20240610170930`, `20250120154554` and
  `20250222213848`, which 1.10.1 removed from `db/data`.
- Installs created from a shipped schema.rb carry its `define(version:)`, which is not always a migration of that
  release: `20240808121027` (0.9.12 to 0.11.1; the migration itself ships in 0.12.0), `20241030152025` (0.16.0 to 0.17.2;
  `create_user_digests`, never released) and `20250930150256` (0.34.0; no such file in any release).
- 9 states differ from their predecessor only in data migrations (0.5.3, 0.8.0, 0.9.9, 0.9.12, 0.15.8, 0.16.0, 0.19.3,
  0.21.3, 0.26.2), so `schema_migrations` alone identifies 78 schema states; `data_migrations` tells the rest apart.

## What C2 must not assume

- Rails' `if_not_exists:`, `if_exists:`, `column_exists?`, `index_exists?` and `table_exists?` guards exist because of
  the schema.rb drift above. Port them verbatim; a guard that looks redundant against a migration-built snapshot is
  load-bearing on a schema.rb install.
- One schema per state. State 0.23.0 has two, and every differing row of `schemarb.tsv` is a second variant.
- That upgrading converges. Current Rails migrations leave 20 of the 29 schema.rb variants different from a current
  fresh install (the last column of the drift table). Reproducing Rails means leaving those differences in place;
  repairing any of them is a behaviour change that belongs in `app-phoenix/parity/expected_diffs.md`.
- Ledger equality. Accept "ledger ⊇ state's set, every extra version is a known removed version or a known schema.rb
  `define(version:)`", never exact equality.
- `ar_internal_metadata`. Image snapshots record `environment=production`, replay and schemarb snapshots
  `development`; real installs have `production`. Do not compare it.
- Restoring into any PostgreSQL. The dumps come from `pg_dump` 17.5 and contain `SET transaction_timeout = 0;`, which
  PostgreSQL 16 and older reject, so `psql -v ON_ERROR_STOP=1` fails there. The default compose files ran
  `postgres:14.2-alpine` up to 0.23.6, `postgis/postgis:14-3.5-alpine` from 0.24.0 to 0.25.x and
  `postgis/postgis:17-3.5-alpine` from 0.26.0. The snapshots record no extension versions.

## Map anomalies

**Removed migrations (2 states):**

- **1.7.2**: `schema_removed: ["20251228163703"]`: drops the RailsPulse tables added in 0.37.0.
- **1.10.1**: `data_removed: ["20240610170930", "20250120154554", "20250222213848"]`.

**Out-of-order versions (backports and out-of-sequence merges):**

Schema, 15 states: each state's minimum added version is lower than the running maximum of all prior states:

| State | min added | prior running max |
|---|---|---|
| 0.19.4 | 20241202114820 | 20241205160055 |
| 0.23.5 | 20241226202204 | 20250120154555 |
| 0.30.12 | 20250821192219 | 20250823125940 |
| 0.36.0 | 20251028130433 | 20251030190924 |
| 1.3.1 | 20260108192905 | 20260222215414 |
| 1.7.1 | 20260421200001 | 20260426204917 |
| 1.7.7 | 20260504120000 | 20260508193923 |
| 1.7.8 | 20260430000001 | 20260508193923 |
| 1.8.0 | 20260520111503 | 20260529185458 |
| 1.9.0 | 20260207075817 | 20260610090000 |
| 1.10.0 | 20260521121527 | 20260622090000 |
| 1.14.0 | 20260815100000 | 20260819120100 |
| 1.14.4 | 20260901070000 | 20260905140000 |
| 1.15.0 | 20260901140000 | 20260906103000 |
| 1.15.2 | 20260714000001 | 20260919190000 |

Data, 2 states:

| State | min added | prior running max |
|---|---|---|
| 0.12.0 | 20240808133112 | 20240815174852 |
| 0.19.4 | 20241202125248 | 20241206163450 |

## Regenerate

From the repository root. Nothing here touches the development or test database or the development Redis.

1. `docker login` (recommended: anonymous Docker Hub pulls are limited to about 10 an hour; `snapshot.sh` retries a
   rate-limited pull 12 times, 360 s apart, tunable with `SNAPSHOT_PULL_RETRIES` and `SNAPSHOT_PULL_WAIT`).
2. `scripts/schema_parity/infra.sh up`: `sp-db` (`postgis/postgis:17-3.5`, used here at
   `sha256:01a6a70e41e6c4467c8f55f6063555ed72db2d6662cd0d571040d42eadaeb6f6`, PostgreSQL 17.5) on `127.0.0.1:55532` and
   `sp-redis` (`redis:7.4-alpine`) on `127.0.0.1:56479`, on the Docker network `schema-parity`.
3. `git fetch --tags`, then `LANG=en_US.UTF-8 DATABASE_NAME=sp_unused RAILS_ENV=test bin/rails schema_parity:release_map`.
   It rewrites `db/release_migrations.json` and refuses to when a release the committed map lists has no local tag.
4. `LANG=en_US.UTF-8 scripts/schema_parity/snapshot_all.sh`, twice. Existing snapshots are skipped, so the second run
   retries only what failed. It exits non-zero while any state fails (listed in `tmp/schema_parity/failures.txt`),
   appends to `tmp/schema_parity/<state>.log`, and each new snapshot updates its row in `provenance.tsv`.
5. `LANG=en_US.UTF-8 scripts/schema_parity/schemarb_all.sh`: rewrites `schemarb.tsv` and the `.schemarb.sql.gz` files.
6. `LANG=en_US.UTF-8 scripts/schema_parity/compare_all.sh`: one line per state in `tmp/schema_parity/summary.txt`
   (`<state> upgrade:<lines> replay:<lines|n/a|not-reproducible missing:…>`) and one per stored schema.rb variant in
   `tmp/schema_parity/summary_schemarb.txt`; diffs in `tmp/schema_parity/diffs/`. It exits non-zero if any
   comparison could not run.
7. `scripts/schema_parity/infra.sh down`.

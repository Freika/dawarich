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
  `postgis/postgis:17-3.5-alpine` from 0.26.0. The snapshots record no extension versions. The harness's
  `restore_snapshot` handles it for `SP_PG_MAJOR=14` (see "Interface for C4").

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
2. `scripts/schema_parity/infra.sh up`, with the default `SP_PG_MAJOR=17` (the scripts below refuse any other):
   `sp-db` (`postgis/postgis:17-3.5`, used here at
   `sha256:01a6a70e41e6c4467c8f55f6063555ed72db2d6662cd0d571040d42eadaeb6f6`, PostgreSQL 17.5) on `127.0.0.1:55532`
   and `sp-redis` (`redis:7.4-alpine`) on `127.0.0.1:56479`, on the Docker network `schema-parity`.
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

## Ecto counterparts (C2)

Roadmap step C2 ports every Rails schema migration after the 1.0.0 floor to Ecto and proves each port against current
Rails on these snapshots. The spec is ADR 0015 with its two 2026-09-24 amendments
(`docs/adr/0015-port-every-rails-migration-to-ecto-squashed-per-release.md` at the workspace root); the plan is
`superpowers/plans/2026-09-24-phoenix-c2-ecto-migrator-plan.md` there. Deliberate differences from Rails are in
`app-phoenix/parity/expected_diffs.md`.

### What exists

Paths are relative to the repository root.

| Path | Responsibility |
|---|---|
| `app-phoenix/priv/repo/migrations/20260924120000_create_release_migrator_tables.exs` | Lease (`phoenix.release_migrator_leases`) and outbox (`phoenix.release_migration_jobs`) tables, in the `phoenix` schema |
| `app-phoenix/config/config.exs`, `config/test.exs` | `Dawarich.Repo` gets `parameters: [timezone: "UTC"]`; the test env adds `Dawarich.ScratchRepo` |
| `app-phoenix/lib/dawarich/release_migration.ex` | Release-module behaviour and the step helpers (the porting DSL) |
| `app-phoenix/lib/dawarich/release_migrator.ex` | Preflight, classification, per-version execution, fenced ledger and outbox writes, baseline, pending data |
| `app-phoenix/lib/dawarich/release_migrator/ledger.ex` | Pure classification of a ledger |
| `app-phoenix/lib/dawarich/release_migrator/floor.ex` | The 1.0.0 floor: every state through `0.37.2` with the migrations `db/migrate` still ships |
| `app-phoenix/lib/dawarich/release_migrator/lease.ex` | Lease row, renewal, fencing, two-connection probe |
| `app-phoenix/lib/dawarich/release_migrations.ex` | Ordered registry of release modules (`@releases`) |
| `app-phoenix/lib/dawarich/release_migrations/v*.ex`, `unreleased.ex` | One module per C1 state after the floor (38: `1.0.1` … `1.15.2`, 146 versions), plus `Unreleased` |
| `app-phoenix/lib/dawarich/release_migrations/effects/*.ex` | C3a: the Phoenix ports of the app code migrations call synchronously, one module per Rails effect (see "C3a: inline effects, and what is handed on") |
| `app-phoenix/lib/dawarich/release_migrations/effects/support/*.ex` | Ruby semantics the ports share: `Ruby` (`blank?`, `strip`, `to_s`, JSON writing; `Ruby.Error` for an error Ruby raises, with Ruby's exact message except ED-025; `Ruby.Unreproducible`, never rescued, where Phoenix cannot reproduce Ruby's behaviour), `RubyFloat` (`Float#to_s` and Oj's Rails float format), service settings, the geocoding schema and `InstanceSettings::Registry` |
| `app-phoenix/lib/dawarich/active_record_encryption.ex`, `active_record_encryption/*.ex`, `app-phoenix/priv/ruby_encodings.txt` | Rails-compatible Active Record Encryption: keys from the Rails environment, messages Rails reads, and Rails' rescued and raised decryption failures |
| `app-phoenix/priv/admin1_world.geojson` | A link to `lib/assets/admin1_world.geojson` (`Achievements::LoadRegions`). `mix release` copies it as a file, and the image copies the Rails file in before `mix release`. `scripts/release_smoke.sh` fails unless the built release holds a byte-identical regular file |
| `app-phoenix/priv/release_migrations/baseline.sql` | Generated baseline for fresh installs |
| `app-phoenix/priv/release_migrations/<release>/<version>.sql` | Only for a module that would pass 300 lines; none today |
| `app-phoenix/test/support/scratch_repo.ex`, `scratch_case.ex`, `rails_tree.ex`, `migration_modules.ex` | Scratch repo, per-test reset, reading `db/` and `app/` of the Rails tree, purging test-defined modules |
| `app-phoenix/test/support/mix/tasks/dawarich.release_migrate.ex` | `mix dawarich.release_migrate [--only <release>]` (test env only): the harness's Ecto entry, and the refusal texts (`describe/1`) |
| `app-phoenix/test/mix/dawarich_release_migrate_test.exs` | Pins the refusal and failure messages the harness parses |
| `app-phoenix/test/dawarich/release_migration_test.exs`, `release_migrator_test.exs`, `release_migrations_test.exs` | Helpers, migrator (lease, fencing, refusals, outbox), counterpart coverage and completeness |
| `app-phoenix/test/dawarich/release_migrator/ledger_test.exs`, `real_ledger_test.exs`, `baseline_test.exs` | Classification, real ledgers around the floor, baseline and fresh install end to end |
| `app-phoenix/test/dawarich/release_migrations/v1_0_2_test.exs`, `v1_1_0_test.exs`, `v1_11_0_test.exs`, `v1_13_0_test.exs` | Rescued-SQL unit tests |
| `app-phoenix/test/dawarich/release_migrations/effects/*_test.exs`, `app-phoenix/test/dawarich/active_record_encryption_test.exs`, `app-phoenix/test/fixtures/*.json` | Unit tests of the ports and the encryption module; Rails pins (`geocoding_rails_pins_test.exs` reads the registry, providers, rate limits and messages through `RailsTree`; floats, Oj parsing and encryption messages are recorded in the Rails runtime) |
| `app-phoenix/test/support/release_effect_inventory.ex`, `app-phoenix/test/dawarich/release_migrations/effect_inventory_test.exs` | Every class a release module records in the outbox, with its owner; a new or dynamically named class fails. The stop helper no longer exists, so a step that calls an unported effect does not compile |
| `app-phoenix/test/dawarich/release_migrations/inline_effects_test.exs`, `encrypted_columns_test.exs` | Guards for `inline_effects.tsv` and `encrypted_columns.tsv` |
| `app-phoenix/parity/expected_diffs.md` | Deliberate differences from Rails (`ED-002` onward) |
| `scripts/schema_parity/rails_reference.rb` | Rails side of every check; captures SQL, jobs and the baseline |
| `scripts/schema_parity/baseline.sh` | Regenerates `baseline.sql` |
| `scripts/schema_parity/canon.rb` | Canonical jobs, time-window masking of rows |
| `scripts/schema_parity/inventory.rb` | Prism inventory of `db/migrate` after the floor |
| `scripts/schema_parity/list_checks.rb` | The check list, shared by both scripts below |
| `scripts/schema_parity/ecto_check.sh`, `ecto_prove.sh`, `ecto_lib.sh`, `ecto_template.sh` | One check; listing, running and summarising checks (C4's interface); shared helpers; template databases |
| `scripts/schema_parity/ecto_expectations.tsv` | Declared outcomes: `failed@V`, contended and refused checks |
| `scripts/schema_parity/pr_checks.rb` | Checks a pull request must pass; fixture gate for unreleased migrations |
| `scripts/schema_parity/inline_effects.tsv` | The Rails files each inline port reproduces, and the release whose checks a change to one selects |
| `scripts/schema_parity/encrypted_columns.tsv`, `decrypt_columns.rb` | The encrypted attributes; Rails decrypts both sides before the row comparison |
| `scripts/schema_parity/lib.sh`, `infra.sh` | C1's helpers: `canon_dump` excludes `phoenix` and `oban` and is memoised; bounded `docker exec`; the PostgreSQL 14 restore rule; `infra.sh up` starts the pinned server `SP_PG_MAJOR` selects and turns off its durability |
| `scripts/schema_parity/fixtures/<release>[--<variant>].sql` / `.env` | Row fixtures and their environments (128 `.sql`, 36 `.env`) |
| `scripts/schema_parity/matrix_inventory_preflight.rb`, `inventory_tags.rb`, `snapshot_paths.rb` | The matrix inventory preflight (see "Matrix inventory preflight"); the `inventory.rb` tags that need a fixture, shared with `pr_checks.rb`; the snapshot files a check label restores from |
| `scripts/schema_parity/ci/*` | CI helpers: `prove_shard.sh` (the nightly and sample proof wrapper), `nightly_report.rb` (`leg` and `report`), `upgrade_sample.rb`, `ref_cache_key.sh` |
| `scripts/schema_parity/test/*` | Harness self-tests (see "What CI runs" and the nightly's "Tests") |
| `.github/workflows/ecto-counterparts.yml` | Four jobs: `ecto-counterparts` (the checks a change selects on pull requests, every check on pushes to `dev` and `master`), `ecto-upgrade-sample`, `harness-tests` and `harness-docker-tests` |
| `.github/workflows/ecto-nightly.yml` | The nightly matrix: every check on PostgreSQL 14 and 17 in two shards each, and the report (see "Nightly matrix") |

**Nothing calls the migrator before A12.** The application, `Dawarich.Release`, the entrypoint and the image never
reference `Dawarich.ReleaseMigrator`; today its only entry is the test-env mix task the harness runs.

### How a database is migrated

1. **Unit of porting vs unit of execution.** One module per C1 state after the floor, registered in JSON order in
   `Dawarich.ReleaseMigrations`, is the unit that is ported, reviewed and proven. Execution is per version, in global
   version order across all modules, exactly as Rails' `db:migrate` orders pending migrations.
   - A version runs its step, its ledger row and its outbox rows in one transaction.
   - A version whose Rails file calls `disable_ddl_transaction!` is `transaction: false`: its step runs outside a
     transaction (each statement commits on its own, `CONCURRENTLY`, lock retries and batch commits as Rails wrote
     them), then its ledger and outbox rows are written in a short transaction.
   - The release step must run with the Rails app's environment (`RAILS_ENV`, `OTP_ENCRYPTION_*`, `SECRET_KEY_BASE`): `Dawarich.ActiveRecordEncryption` resolves the Active Record Encryption keys from it exactly as `config/application.rb` does (a development install without `OTP_ENCRYPTION_*` uses Rails' dev keys), so any other environment gives other keys, and Phoenix would write ciphertext Rails cannot read and treat every stored secret as unreadable. No committed dotenv file may carry these keys either, since dotenv loads them into Rails only (`active_record_encryption_test.exs`).
2. **Ledger = Rails' ledger.** State comes only from `public.schema_migrations`. Each version writes its own row. There
   is no Ecto ledger for release migrations, and `ar_internal_metadata` is never written.
3. **Classification** (`Ledger.classify/2`, pure), after the preflight below:
   - no `public.schema_migrations`, or an empty one → `:fresh`. **Empty-ledger rule:** when `public` holds nothing but
     Rails' ledger tables, the baseline builds the schema beside them. When an application table is present, the
     baseline stops at the first one it would create and changes nothing, in one transaction: the same outcome as a
     missing ledger with leftover tables.
   - a non-empty ledger holding no floor version → `{:not_dawarich, count}`;
   - a ledger lacking any floor version → `{:below_floor, release}`, where `release` is the `first_release` of the
     oldest state the ledger has not completed;
   - versions no module knows → `{:newer, versions}`. Tolerated: every floor version, the removed `20251228163703`
     (installs that passed through 0.37.0–1.7.1 keep it), and the schema.rb define versions `20241030152025` and
     `20250930150256`;
   - otherwise the missing known versions → `{:pending, sorted}`, or `:current`. A database stopped part-way through
     a release resumes from its first missing version.
4. **The 1.0.0 floor** (`Dawarich.ReleaseMigrator.Floor`). Release 1.0.0 shares its schema state with 0.37.2 and
   0.37.3, so the floor is state `0.37.2`: every migration `db/migrate` still ships of the 40 states through it (92
   versions). A ledger lacking one is refused before the lease and before any change, with this message
   (`describe/1` in the mix task, reused verbatim by the harness and `expected_diffs.md`):

   `refused: this database has not reached Dawarich <release>, and this image upgrades only from 1.0.0; start the Dawarich 1.15.2 image once so Rails upgrades it, then start this image`

   The remedy names one release, `@last_rails_release` in the mix task, rather than "any image from 1.0.0": 1.3.2
   and 1.7.0–1.7.2 crash on upgrades from 1.0.0 or earlier (see "Why the fallbacks exist") after the floor versions
   commit and before `rake data:migrate`, and a database left there would pass the floor with its old data migrations
   never run. A12 bumps `@last_rails_release` to the last Rails release, and the upgrade note of the release that
   removes Rails names it.
5. **Refusals**, checked in this order, each before any change:

   | Refusal | Message | Remedy |
   |---|---|---|
   | A pool under two connections (a second checkout is attempted while one is held) | `refused: the repo pool needs two connections` | Run the migrator on a repo with ≥ 2 connections (A12) |
   | A session time zone other than UTC | `refused: session time zone is <value>, not UTC` | Pass the `timezone` startup parameter; behind PgBouncer, make sure `TimeZone` is passed through |
   | A Rails migrator holding Rails' session advisory lock (key `2053462845 * crc32(current_database())`, read from `pg_locks`) | `refused: a Rails migrator holds its advisory lock (backend <pid>); stop it, or if no Rails process runs, wait for PgBouncer's server_lifetime or restart PgBouncer` | As the message says. Also checked before every `transaction: false` step and inside every ledger transaction; a lock that appears mid-run rolls that version back. Self-hosted only: Cloud sets `DATABASE_ADVISORY_LOCKS=false`, so its deploy must guarantee no Rails migrator runs |
   | Rails tables outside `public` (`current_schema()` is not `public`, or a `schema_migrations` table exists in another schema) | `refused: Rails tables outside public (search path <schema>; <schemas>)` | Reset the role's `search_path`, or move Rails' tables to `public` |
   | A ledger with no Dawarich version | `refused: schema_migrations holds <count> versions and none of them is a Dawarich migration; check DATABASE_NAME` | Point `DATABASE_NAME` at the Dawarich database |
   | A database below the floor | the floor message above | Start the named Rails image once, then this image |
   | A live lease held by another migrator, after a 15-minute wait (poll 2 s) | `refused: another migrator holds the lease (<holder>)` | Let the other migrator finish; a dead holder's lease expires 60 s after its last renewal |
   | Unknown versions | `refused: newer than this image (<versions>)` | Start the Dawarich image that created them, or restore the pre-upgrade backup |

   A version that fails ends the run with `failed <release> <version>: <error>`. A DDL-transaction version rolls back;
   a `transaction: false` version keeps the statements it committed, as in Rails. Either way the next start resumes
   at that version. A lost lease ends it with `refused: lease lost by <holder>`.
6. **Lease, not advisory lock; fenced.**
   - `phoenix.release_migrator_leases` holds one row, `release_migrator` (holder, `expires_at`, TTL 60 s).
   - Every expiry is `clock_timestamp() + TTL`, never `now()`, which is the transaction start.
   - A linked process renews it every 20 s. It exits `:lease_lost` when its `UPDATE` matches no row and crashes when a
     renewal takes longer than one interval; either way the link kills the migrator.
   - Every ledger write renews the lease by holder inside its own transaction, after the step's work; if that
     `UPDATE` matches anything but one row, the version rolls back. The baseline fences after its SQL.
   - The row is deleted at the end. It serialises every step, including those outside a transaction, and is
     PgBouncer-safe.
7. **Jobs are never lost.** A step's jobs go to `phoenix.release_migration_jobs` (`version`, `job_class`,
   `arguments jsonb`, `wait_seconds`, `recorded_at`) in the same transaction as the version's ledger row, in enqueue
   order. Nothing is enqueued before C3/A12, and nothing reads the table yet. **Argument format:** `arguments` holds
   ActiveJob-serialized arguments, exactly what Rails puts in the Sidekiq payload, and the harness compares them with
   `job.serialize["arguments"]`:
   - JSON scalars and arrays as-is;
   - a plain Hash with `"_aj_symbol_keys": [its symbol keys]`, always present, possibly empty;
   - keyword arguments as a trailing Hash with `"_aj_ruby2_keywords": [keys]` instead (1.14.4:
     `[null, 50000, {"repair_collisions": true, "_aj_ruby2_keywords": ["repair_collisions"]}]`);
   - `HashWithIndifferentAccess` with `"_aj_hash_with_indifferent_access": true`;
   - Symbol, Time, Duration and other serializer-backed values as `{"_aj_serialized": "<Serializer>", …}`;
   - records as `{"_aj_globalid": "gid://dawarich/Model/id"}`.

   `wait_seconds` is `.set(wait: n)`, `0` when none.
8. **Synchronous app code runs inline (C3a).** Where Rails calls app code synchronously (`perform_now`, a service),
   the step calls the Phoenix port of that effect (`release_migrations/effects/`) at the same place, behind the same
   guards and Rails' own work condition, within the version's own transaction boundary (none for a
   `transaction: false` version, like 1.7.6's and 1.14.0's). All seven sites are ported (see "C3a: inline effects,
   and what is handed on"). There is no stop helper: C2's `unported!/1` and `UnportedEffect` are deleted, so a step
   that calls an effect without a port does not compile.
9. **Data ledger: read, never written.** `data_versions/0` is `[]` for every module, so `pending_data` is `[]` on
   every supported database: all 27 `db/data` migrations belong to states at or before the floor, and
   `docker/web-entrypoint.sh` runs `rake data:migrate` on every start. The migrator never writes `data_migrations`.
10. **Baseline.** `baseline.sql` is the SQL Rails sends during `db:schema:load` of current `db/schema.rb`, captured by
    `baseline.sh` (`rails_reference.rb schema`): what a real fresh install runs, unqualified, valid on PostgreSQL 14+.
    - It omits Rails' `DROP TABLE IF EXISTS … CASCADE` and the `ar_internal_metadata` rows, so leftover tables make it
      fail instead of being overwritten.
    - It creates `schema_migrations` and `ar_internal_metadata` with `CREATE TABLE IF NOT EXISTS` (Rails checks
      `table_exists?` in Ruby first), so an empty ledger in an otherwise empty `public` takes it.
    - A fresh install is the baseline in one transaction, then every known version the baseline lacks.
    - Regenerate it at every release cut and whenever `fresh` fails: a stale baseline plus later steps diverges from
      Rails whenever a future `db/schema.rb` drifts from its migrations, as 29 shipped ones did.
11. **Connection.** `prepare: :unnamed`; no advisory lock is ever taken (the migrator only reads `pg_locks`); only
    `SET LOCAL`, never a session `SET` or `RESET` (a test scans every module); UTC through the Postgrex startup
    parameter `timezone`, which PgBouncer tracks, instead of Rails' `SET SESSION timezone TO 'UTC'`; a repo-level
    `timeout: :infinity`; no temporary tables, and the scratch tables Rails creates and drops within one migration stay
    `UNLOGGED`, as Rails creates them.
12. **A12 preconditions** (recorded here, enforced there):
    - No Rails process may run `db:migrate` against a database the Phoenix migrator touches: an old image, a replica,
      a rollback. The `pg_locks` refusal guards self-hosted installs; on Cloud the deploy procedure must.
    - Rails' boot-time data writes (`FeatureFlags.apply_defaults!` and any other initializer that writes rows) are
      ported to Phoenix, never into a release module. Rails' release step boots the app, running them, before it
      migrates, and the harness proves that order. So Phoenix's release step runs the ported defaults (when the
      Flipper tables exist) before `ReleaseMigrator.migrate`, sequentially in the same process, and web boot runs them
      again, as Rails does. The two must never run concurrently (`expected_diffs.md` ED-016, ED-020).
    - Killing the migrator (lease lost, renewer timeout) does not cancel a statement already running on the server.
      The release command must say so and wait for, or `pg_cancel_backend`, that backend before retrying.
    - The production repo used for migrating has ≥ 2 connections, `timeout: :infinity` and the UTC `timezone`
      parameter, and `Dawarich.Release.migrate/0` (lease and outbox tables) runs first.
    - The release that removes Rails ships the upgrade note for databases older than 1.0.0, naming the last Rails
      release, and its release command prints the floor message with that release.
    - The operator layer lives only in the test-only mix task (`test/support/mix/tasks/dawarich.release_migrate.ex`).
      A12 moves it to `lib/`: `describe/1` with every refusal text (including the generic `refused: <message>` for a
      connection error from the two-connection probe), `@last_rails_release`, and the repo overrides (a pool of ≥ 2,
      `timeout: :infinity`, `DBConnection.ConnectionPool` instead of the test sandbox).
      `ReleaseMigrator.apply_release_for_proof/3` (`--only`) is harness-only; the release command calls `migrate/2`.
    - Only a step's own error comes back as `{:error, {:failed, …}}`. Other query errors raise out of `migrate/2`: the
      preflight and classification reads, the ledger re-read after the baseline (`run/5`'s recursion),
      `pending_data`, the lease acquire and the lease `DELETE` in `with_lease`'s `after`. A12's release command
      rescues them and reports a failure instead of crashing.
    - The lease timings (TTL 60 s, renewal every 20 s, renewal query timeout 20 s) are too tight for slow self-hosted
      storage. Eugene agreed (2026-09-25) to raise the TTL, for example to 5 minutes; A12 sets the values and keeps
      the renewal interval and its timeout well inside the TTL.

### Porting rules (Tasks 7–18 and every future Rails migration)

A release module is `app-phoenix/lib/dawarich/release_migrations/v<release with dots as underscores>.ex`, `Dawarich.ReleaseMigrations.V<same>`, `@behaviour Dawarich.ReleaseMigration`. It defines:
- `release/0`: the state's `first_release`.
- `steps/0`: one entry per Rails file in the state's `schema_added` still in `db/migrate`, sorted by version. It is `{version, &fun/1}`, or `{version, &fun/1, transaction: false}` exactly when the Rails file calls `disable_ddl_transaction!` (a test enforces this).
- `data_versions/0`: the state's `data_added` still in `db/data`, sorted.

A step receives the repo; a `{:jobs, [job(...)]}` return reports enqueues.

| Rails source | Ecto step |
|---|---|
| Statements a migration emits (`create_table`, `add_column`, `add_index`, `add_reference`, `change_column*`, `rename_*`, `remove_*`, `add_foreign_key`, `validate_*`, `add_check_constraint`, `execute`) | The statements the fixture-free capture `tmp/schema_parity/capture/<release>.sql` shows under `-- version <v>`, verbatim, **including `CONCURRENTLY`**. In a DDL-transaction step, several may share one `sql!(repo, ~S"""…""")`. **In a `transaction: false` step, one `sql!` per Rails call.** A multi-statement simple query is one implicit transaction: `… CONCURRENTLY` fails inside it, and the other statements lose Rails' commit-per-statement. A single Rails `execute` that itself holds several statements becomes one `sql!` inside `repo.transaction(fn -> … end)`. `sql!` raises outside a transaction when given more than one statement; semicolons inside `'…'` strings and `$$` bodies do not count. Its known miscounts (a `;` in a comment, an `E'…'` string with escaped quotes, a quoted identifier) fail loudly, never silently: split the statement or wrap it as above |
| `disable_ddl_transaction!` | `transaction: false` on the step; each `sql!` then commits on its own, as in Rails |
| An inner `transaction do … end` | `repo.transaction(fn -> … end)` around the same statements |
| `ensure` (e.g. `DROP TABLE IF EXISTS visit_dedupe_plan` / `visit_straggler_losers`) | `try do … after … end` with the same statements in `after` |
| Batch loops that repeat until zero rows | The same loop: `repo.query!(sql, params).num_rows` until 0; outside a transaction each batch commits, as in Rails. The repo's `timeout: :infinity` covers long batches |
| Rails boot-time data writes (`FeatureFlags.apply_defaults!` and other initializers) | Nothing. They are not migrations; the harness boots Rails on both sides, and A12 ports them to Phoenix boot |
| Ruby decisions: `table_exists?`, `column_exists?`, `index_exists?`, `index_name_exists?`, `foreign_key_exists?`, `check_constraint_exists?`, `connection.columns(...)`, `select_value` / `select_all` / `select_values`, `return if/unless`, `raise` | The same decision, same order, same short-circuiting: `table?/2`, `column?/3`, `index?/3` (Rails' `index_exists?` for `name:` / `columns:` exactly as passed, primary keys excluded; any other option such as `unique:`, `valid:` or `include:` raises, so write that check with `exists?/3` on `pg_index`), `index_name?/3` (Rails' `index_name_exists?`: name only, primary keys included), `exists?/3`; `raise` keeps its message |
| Guards Rails evaluates in Ruby, so the capture shows the SQL unconditionally. Line numbers are in activerecord-8.1.3.1 `connection_adapters/abstract/schema_statements.rb` unless noted: `add_column … if_not_exists:` (`:674`), `remove_column … if_exists:` (`:719`), `remove_index … if_exists:` (`postgresql/schema_statements.rb:577`, name **and** columns when both are given), `add_foreign_key … if_not_exists:` (`:1209`), `remove_foreign_key … if_exists:` (`:1249`), `add_check_constraint … if_not_exists:` (`:1330`), `remove_check_constraint … if_exists:` (`:1360`) | An explicit `unless column?` / `if column?` / `if index?(repo, t, name: …, columns: […])` / `exists?` on `pg_constraint` around the statement |
| Guards Rails writes into the SQL (`create_table if_not_exists:`, `add_index if_not_exists:`, `drop_table if_exists:`) | Verbatim |
| Lock-timeout retry (`transaction do SET LOCAL lock_timeout …; <DDL> end`, `rescue ActiveRecord::LockWaitTimeout` [+ `QueryAborted`], `sleep`, `retry`) | `with_lock_retry(repo, fn -> … end, lock_timeout:, attempts:, backoff_seconds:, on: [:lock_not_available] or [:lock_not_available, :query_canceled])` in a `transaction: false` step. Each attempt is its own transaction; `SET LOCAL statement_timeout = 0` inside the Rails block goes inside the fun. It returns `{:not_acquired, %Postgrex.Error{}}` (the last 55P03) after the last attempt; do what Rails does there: `{:not_acquired, error} -> raise error` where Rails re-raises (`20260827200000`, `20260827210000`, `20260914090000`; the harness compares SQLSTATE and the number of lock waits), a job or nothing via `{:not_acquired, _}` |
| `rescue` around SQL (`ActiveRecord::RecordNotUnique`, `StatementInvalid`, …) | `rescue_sql(repo, fn -> … end, [postgres_error_codes] or :any, fn error -> … end)` in the same place: `unique_violation` for `RecordNotUnique`, `:any` for `StatementInvalid`. The step is `transaction: false` wherever Rails runs it outside a transaction (all current sites). A future site inside a transaction needs a savepoint variant first. **Each site gets an ExUnit unit test** |
| `rescue StandardError` around `perform_later` only | Nothing: the outbox write cannot fail on its own |
| Session `execute 'SET lock_timeout = 0'` / `'RESET lock_timeout'` (`20260816120000`, `20260818201239`, there so `CONCURRENTLY` is not aborted) | Dropped. At that point call `require_zero_lock_timeout!(repo)`, which fails with a clear message when the role or database sets a non-zero `lock_timeout` (expected_diffs; question for Eugene) |
| `Job.perform_later(args)` / `.set(wait: n)` | `{:jobs, [job("Job", serialized_args, n_seconds)]}` after the step's SQL, in enqueue order, behind the same conditions. Arguments use the ActiveJob serialization in "How a database is migrated", item 7 |
| `Job.perform_now`, app classes that read or write rows | A port in `release_migrations/effects/<effect>.ex`, called at the same place behind the same guards, that follows the Rails class statement by statement, including its failures (`Ruby.Error` with Ruby's message). Where Phoenix cannot reproduce Ruby's exact failure, it raises `Ruby.Unreproducible` (nothing rescues it) and the difference goes into `expected_diffs.md`. JSON written to `jsonb` goes through `Ruby.json` (Oj's Rails encoder, `config/initializers/oj.rb`). Copied app lists get an ExUnit pin that reads the Rails file through `RailsTree`. Each Rails file the port reproduces gets a row in `scripts/schema_parity/inline_effects.tsv` |
| Thin model calls that are one statement (`Model.where(…).update_all(…)`, `delete_all`, `none?`, `count`, `Flipper.enable`) | The captured statement with its binds inlined, except values that come from data or the clock (next row) |
| **Values Ruby computed from query results or the clock** (ids, `loser_ids.join(',')`, `Time.current`, Flipper's `created_at`) | Computed in the step at run time: ids from the same query, passed as parameters; times as `now()` (the session is UTC, like Rails', so `now()` in a `timestamp` column equals Rails' UTC write). A literal id or timestamp copied from a capture is a bug; the `rows:…~shifted` checks catch ids |
| `DawarichSettings.self_hosted?` | `self_hosted?()` |
| Other `ENV` / config reads | `System.get_env/2` with the Rails name, default, parsing and production semantics. Ruby's `present?` / `blank?` treat `nil`, `""` and whitespace-only strings alike, so `ENV['X'].present?` becomes `String.trim(System.get_env("X") \|\| "") != ""` (`SKIP_*`, Registry variables) |
| `DawarichSettings.<setting>` backed by `InstanceSettings` (e.g. `reverse_geocoding_enabled?` via `photon_host` …) | `InstanceSettings::Resolver.get` order (`app/services/instance_settings/resolver.rb`): **the environment first** (a non-blank variable pins it), then a stored `instance_settings` row, then the registry default. Any database error degrades to environment + default: before 1.15.0 `instance_settings` does not exist, so only the environment and defaults decide. `DawarichSettings.setting` falls back to the constant on any error |
| `Rails.logger`, `say`, `puts`, comments, `down` | Nothing |
| A migration of a state at or before the floor (`0.37.2`), including the removed `20251228163703` | Nothing: no module, no step. `Floor` lists the shipped ones and the preflight refuses a ledger that lacks one; `20251228163703` stays in `Ledger.removed_versions/0` |

A module that would pass 300 lines moves its longest SQL into `app-phoenix/priv/release_migrations/<release>/<version>.sql` and embeds it at compile time:
- `@<name>_path Path.expand("../../../priv/release_migrations/<release>/<version>.sql", __DIR__)`
- `@external_resource @<name>_path`
- `@<name> File.read!(@<name>_path)`

#### Rules added while porting

The porting rules above are the plan's. Porting 1.0.1–1.15.2 added these, and every later port follows them:

- **Use the helpers in `Dawarich.ReleaseMigration`** instead of hand-rolling their pattern: `sql!/2`, `exists?/3`,
  `table?/2`, `column?/3`, `index?/3`, `index_name?/3`, `index_names/3` (Rails' index lookup by columns),
  `remove_index_by_columns/4` (Rails' `remove_index` by columns, including its "Multiple indexes found" error),
  `remove_index_concurrently_if_exists/3`, `foreign_key_name/4` (Rails' `foreign_key_for`), `quote_ident/1`,
  `select_value/3`, `repeat_until_zero/3`, `with_lock_retry/3` and `with_lock_retry!/3` (raises the last 55P03 after
  the last attempt), `rescue_sql/4`, `require_zero_lock_timeout!/1`, `job/3`, `self_hosted?/0` (Rails'
  `SELF_HOSTED` parsing, with Ruby 3.4's `strip`), `env_present?/1` (`ENV[…].present?`) and `backfill_allowed?/0`.
- **The capture wins over the plan.** Guards are evaluated where Rails evaluates them, and the capture shows where
  (for example, 1.14.x's lock-retry guards run once, before the first attempt).
- **An effect's gates follow Rails' own work condition**, not a broader stop. C2's list-free stop conditions went with
  `unported!/1` in C3a.
- **Each branch of an effect gets its own fixture and mutation**, named by what it covers:
  `<release>--<variant>` (for example `1.15.2--legacy-awards`).
- **Every guard's skip branch is exercised by a fixture.** Fixtures use no clock defaults, and fixture tables have
  Rails' real shape.
- **The main `rows:<release>` fixture runs every version of the release.** A fixture that writes ledger rows models a
  drifted database both runtimes accept (a version recorded without its effect) and is a variant, never the main
  fixture.
- **`pg_dump` omits invalid indexes**, so the harness compares an `invalid` part (`pg_index.indisvalid = false`, per
  table, name and definition) next to the schema.
- **A mutation runner must give each restored file a new modification time**: Mix keeps a mutated `.beam` when the
  restored file is older than the build and the same size.

### Proof rules

- **Checks** (`ecto_prove.sh --list` prints them all). Only states after the floor get `step:` / `rows:` / `contended:`, and only snapshots at or after it get `upgrade:`:
  - `fresh`: an empty database, Rails' `db:schema:load` vs the Ecto migrator (baseline).
  - `fresh:empty`: Rails' ledger tables and nothing else (the old `upgrade:empty` database). Rails loads `db/schema.rb` onto it; the Ecto migrator treats the empty ledger as fresh and runs the baseline. Rails' own `db:migrate` would instead run every migration from the first, a pre-floor path (expected_diffs).
  - `step:<R>`: R's versions on the previous state's snapshot, Rails vs Ecto.
  - `rows:<R>[--<variant>][~shifted]`: `step:` after loading `scripts/schema_parity/fixtures/<R>[--<variant>].sql` into both databases, with that fixture's `.env` (if any) in both environments.
  - `contended:<R>:<table>`: `step:` while a second session holds `LOCK TABLE <table> IN ROW EXCLUSIVE MODE`.
    - That lock conflicts with the `SHARE ROW EXCLUSIVE` (foreign keys) and `ACCESS EXCLUSIVE` (column changes) requests the lock retries guard, so those retries time out.
    - Ordinary writes proceed. `CREATE/DROP INDEX CONCURRENTLY` waits for transactions holding conflicting locks, and `ROW EXCLUSIVE` conflicts, so a `CONCURRENTLY` step in the same release blocks until the holder ends. The results stay valid, but `contended:1.10.1:points` and `contended:1.13.1:points` take ≥ ~5 min each.
    - The holder's `pg_sleep` (150 s) must exceed the longest retry budget in the contended versions (75 s today); raise it when a new retry budget is longer.
    - Each contended check has a declared expected result in `ecto_expectations.tsv`: a status, and a job where Rails hands off. A check whose contention changes nothing fails.
  - `upgrade:<label>`: the state's snapshot, then everything pending, Rails `migrate` vs the full Ecto migrator. `label` is a state from `0.37.2` on, `<release>.schemarb` from `0.37.2` on, `<state>+<version>` (one extra ledger row), or `<state>@<version>` (Rails first migrates up to that version: an interrupted upgrade). `upgrade:0.37.2`, a 1.0.0 database and the lowest supported state, is a required pass.
  - `refused:<label>`: a database below the floor, with the same label syntax. It is Ecto only: Rails does not run, and the Ecto side does not boot Rails.
    - It expects the migrator to stop with `refused: this database has not reached Dawarich <R>,` and to leave `public` and the outbox unchanged: schema, ledger, columns, rows, jobs.
    - `ecto_expectations.tsv` declares R per check: `refused:0.0.8` → `0.0.9` (the oldest state), `refused:0.34.0.schemarb` → `0.34.1` (a schema.rb install, phantom define version included), `refused:0.36.3@20251227000001` → `0.37.0` (the database stuck part-way through 0.37.0).
- **What is compared:**
  - the C1-canonicalised schema, with `phoenix` and `oban` excluded;
  - the ledger;
  - `public` column order (`information_schema.columns.ordinal_position`, which C1's `normalize.sh` hides);
  - `public` rows (timestamps inside the run's time window become `<now>`, those written while the check's template database was built `<template>`);
    - Encrypted columns (`scripts/schema_parity/encrypted_columns.tsv`) compare as plaintext, since each encryption uses a random IV. When one holds a value, Rails boots on that side's database in a read-only session (`decrypt_columns.rb`) and decrypts every value with the model's own attribute type and the check's `.env` keys. The row copy then reads the plaintext inside a transaction it rolls back. A decrypted value compares as `plaintext: <plaintext>`. A value Rails cannot decrypt compares as `undecryptable (<exception class>): <ciphertext>`, so it matches only the byte-identical, untouched ciphertext on the other side. A value Phoenix wrote that Rails cannot read therefore still fails the check, as a row difference, which proves that Rails reads what Phoenix writes; a fixture's deliberately undecryptable row compares as itself.
    - `encrypted_columns_test.exs` fails when a Rails model gains or loses an `encrypts`, or gives one options that `Dawarich.ActiveRecordEncryption` does not implement.
  - jobs (canonical JSON, in order).
- **Rails boots on both sides.** After the fixture, the template build runs `bin/rails runner 'nil'`, and both sides are cloned from that template, so Rails' boot-time rows are on both sides before either migrates. These are the `poster_ordering` and `achievements` Flipper features and a gate from `FeatureFlags.apply_defaults!`, written on every snapshot from 1.7.0 on.
  - Fixture authors: that boot runs **after** your fixture, and `apply_defaults!` also deletes retired flags. A fixture row that is a retired flag disappears before either side migrates, so no row a check relies on may be one.
  - For `Flipper.enable(:poster_ordering)` (1.11.0), seed a pre-existing *disabled* `poster_ordering`, so the step has something to change.
- **Outcomes:**
  - Rails and Ecto must end the same way. Both succeed, or both fail at the same version, with the whole state compared either way.
  - A failure whose version cannot be read (`failed@` with nothing after it) is always a FAIL.
  - A `refused:` check passes as `ok (refused below_floor <R>)`.
- **Time zone and ids.** Every harness database has `timezone = 'Pacific/Chatham'` as its default, so a step that writes local time instead of UTC shows up as a row diff. Every `rows:` check also runs `~shifted`, with all `public` sequences advanced to 100000 before the fixture, so an id inlined from a capture shows up as a diff.
- **Fixture files.** `fixtures/<R>[--<variant>].sql` is plain SQL on the previous state's snapshot, run as the `sp-db` superuser.
  - Timestamps are fixed; ids are never written explicitly.
  - At least one row each statement changes and one it keeps.
  - Invalid-index branches: `UPDATE pg_index SET indisvalid = false WHERE indexrelid = '<index>'::regclass`.
  - Rows that violate a `NOT VALID` constraint: `ALTER TABLE <t> DISABLE TRIGGER ALL` around the insert.
  - `fixtures/<R>[--<variant>].env` holds `NAME=value` lines (no spaces), for example the dummy `OTP_ENCRYPTION_*` values C1's `snapshot.sh` uses.
- **Captures** come only from fixture-free `step:` runs.
- **Porting procedure per release R:**
  - **Red.** `step:R` fails with `no Ecto release module for R`, and the capture appears.
  - **Port.** Read every file and the capture, then write the module and register it.
  - **Green.** `step:R` is `ok`.
  - Write the fixtures the task's inventory requires, and make every `rows:` / `contended:` check of R `ok`.
  - A check that cannot be made green without changing a Rails file, the harness, or another release's module is a **STOP**: report it.

### Proof inventory

`scripts/schema_parity/inventory.rb` (Task 6) builds this from `db/migrate` with Prism, ignoring `down` and comments. It skips the versions of states at or before the floor. Tasks 7–18 turn every flagged version into a required check. Legend:
- `rows`: changes rows.
- `validates`: the result depends on data (`validate_*`, `SET NOT NULL`, raise-on-duplicates).
- `job`: enqueues.
- `gated`: the enqueue or change depends on a query of existing rows (`select_value`, `exists?`, `EXISTS (…)`), so both branches need a fixture.
- `effect`: a synchronous app call, ported inline since C3a.
- `env`: reads configuration.
- `notx`: `disable_ddl_transaction!`.
- `lockretry`: lock-timeout retry.
- `rescue`: rescued SQL.
- `sessionset`: session `SET`.
- `invalid`: an invalid-index branch.

Unconditional enqueues are proven by `step:` on the empty snapshot; everything else needs a row fixture, an env variant, or a contended check.

The proof inventory tables list only flagged versions; every other version needs only `step:`. Every `rows:` check listed implies its `~shifted` twin. Each task also names the mutation that proved its checks can fail.

#### Task 7: 1.15.2

| Version | Tags | Required checks |
|---|---|---|
| `20260714224647` | effect (`Achievements::LoadRegions` when countries exist and `regions` is empty; C3a: `effects/load_regions.ex`) | `rows:1.15.2--regions-seeded`, `--regions-subdivisions`, `--regions-mixed` |
| `20260720160000` | effect (`Achievements::MigrateExplorationState` whenever `achievement_progresses` exists; C3a: `effects/migrate_exploration_state.ex`) | `rows:1.15.2--legacy-progress`, `--legacy-awards`, `--legacy-merge`, `--sharing-carriers`, `--award-collisions`, `--no-legacy-work`, `--migrated-state`, `--float-earned`; declared `failed@20260720160000`: `--carrier-collision`, `--deleted-user-progress` |
| `20260720170000` | rows (`DELETE` of codes without `-`), effect (`LoadRegions` when countries exist) | `rows:1.15.2` (+ `~shifted`), `rows:1.15.2--regions-subdivisions`, `--regions-mixed` |
| `20260922120000` | job | `step:1.15.2` |

#### Task 8: 1.15.0, 1.14.4

| Release | Version | Tags | Required checks |
|---|---|---|---|
| 1.15.0 | `20260901150000` | effect (`InstanceSettings::Backfill`; C3a: `effects/backfill_instance_settings.ex`, its registry pinned by `effects/geocoding_rails_pins_test.exs` through `RailsTree`) | `rows:1.15.0--env-settings`, `--env-coercions`, `--env-over-admin`, `--admins-unanimous`, `--users-unanimous`, `--users-disagree`, `--users-lowest-rate`, `--partial-coverage`, `--undecryptable-key`, `--rps-small`, `--rps-rounding` (`.env` files with dummy `OTP_ENCRYPTION_*`); declared `failed@20260901150000`: `--malformed-key`, `--missing-encryption-key` |
| 1.15.0 | `20260914090000` | notx, lockretry (5 s, 5 attempts, `sleep(attempts * 5)`, raise after the last; `add_column … if_not_exists` → `unless column?` inside each attempt) | `contended:1.15.0:points` → expected `ok (failed@20260914090000)` |
| 1.14.4 | `20260901070000` | job+env (`backfill_allowed?` = `self_hosted?()` and `SKIP_POINT_DIMENSION_BACKFILL` blank, `add_point_dimension_columns_job.rb:28-32`; gate `EXISTS (SELECT 1 FROM point_sources)`; arguments `[nil, BATCH_SIZE, {"repair_collisions" => true, "_aj_ruby2_keywords" => ["repair_collisions"]}]`) | `rows:1.14.4` (a `point_sources` row → the job), `rows:1.14.4--skip-backfill` (`.env` `SKIP_POINT_DIMENSION_BACKFILL=1`) |
| 1.14.4 | `20260906103000` | rows, notx, conc, invalid | `rows:1.14.4` also carries its duplicate `stats` rows: the fixture drops the existing unique index first so the duplicates can be inserted. `rows:1.14.4--invalid-index` |

Mutation: return no job from `20260901070000` when `point_sources` has rows → `rows:1.14.4 FAIL jobs`.

#### Task 9: 1.14.3, 1.14.2, 1.14.1

| Release | Version | Tags | Required checks |
|---|---|---|---|
| 1.14.3 | all four | guard, conc | `step:` |
| 1.14.2 | `20260828100000`, `20260831120000` | job | `step:` |
| 1.14.2 | `20260901120000` | rows | `rows:1.14.2` |
| 1.14.1 | `20260827200000` | notx, lockretry (`foreign_key_exists?(:points, :tracks, column: :track_id)` guard; raise after the last attempt) | `contended:1.14.1:points` → expected `ok (failed@20260827200000)` |
| 1.14.1 | `20260827200100` | notx, rows+validates (dangling `points.track_id` detach loop, then `VALIDATE`) | `rows:1.14.1` (points pointing to missing tracks, inserted with `DISABLE TRIGGER ALL`) |
| 1.14.1 | `20260827210000` | notx, lockretry (`connection.columns(:trips)` sql_type guard) | `contended:1.14.1:trips` → expected `ok (failed@20260827210000)` |

Mutation: change the settings key in 1.14.2's `20260901120000` UPDATE → `rows:1.14.2 FAIL`.

#### Task 10: 1.14.0

| Version | Tags | Required checks |
|---|---|---|
| `20260815100000` | guard | `step:` |
| `20260815100001` | notx, validates+effect (the migration's own `userless_count` check, then `DataMigrations::BackfillPlacesUserIdJob.perform_now`, C3a: `effects/backfill_places_user_id.ex`; the `remaining=<n>` recount and curated `raise`; `check_constraint` by name via `pg_constraint`) | `rows:1.14.0--userless-places`, `--owned-places`, `--place-tie-breaks`, `--unvisited-place`, `--no-check-constraint`; declared `failed@20260815100001`: `--unresolvable-places` |
| `20260823190000` | notx, rows+job (stamp-clearing UPDATE, then `RecalculateAnomaliesJob`) | `rows:1.14.0` |
| `20260825120000` | job+env (`backfill_allowed?`) | `rows:1.14.0--skip-backfill` (`.env` `SKIP_POINT_DIMENSION_BACKFILL=1`) |
| `20260825120100` | guard | `step:` |

Mutation: drop one condition from the WHERE of `20260823190000` → `rows:1.14.0 FAIL`.

#### Task 11: 1.13.1, 1.13.0, 1.12.2

| Release | Version | Tags | Required checks |
|---|---|---|---|
| 1.13.1 | `20260816150000` | notx, lockretry (1 s, 5 attempts, backoff 2, `on: [:lock_not_available, :query_canceled]`, `:not_acquired` → nothing) | `contended:1.13.1:points` → expected `ok` with `AddPointDimensionColumnsJob` (enqueued by `20260816150200` when `source_id` is missing) |
| 1.13.1 | `20260816150100` | conc, guard | `step:` |
| 1.13.1 | `20260816150200` | job+env | `step:` (default branch → `BackfillPointDimensionsJob`), `rows:1.13.1--skip-backfill` (`.env`) |
| 1.13.1 | `20260818201239` | notx, conc, session `SET`/`RESET lock_timeout` (both dropped, `require_zero_lock_timeout!` in their place), invalid (own gist index) | `rows:1.13.1--invalid-index` |
| 1.13.1 | `20260819120000` | guard | `step:` |
| 1.13.1 | `20260819120100` | effect+env (`Geocoding::SeedFromEnv` only when `self_hosted?()`, `reverse_geocoding_enabled?` and a `users` row exists). `reverse_geocoding_enabled?` follows `InstanceSettings::Resolver`: environment first, then a stored row, then the default. At 1.13.1 `instance_settings` does not exist yet, so the lookup degrades to environment + default: any geocoding host or key variable that is non-blank enables it | C3a: `effects/seed_geocoding_from_env.ex`. `rows:1.13.1--env-provider`, `--provider-chain`, `--chain-tail`, `--chain-without-photon`, `--komoot-host`, `--existing-active`, `--invalid-env`, `--env-disabled`, `--cloud-geocoding`, `--missing-encryption-key` (`.env` files with dummy `OTP_ENCRYPTION_*`); declared `failed@20260819120100`: `--malformed-winner`, `--undecryptable-komoot`, `--undecryptable-winner` |
| 1.13.0 | `20260816120000` | notx, conc, session `SET lock_timeout = 0` (dropped, `require_zero_lock_timeout!` in its place), invalid (drops other invalid points indexes; replacement invalid → `REINDEX INDEX CONCURRENTLY`), rescue (`StatementInvalid` → `rescue_sql(…, :any, …)`, then the curated `MigrationError`) | `rows:1.13.0--invalid-index` (one unrelated index and the replacement index marked invalid); **unit test** `test/dawarich/release_migrations/v1_13_0_test.exs`: the replacement index invalid over duplicate rows → the step raises the curated message (`… is missing on \`points\`, or invalid and could not be rebuilt automatically.`) |
| 1.12.2 | `20260811120000` | notx, rows+job | `rows:1.12.2` |
| 1.12.2 | `20260813120000`, `20260813120100` | conc, guard | `step:` |

Mutation: in `V1_13_0`, remove the `rescue_sql` wrapper → the unit test fails with the raw Postgres error.

#### Task 12: 1.12.0

| Version | Tags | Required checks |
|---|---|---|
| `20260804085722` | notx, conc, invalid | `rows:1.12.0--invalid-index` |
| `20260804085723` | job | `step:` |
| `20260804093200`, `20260809085900`, `20260809090100` | rows | `rows:1.12.0` |
| `20260805120001` | notx, rows (batched soft delete), guard | `rows:1.12.0` |
| `20260808120000` | guard | `step:` |
| `20260809090000` | job+env (`self_hosted?()`, `SKIP_VISITS_FLEET_REDETECT` present → no job; `defined?(Visits::FleetRedetectJob)` is true on `dev`) | `rows:1.12.0--skip-redetect` (`.env` `SKIP_VISITS_FLEET_REDETECT=1`), `rows:1.12.0--cloud` (`.env` `SELF_HOSTED=false`) |

Mutation: skip the `SKIP_VISITS_FLEET_REDETECT` read → `rows:1.12.0--skip-redetect FAIL jobs`.

#### Task 13: 1.11.0

Requires `f7325c68c` in the base.

| Version | Tags | Required checks |
|---|---|---|
| `20260730160000`, `20260802120000` | job | `step:` |
| `20260730200000` | rows (`Flipper.enable(:poster_ordering)`: timestamps as `now()`) | `rows:1.11.0`: the fixture seeds a pre-existing *disabled* `poster_ordering`; the boot after it deletes retired flags, so no kept row is one |
| `20260730210000`, `20260730210400`, `20260730220000` | notx, conc, guard (`210400`: invalid) | `rows:1.11.0--invalid-index` |
| `20260730210100` | notx, rows (`Import.where(…).update_all`) | `rows:1.11.0` |
| `20260730210150` | notx, rows (visits dedupe; `loser_ids` computed in the step; `place_visits` delete only when the table exists, per `233a70ebe`) | `rows:1.11.0`, `rows:1.11.0--no-place-visits` (fixture drops `place_visits`) |
| `20260730210200`, `20260730210300` | notx, rows, conc, invalid, rescue (`RecordNotUnique` → `rescue_sql(…, [:unique_violation], …)`: drop the invalid index, collapse stragglers or delete duplicate segments, rebuild; `collapse_stragglers` deletes from `place_visits` only when the table exists, per `f7325c68c`) | `rows:1.11.0` (duplicates removed by the dedupe steps first); **unit tests** `test/dawarich/release_migrations/v1_11_0_test.exs`, one per site plus one for the guard. Duplicates present when the step starts → the index ends valid, one row per key, points moved to the keeper. For `20260730210200` without a `place_visits` table, the rescue path still succeeds |
| `20260730210250` | notx, rows (track segment dedupe) | `rows:1.11.0` |

Mutation: keep the wrong visit in `20260730210150` → `rows:1.11.0 FAIL`.

#### Task 14: 1.10.2, 1.10.1

Port 1.10.2 first (newest first).

| Version | Tags | Required checks |
|---|---|---|
| `20260727120000` (1.10.2) | guard | `step:1.10.2` |
| `20260727130000` (1.10.2) | job | `step:1.10.2` |
| `20260714090000` | notx, rows (batched lonlat backfill from legacy `latitude`/`longitude`), lockretry (1 s, 3 attempts, backoff 3, `on: [:lock_not_available, :query_canceled]`; `SET LOCAL statement_timeout = 0` inside the attempt; `:not_acquired` → `{:jobs, [job("DataMigrations::DropLegacyLatLonJob")]}`) | `rows:1.10.1` (points with `lonlat IS NULL` and legacy columns), `contended:1.10.1:points` → expected `ok` with `DataMigrations::DropLegacyLatLonJob` (the handoff) and the legacy columns still present |
| `20260719180000`, `20260719190000` | job | `step:` |
| `20260719185000` | conc, guard | `step:` |

Mutation: return nothing on `:not_acquired` → `contended:1.10.1:points FAIL jobs`.

#### Task 15: 1.10.0, 1.9.1, 1.9.0, 1.8.1, 1.8.0, 1.7.11

| Release | Version | Tags | Required checks |
|---|---|---|---|
| 1.9.1 | `20260622090000` | notx, conc, validates (curated `raise` on duplicate attachable dates) | `rows:1.9.1--violation` (duplicate notes → both fail at `20260622090000`) |
| 1.9.0 | `20260207075817`, `20260208223255` | rows | `rows:1.9.0` |
| 1.8.1 | `20260610090000` | notx, rows, conc, invalid | `rows:1.8.1`, `rows:1.8.1--invalid-index` |
| 1.8.0 | `20260604120000` | job | `step:` |
| 1.7.11, 1.10.0 | all | conc / guard | `step:` |

Mutation: drop the duplicate check in `20260622090000` → `rows:1.9.1--violation FAIL`.

#### Task 16: 1.7.8, 1.7.7, 1.7.6, 1.7.5, 1.7.2, 1.7.1, 1.7.0, 1.6.0, 1.5.0, 1.4.0

| Release | Version | Tags | Required checks |
|---|---|---|---|
| 1.7.8 | `20260508093702`, `20260514120100` | job gated by `has_pending` queries | `rows:1.7.8` (places with `user_id NULL`; tracks the second query counts) |
| 1.7.6 | `20260508193900` | notx, effect (`DedupeTracksForUniqueIndexJob.perform_now`; work iff `users_with_duplicates` in `app/jobs/data_migrations/dedupe_tracks_for_unique_index_job.rb` returns a row) | C3a: `effects/dedupe_tracks_for_unique_index.ex`. `rows:1.7.6--duplicate-tracks`, `--three-way-duplicates`, `--duplicate-associations`, `--deleted-user`, `--no-duplicates` |
| 1.7.2 | `20260429180000` | drops the RailsPulse tables (`if_exists`, `CASCADE`) | `step:` |
| 1.5.0 | `20260323000002` | job | `step:` |
| 1.4.0 | `20260322000001` | validates (`validate_foreign_key :points, :points_raw_data_archives`) | `rows:1.4.0--violation` (a point pointing to a missing archive, inserted with `DISABLE TRIGGER ALL`) |
| others | | conc / guard | `step:` |

Mutation: invert the first `column?` guard in `V1_7_0` → `step:1.7.0 FAIL`.

#### Task 17: 1.3.4, 1.3.3, 1.3.2, 1.3.1, 1.3.0

Requires `f7325c68c` in the base.

| Release | Version | Tags | Required checks |
|---|---|---|---|
| 1.3.4 | `20260314000001`, `20260315000001` | job | `step:` |
| 1.3.3 | `20260310000003` | notx, rows (duplicate `place_visits` delete), conc; returns early without `place_visits` (`233a70ebe`, in `f7325c68c`) | `rows:1.3.3`, `rows:1.3.3--no-place-visits` |
| 1.3.2 | `20260301202147` | rows+env (`self_hosted?()`; raw SQL since #2576) | `rows:1.3.2`, `rows:1.3.2--cloud` (`.env` `SELF_HOSTED=false`) |
| 1.3.0 | `20260217000001` | job | `step:` |
| 1.3.1, 1.3.0 | others | conc / guard | `step:` |

Mutation: replace `self_hosted?()` with `not self_hosted?()` → `rows:1.3.2 FAIL`.

#### Task 18: 1.1.0, 1.0.2, 1.0.1

| Release | Version | Tags | Required checks |
|---|---|---|---|
| 1.1.0 | `20260206202634` | notx, job per user with duplicates, staggered `wait` | `rows:1.1.0` |
| 1.0.2 | `20260125100000` | notx, jobs per user and per import, staggered `wait` | `rows:1.0.2` |
| 1.0.1 | `20260112192240`, `20260113230537` | rows | `rows:1.0.1` |

`step:1.0.1` runs on the `0.37.2` snapshot, the floor itself.

Mutation: compute `wait` from the wrong index in `20260125100000` → `rows:1.0.2 FAIL jobs`.

#### Where execution differs from these tables

The tables are the plan's required minimum; `ecto_prove.sh --list` is the complete list. Execution added fixtures for
guard skip branches and drifted databases, and corrected these rows:

- **The seven effect sites (C3a):** C2's broad stops are gone. Each port runs under Rails' own work condition, for
  example 1.13.1's `self_hosted?()`, `reverse_geocoding_enabled?` and a `users` row, and 1.15.2's
  `20260720160000` whenever `achievement_progresses` exists. The rows above list the fixtures C3a added.
- **1.13.0:** `rows:1.13.0--no-replacement` (the replacement index missing) is declared `failed@20260816120000`.
- **1.11.0:** no priv SQL was needed (the module is 267 lines); `rows:1.11.0--rescue` and `rows:1.11.0--batches`
  (5001 imports) prove the rescued unique-violation fallback and the `== 5000` batch continuation.
- **1.4.0:** `rows:1.4.0--fk-recorded` (`20260318000001` recorded without its foreign key) is declared
  `failed@20260322000001`, like `--violation`.
- **1.1.0 `20260206202634`:** one `Tracks::DeduplicationJob` per non-deleted user, not per user with duplicates
  (current Rails has no duplicates gate).
- **1.0.2 `20260125100000`:** current Rails enqueues nothing: the user half names `TransportationModes::BackfillJob`,
  deleted in `b1de9ea6a` (a `NameError` its `rescue` swallows), and the import half compares the integer
  `imports.source` with strings (an SQL error it swallows). The port enqueues nothing, and its unit test pins that.
- **`step:1.0.1`** is declared `failed@20260112192240` (see "Proof results").

### Proof results

**After C3a (2026-09-26).** `ecto_prove.sh --jobs 6 all` ran cold in 2163 s (36 min) on the loaded machine, after
the Ecto sides moved to their own build path (5ad4e6da1), with two `mix test --force` runs in `app-phoenix/_build/test`
during it:

| Checks | ok | ok, both fail at V | ok, refused below the floor | FAIL |
|---|---|---|---|---|
| 358 | 323 | 32 | 3 | 0 |

The 358 are 2 `fresh`, 39 `step:`, 254 `rows:`, 5 `contended:`, 55 `upgrade:` and 3 `refused:`. An earlier run on the
shared `_build/test` failed `step:1.8.0` once, because a concurrent `mix test` re-consolidated the protocols while
that check's Ecto side booted; the separate build path removed the cause. C3a adds 16 checks that fail at the same version on both sides, each fixture with its
`~shifted` twin: `rows:1.13.1--malformed-winner`, `--undecryptable-komoot` and `--undecryptable-winner` at
`20260819120100`, `rows:1.14.0--unresolvable-places` at `20260815100001` (the curated `remaining=<n>` error),
`rows:1.15.0--malformed-key` and `--missing-encryption-key` at `20260901150000`, and `rows:1.15.2--carrier-collision`
and `--deleted-user-progress` at `20260720160000`. No check stops at an unported effect any more.

**C2 (2026-09-25).** The whole matrix (`ecto_prove.sh all`, 262 checks) ran seven times on 2026-09-25: twice on the sequential harness
and five times on the template harness, the last one cold on the harness as committed. All seven `summary.txt` files
are byte-identical:

| Checks | ok | ok, both fail at V | ok, unported | ok, refused below the floor | FAIL |
|---|---|---|---|---|---|
| 262 | 234 | 16 | 9 | 3 | 0 |

The 262 are 2 `fresh`, 38 `step:`, 159 `rows:`, 5 `contended:`, 55 `upgrade:` and 3 `refused:`.

**Both fail at the same version** (`ok (failed@V)`), with the whole state compared and Rails' error from its reference
`.out`; each `rows:` line also holds for its `~shifted` twin:

- `step:1.0.1` at `20260112192240`: `PG::UndefinedColumn: ERROR: column "deleted_at" does not exist`. A harness
  artefact: the migration reads `users.deleted_at`, which `20260108192905` adds, a lower version that belongs to state
  1.3.1. On the 0.37.2 snapshot alone both runtimes fail identically; a real upgrade runs `20260108192905` first
  (global version order), which the `upgrade:` checks prove.
- `rows:1.0.2--multiple-indexes` at `20260120193124`: `Multiple indexes found on digests columns [:user_id, :year,
  :period_type]. Specify an index name from index_digests_legacy_user_year_period,
  index_digests_on_user_id_and_year_and_period_type`.
- `rows:1.3.3--multiple-indexes` at `20260310000001`: `Multiple indexes found on points columns [:user_id]. Specify an
  index name from index_points_on_user_id, index_points_on_user_id_unarchived`.
- `rows:1.4.0--violation` at `20260322000001`: `PG::ForeignKeyViolation: ERROR: insert or update on table "points"
  violates foreign key constraint "fk_rails_98d7bdf4ad" DETAIL: Key (raw_data_archive_id)=(1) is not present in table
  "points_raw_data_archives".`
- `rows:1.4.0--fk-recorded` at `20260322000001`: `Table 'points' has no foreign key for points_raw_data_archives`.
- `rows:1.9.1--violation` at `20260622090000`: `Cannot create unique index index_notes_on_attachable_and_noted_date: 2
  duplicate (attachable_type, attachable_id, noted_at::date) group(s) exist in the notes table. Resolve the duplicates
  and re-run this migration.`
- `rows:1.13.0--no-replacement` at `20260816120000`: ``index_points_on_user_id_timestamp_lonlat is missing on
  `points`, or invalid and could not be rebuilt automatically. …`` (the curated message, with the repair SQL).
- `contended:1.14.1:points` at `20260827200000`, `contended:1.14.1:trips` at `20260827210000` and
  `contended:1.15.0:points` at `20260914090000`: `PG::LockNotAvailable: ERROR: canceling statement due to lock
  timeout`, after the fifth attempt on both sides (the harness compares the SQLSTATE and the number of lock waits).

**Stops at an unported effect** (C2 only, `ok (unported@V)`): nine `rows:` checks of 1.7.6, 1.13.1, 1.14.0, 1.15.0
and 1.15.2. C3a renamed their fixtures, ported the effects and turned them into row comparisons.

**Upgrades.** All 55 `upgrade:` checks are plain `ok`, including the required `upgrade:0.37.2` (a 1.0.0 database, the
lowest supported state), `upgrade:0.37.2+20241030152025` (the phantom define version: tolerated by Ecto, ignored by
Rails), and both interrupted upgrades, `upgrade:0.37.2@20260108192905` and `upgrade:1.3.1@20260301201446`. The 13
schema.rb variants at or after the floor (`0.37.2`, `1.0.1`, `1.0.2`, `1.1.0`, `1.3.0`, `1.3.1`, `1.3.2`, `1.3.3`,
`1.3.4`, `1.4.0`, `1.5.0`, `1.6.0`, `1.7.7`) are the ones none of which converges under current Rails (the last column
of "Shipped schema.rb drift"): Ecto reproduces each (`upgrade:<release>.schemarb ok`), leaving exactly the
differences Rails leaves.

**Refusals** (`ok (refused below_floor R)`, Ecto only, `public` and the outbox unchanged):
- `refused:0.0.8` → 0.0.9: a migration-built database from the oldest state;
- `refused:0.34.0.schemarb` → 0.34.1: a schema.rb fresh install, its phantom define version `20250930150256`
  included;
- `refused:0.36.3@20251227000001` → 0.37.0: the database stuck part-way through 0.37.0 (the `safety_assured` crash).

**Column order.** C1's `normalize.sh` sorts the columns inside every `CREATE TABLE`, so the schema part cannot see
column order. The `columns` part (`information_schema.columns` in `ordinal_position` order) restores it.

**The proven configuration** is the self-hosted default: `SELF_HOSTED`, `SKIP_POINT_DIMENSION_BACKFILL`,
`SKIP_VISITS_FLEET_REDETECT` and every geocoding variable unset. On top of it, the `.env` fixtures prove
`SELF_HOSTED=false` (`--cloud`: 1.3.2, 1.12.0, 1.13.1, 1.14.0, 1.14.4), `SKIP_POINT_DIMENSION_BACKFILL=1`
(`--skip-backfill`: 1.13.1, 1.14.0, 1.14.4), `SKIP_VISITS_FLEET_REDETECT=1` (`--skip-redetect`: 1.12.0), and,
since C3a, geocoding and `InstanceSettings::Registry` variables with dummy `OTP_ENCRYPTION_*` values (the 1.13.1 and
1.15.0 effect fixtures; `--cloud-geocoding` adds `SELF_HOSTED=false`). Any other combination is unproven.

### Interface for C4

**`ecto_prove.sh [--shard K/N] [--jobs N] --list | all | <check>...`**, from the repository root:
- `--list` prints every check (358 today), one per line, in a stable order. `--shard K/N` keeps lines K, K+N, K+2N….
- `all` or a list of checks prints one line per check: `ok`, `ok (failed@V)`, `ok (refused below_floor R)`, or `FAIL …` (including `FAIL timed out: …` and `FAIL no result`). Then
  `ran <n> checks, <f> failed`.
  - The lines go to `tmp/schema_parity/ecto/summary.txt` (`summary.K-N.txt` for a shard) in `--list` order. `all`
    starts a fresh file for its own shard; explicit checks append, so remove `summary*.txt` first, as the CI job does.
  - Exit 0 only when every check passed. A run aborted before its checks start (duplicate check names, a list error,
    no check selected, a local `.env`, a server whose major is not `SP_PG_MAJOR` or whose version check timed out,
    `mix compile` failing) exits 2 and
    writes `ABORTED …` to the summary. A bad `--shard` or `--jobs` value, a missing argument and any `--list` error
    exit 2 with a message on stderr and write no summary line.
  - A TERM signal exits 2 as well, so a killed run always leaves a line to name. Before the checks start it writes
    `ABORTED terminated …` like the aborts above (`… during mix compile in app-phoenix`, or the version-check
    timeout). While the checks run, it appends the lines of the checks that already finished, `FAIL` lines included,
    in `--list` order, then `ABORTED terminated while running the checks (unfinished: <checks>)`. If a `docker exec`
    times out in the cleanup after a complete summary, it appends `ABORTED terminated while dropping the stale
    scratch databases`. The lanes and the serial contended check reset TERM, and a second TERM is ignored, so the
    line appears once. The nightly job sends TERM through GNU `timeout`, which signals the whole process group.
  - `== start|end <epoch> <check>` lines go to `tmp/schema_parity/ecto/prove.log`.
- `--jobs N` runs N lanes over the non-contended checks (default: half the cores, at least 1), then the contended
  checks one at a time, alone. With `--shard`, each shard runs its own contended checks alone at its end.
- Diffs go to `tmp/schema_parity/ecto/diffs/`. Rails references are cached in `tmp/schema_parity/ecto/ref/`, keyed
  by the check's own inputs (snapshot, fixture, `.env`) and the code key: the SHA-1 of the working-tree bytes of
  `db/migrate`, `db/release_migrations.json`, `app` (without `app/assets`), `config`, `lib`, `Gemfile.lock`,
  `.ruby-version`, `.tool-versions`, the harness scripts directly in `scripts/schema_parity/` and
  `encrypted_columns.tsv`, plus the `.env*` files, `ruby -v` and `SP_PG_MAJOR`, so each PostgreSQL major keeps its
  own references and CI cache. The canonical-dump
  memo `tmp/schema_parity/canon/` is content-addressed. The CI job caches both under `ecto-ref-<os>-<code key>`.
- Each starting point (snapshot, migrated-to version, extra ledger row, `~shifted`, fixture, `.env`) is built once as
  a template database `sp_t_<sha1>`, with Rails booted on it (except for `refused:`), and every side of every check
  is its own clone. A complete `all` run drops unused templates and the databases of dead runs.
- Every `docker exec` is bounded at 300 s (`SP_EXEC_TIMEOUT`), the lock holder and its watcher at 150 + 300 s; a stuck
  call fails its check instead of hanging.
- Declared outcomes (`failed@V`, contended, refused) are in `scripts/schema_parity/ecto_expectations.tsv`.
  Contended checks hold `ROW EXCLUSIVE` on their table for 150 s.
- `inventory.rb [versions…]` prints `state<TAB>version<TAB>tags` per migration after the floor;
  `pr_checks.rb <list> [<base>...<head>]` reads changed paths on stdin and prints the checks they select (see "What CI
  runs"); the range is required when `Gemfile.lock` changed.

**Prerequisites:** `scripts/schema_parity/infra.sh up` (sp-db with `fsync`, `full_page_writes` and
`synchronous_commit` off, and sp-redis), `bundle check`, `mix deps.get` in `app-phoenix/`, the
`en_US.UTF-8` locale, and no `.env`, `.env.local` or `.env.development.local` in the checkout (the harness refuses
them: dotenv would load them into the Rails side only). The Ecto sides compile into their own build directory
(`MIX_BUILD_PATH=app-phoenix/_build/parity`), so `mix test` in `app-phoenix/` can run alongside a proof: a shared
`_build/test` let a concurrent compile or protocol consolidation fail whichever check was booting. Proofs of both
PostgreSQL majors share that directory, also when they run side by side from one checkout: nothing compiled depends
on the major (only `DATABASE_PORT` differs, and the repo reads it at runtime), and Mix 1.18 holds an operating-system
lock on the build directory while it compiles, so a second up-front `mix compile` waits and then finds nothing to do.
One directory also keeps the single `mix-parity-…` CI cache valid for every leg.

**Timings** (Apple M5 Pro, 18 cores, OrbStack, other sessions loading the machine; 9 lanes unless noted):

| Run | Wall | Lanes phase | Contended phase |
|---|---|---|---|
| Whole matrix, cold | 1719–1844 s (29–31 min) | 594 s | 1118 s |
| Whole matrix after C3a (358 checks), cold, 6 lanes | 2174 s (36 min) | 1046 s | 1111 s |
| Whole matrix, cached | 1306 s (22 min) | 211 s | 1095 s |
| One release (1.14.0, 11 checks), cold / cached | 34 s / 11 s | | |
| PR job dry run, 207 checks, 2 lanes, cold | 2474 s (41 min) | 1373 s | 1100 s |
| Old sequential harness, idle machine: cold (sum of check times) / cached | 6945 s / 3936 s | | |

The contended phase is the floor: its Rails side always reruns under the 150 s holder, and its length is set by the
migrations' own retry budgets (1.10.1 and 1.13.1 about 310 s each, the three failing ones about 165 s each).
Re-measure per kind on any run's slice of `prove.log`:

```bash
awk '$2 == "start" { s[$4] = $3 } $2 == "end" { split($4, k, ":"); t[k[1]] += $3 - s[$4]; c[k[1]]++ } END { for (x in t) printf "%s %d checks, %.0f s average, %.0f s total\n", x, c[x], t[x] / c[x], t[x] }' tmp/schema_parity/ecto/prove.log
```

**Shard sizing.** The non-contended checks need about 5250 lane-seconds cold and the contended ones about 1120 s.
With the default 2 lanes of a 4-core runner, one shard per PostgreSQL version needs about 5250 / 2 + 1120 ≈ 3750 s
(≈ 1 h). The nightly (see "Nightly matrix") runs two shards per PostgreSQL version under a 180-minute job timeout.
PostgreSQL 14 has been measured locally and is as fast as 17 (see "Calibration" there); the runner's Docker Engine
is still unmeasured. Keep two only if the first cold Actions run keeps every job under 90 min; otherwise use four
and measure again.

**PostgreSQL major.** `SP_PG_MAJOR` selects the server; every harness script, `infra.sh` included, reads it and
rejects anything but `14` or `17` (an empty value too). Unset means `17`.

| `SP_PG_MAJOR` | Image, pinned by index digest | Server |
|---|---|---|
| `17` (default) | `postgis/postgis:17-3.5@sha256:01a6a70e41e6c4467c8f55f6063555ed72db2d6662cd0d571040d42eadaeb6f6` | 17.5, PostGIS 3.5.2 |
| `14` | `postgis/postgis:14-3.5@sha256:2543ae2bc9497ca62cd740268be228f7a6974020207634e2b189fe36be82b749` | 14.18, PostGIS 3.5.2 |

PostGIS 3.5 is the newest minor published for both majors (`14-3.6` and `17-3.6` do not exist), matches the pinned 17
image, and is what the compose files shipped with PostgreSQL 14 (0.24.0–0.25.x) and 17 (from 0.26.0). Both indexes
carry only `linux/amd64`; Apple silicon runs them under emulation.

- `infra.sh up` reuses a container that already has the name, so it reads `SHOW server_version_num` and fails when the
  server is not the selected major; `ecto_prove.sh` makes the same check before any check starts. Each server compares
  Rails and Ecto on itself; references are not shared between majors (see the code key above).
- `SP_DB_CONTAINER`, `SP_DB_PORT`, `SP_REDIS_CONTAINER`, `SP_REDIS_PORT` and `SP_NETWORK` override `sp-db`, `55532`,
  `sp-redis`, `56479` and `schema-parity` for every script, so a second harness can run beside the first. Set all five,
  none empty, or none: any other combination exits 2 before a single `docker` call, naming the missing ones, because
  the unset ones would fall back to the default stack. `infra.sh up` also refuses a reused container that does not
  publish exactly `127.0.0.1:$SP_DB_PORT` (PostgreSQL) or `127.0.0.1:$SP_REDIS_PORT` (Redis). `SP_WORK` moves the work
  directory (`tmp/schema_parity` by default) and everything the harness writes there. CI keeps the defaults: each job
  has its own runner.
- **PostgreSQL 14 restores.** The snapshots are `pg_dump` 17.5 output with one `SET transaction_timeout = 0;` per
  `pg_dump` preamble (two per file: schema and ledger rows), which PostgreSQL 16 and older reject under
  `ON_ERROR_STOP`. With `SP_PG_MAJOR=14`, `restore_snapshot` (the nightly path, through `ecto_prove.sh`) requires that
  line to appear exactly once per preamble, drops only that exact line, writes
  `restoring <snapshot> into PostgreSQL 14 without its 2 'SET transaction_timeout = 0;' lines: <SHA-1 of the filtered
  SQL>` to stderr (`prove.log` for `ecto_prove.sh`), and restores the rest with `ON_ERROR_STOP`, so any other
  incompatible statement still fails. A failing `grep` or checksum fails the restore. The compressed snapshot is not
  touched. PostgreSQL 17 gets the bytes unchanged.
- **PostgreSQL 17 only:** `snapshot.sh`, `snapshot_all.sh`, `schemarb_all.sh` and `baseline.sh` write committed files
  (snapshots, `schemarb.tsv`, `baseline.sql`), and `compare.sh`/`compare_all.sh` keep a fresh-install cache keyed by
  the migrations alone. All six exit 2 unless `SP_PG_MAJOR` is `17` and exit 1 when the server is not PostgreSQL 17.
- `scripts/schema_parity/test/pg_major.sh` proves all of this on containers of its own, named `sp-test-<pid>-…` with
  free ports probed from 55700 up and `SP_WORK` in its temporary directory, all removed afterwards; two runs can share
  a machine. Every refusal case runs against a logging fake `docker`, so a broken guard cannot reach a real container:
  `sh scripts/schema_parity/test/pg_major.sh` prints one `ok`/`not ok` line per assertion and exits non-zero on any.

**C4's matrix** covers the states at or after the floor (every `step:`, `rows:`, `contended:` and `upgrade:` check),
the refusal sample, and nothing older, each restored into PostgreSQL 14 and 17. The nightly (see "Nightly matrix")
activates when `feat/phoenix-port` merges into the default branch.

### What CI runs

`.github/workflows/ecto-counterparts.yml` runs `ecto_prove.sh --jobs 2` on the checks
`scripts/schema_parity/pr_checks.rb` selects, and fails unless the summary lists exactly those checks, each with an
`ok` line:
- **Pushes** to `dev` and `master` run every check, and no later push cancels them. **Pull requests** run `fresh` plus
  what their diff against the merge base (`git diff --name-only <base>...HEAD`) selects; a newer push to the same pull
  request cancels the older run. A base commit missing from the checkout fails the job.
- **Shared inputs select every check:** `release_migration.ex` (the step helpers), `release_migrations.ex` (the
  registry), `release_migrator.ex` and everything under `release_migrator/`, `release.ex`, `repo.ex`, any file under
  `app-phoenix/lib/dawarich/release_migrations/` that is not a release module (the `effects/` ports and their
  support), `active_record_encryption.ex` and everything under `active_record_encryption/`,
  `app-phoenix/priv/ruby_encodings.txt`, any file under
  `app-phoenix/priv/release_migrations/` outside a release directory (`baseline.sql`), `priv/repo/`, the harness mix
  task, `app-phoenix/config/`, `mix.exs`, `mix.lock`, `app-phoenix/.tool-versions`, `db/release_migrations.json`,
  `db/release_snapshots/`, `.env.development`, `.ruby-version`, the workflow file and every script directly in
  `scripts/schema_parity/`.
- **Action pin bumps:** a diff to `ecto-counterparts.yml` whose changed lines are all `uses:` lines naming the same
  actions, in the same order, on the removed and the added side (what Dependabot sends) selects only `fresh`; the
  upgrade sample and the harness jobs below still run. Any other edit, a swapped, added or removed action included,
  selects every check. When the diff range is missing or git cannot read the diff, the file is treated as edited
  (every check). `ecto-nightly.yml` is not a shared input: any edit to it selects only `fresh`, and `harness-tests`
  checks its structure.
- **`Gemfile.lock`:** a diff that changes the version of `rails`, `activerecord`, `activesupport`, `activemodel`,
  `railties`, `pg`, `strong_migrations`, `data_migrate`, `oj` or `json` selects every check. Any other `Gemfile.lock`
  change selects only `fresh`.
- **Rails app code** (`app/`, `lib/`, `config/`) that an inline port reproduces is listed in
  `scripts/schema_parity/inline_effects.tsv`, and a change to it selects that release's checks like a change to its
  module (for example `app/services/achievements/migrate_exploration_state.rb` or `config/initializers/oj.rb` →
  1.15.2). Other app code selects only `fresh`; the released migrations are then proven by the push run after the
  merge. Deliberately unmapped, because they change often and a push run after the merge proves them:
  `app/models/user.rb` (its `SoftDeletable` scope, `admin`, `service_settings`), `app/models/place.rb` (1.14.0),
  `app/models/country.rb` and `app/models/region.rb` (1.15.2); `config/locales/en.yml` (the 1.13.1 validation
  messages) is pinned by `geocoding_rails_pins_test.exs`, which runs on every PR.
- **A release module** (`v<release>.ex`, `unreleased.ex`, or a file under `priv/release_migrations/<release>/`) selects
  that release's `step:`, `rows:` and `contended:` checks plus every `upgrade:` check that starts from an older state
  (for `unreleased`, every `upgrade:` check).
- **A `db/migrate` file** selects its state's checks (`unreleased` when no released state lists it). A migration at or
  before the floor selects every `refused:` check.
- **A fixture** (`fixtures/<name>.sql` or `.env`) selects `rows:<name>`, `rows:<name>~shifted` and its release's checks.
  A fixture that maps to no listed check of a release after the floor fails the select step.
- **An unreleased migration that needs a fixture it lacks** (`inventory.rb` decides) fails the select step, on pull
  requests and pushes alike.

The same workflow has three more jobs, which run whatever the diff:
- **Upgrade sample** (`ecto-upgrade-sample`, one leg per PostgreSQL major, 14 and 17, `fail-fast` off). The selection
  above never runs an `upgrade:` check for a change that touches no release, so this job always proves four fixed
  entry states. `scripts/schema_parity/ci/upgrade_sample.rb` picks them from `ecto_prove.sh --list`:
  - the floor, `upgrade:0.37.2`, which runs the whole supported migration path;
  - the newest state in `db/release_migrations.json` (a new release moves it automatically);
  - the shipped `schema.rb` variant `upgrade:1.0.1.schemarb`, a real-install drift;
  - the interrupted upgrade `upgrade:0.37.2@20260108192905`, a resume.

  The selector fails, naming the check, when one of the four is not in `--list` or has no snapshot, rather than
  running fewer. To retire one of those snapshots, change the sample in that file in the same pull request. The proof
  step is `exec scripts/schema_parity/ci/prove_shard.sh <checks>`: the nightly wrapper, which proves the given checks
  instead of a shard, keeps the TERM relay and writes the same `nightly/` record. `ci/nightly_report.rb leg` then
  requires one `ok` line per check, in order, with no `ABORTED` line; and `cmp` requires the list the wrapper
  recorded to be the selected sample byte for byte. The cache follows the nightly: only `tmp/schema_parity/ecto/ref`,
  under the exact key
  `ecto-ref-sample-v<REF_CACHE_FORMAT>-<os>-<runner image>-<ISO year-week>-pg<major>-<inputs>` with the nightly's
  `ci/ref_cache_key.sh` inputs, saved only after a green leg on a miss. Each leg uploads `upgrade-sample-pg<major>`
  (list, harness output, proof record, summary, `prove.log`, diffs) on success and failure. Fresh, unreleased and
  changed-release checks stay with the selection above.
- **Harness tests** (`harness-tests`) run every script under `scripts/schema_parity/test/` except `pg_major.sh`:
  `prove_term.sh`, `prove_shard.sh`, `nightly_report.sh`, `nightly_workflow.rb`, `counterparts_workflow.rb`,
  `matrix_inventory_preflight.sh`, `upgrade_sample.sh`, `pr_checks.sh` (the pin-bump rule above, on synthetic
  diffs in a throwaway repository) and `default_names.sh` (no harness script names `sp-db`, `sp-redis`, `55532` or
  `56479` outside `lib.sh`'s defaults, so the overrides reach every `docker` call). They need no Docker, Bundler or
  database and take about a minute, so the job can be a required check.
- **Harness tests (Docker)** (`harness-docker-tests`) run `pg_major.sh`, which starts PostgreSQL 14 and 17 containers
  of its own. It runs here rather than in the nightly because `infra.sh` and `lib.sh` change in pull requests, and
  the nightly cannot run before `feat/phoenix-port` reaches the default branch.

Every action in the workflow is pinned to a commit with its version in a comment, with the same pins as
`ecto-nightly.yml`. Every Mix cache in both files uses the key
`mix-parity-<os>-<hash of app-phoenix/.tool-versions and mix.lock>`, apart from `ci.yml`'s, because these jobs build
only `_build/parity`; a pull request's jobs can restore the nightly's entry from the default branch.
`ruby scripts/schema_parity/test/counterparts_workflow.rb [file]` checks this, the three jobs above, and that every
new file under `test/` is wired into `harness-tests`.

### Matrix inventory preflight

`scripts/schema_parity/matrix_inventory_preflight.rb` proves the matrix described above cannot silently shrink. It
reads `db/release_migrations.json`, `db/release_snapshots/schemarb.tsv`, `scripts/schema_parity/ecto_expectations.tsv`
and `scripts/schema_parity/inventory.rb`'s output, and cross-checks each against `ecto_prove.sh --list`. It touches
no database and starts no container.

- Every state at or after the floor (`0.37.2`) must have both an `upgrade:<release>` check in `--list` and an
  `<release>.image.sql.gz` or `<release>.replay.sql.gz` snapshot on disk.
- Every `differs` row of `schemarb.tsv` at or after the floor must have both its named `.schemarb.sql.gz` file on
  disk and its `upgrade:<release>.schemarb` check in `--list`. `schemarb.tsv`'s header and column count are
  validated first, so a reshuffled or added column fails loudly instead of making `result` silently read the wrong
  field.
- Every `refused:` line of `ecto_expectations.tsv` must have its backing snapshot on disk and appear in `--list`.
- Every version `inventory.rb` flags `rows`/`validates`/`env`/`effect`/`invalid`, or both `job` and `gated`, must
  have a fixture belonging to its release; the same holds for any `data_added` version of a floor-or-later state.

Run it with `LANG=en_US.UTF-8 ruby scripts/schema_parity/matrix_inventory_preflight.rb`. On success it writes the
check count by kind and the exact ordered list to `$SP_WORK/inventory_preflight.txt` (`tmp/schema_parity/` by
default, never committed); on any gap, or a malformed input file, it aborts with a `matrix inventory preflight: …`
message naming the release, check or version, never a raw backtrace. No total check count is hard-coded; the gate
is that `db/release_migrations.json`, the tsv files and `--list` agree, so the total is free to grow.

**Known limit.** Fixture coverage is per release, not per version or per gated branch, for `rows`/`validates`/`env`/
`invalid`/`job+gated`/`effect` versions: a release qualifies once any one of its fixtures exists (its main
`<release>.sql`/`.env`, or any `<release>--…` variant), because fixture names do not carry the migration version —
except `unreleased--<version>[-<variant>]` fixtures, which the preflight matches by version instead, and any
`data_added` version, which likewise requires its version in the fixture name. Deleting one variant fixture out of
several for the same release is not caught; deleting every fixture a release needs is. The variant part of a
fixture name is not load-bearing for this rule: C3a renamed C2's effect-stop fixtures to data names
(`1.7.6--duplicate-tracks`) as it ported each effect.

### Nightly matrix

`.github/workflows/ecto-nightly.yml` runs the whole `--list` on PostgreSQL 14 and 17 every night at 01:41 UTC and
on manual dispatch, with a read-only token. A newer run of the same ref cancels an older one.

- **Activation.** GitHub runs `schedule` only from the default branch, so nothing runs before `feat/phoenix-port` is
  merged there. GitHub may also delay or drop a scheduled run, and a dropped run leaves no report behind. Check the
  schedule history (`gh run list --workflow ecto-nightly.yml --event schedule`) rather than trusting the absence of
  a red run. `workflow_dispatch` also needs the file on the default branch, so until the merge the nightly has no
  GitHub run apart from the two calibration runs below: the evidence is the pull request's `ecto-counterparts`,
  `ecto-upgrade-sample`, `harness-tests` and `harness-docker-tests` jobs plus local shard runs (see "Calibration").
  Do not describe a nightly as running before the schedule history shows one.
- **Matrix.** Four jobs, `pg14-shard1`, `pg14-shard2`, `pg17-shard1` and `pg17-shard2`, each on its own runner with the
  default `sp-db`/`sp-redis`. `fail-fast` is off, so every server and shard reports. Each job has 180 minutes.
- **Calibration** (local, 2026-09-26, before C3a: the 267-check list). Each shard ran the workflow's own step blocks in order
  (`SHARD=k SHARDS=2`, `exec ci/prove_shard.sh`, two lanes) on containers of its own, with a fresh stack and work
  directory per run and the reference cache emulated under the exact key. The two majors ran side by side on an
  18-core M5 Pro (OrbStack; the `linux/amd64` images run emulated) with other sessions loading the machine. Setup is
  `infra.sh up`, the server check and the preflight; the Actions setup steps (apt, Ruby, BEAM, Mix) are not in it.
  Peak memory is the harness's process tree plus the PostgreSQL container, sampled every ~13 s.

  | Run | PG | Shard | Checks | Setup | Proof | Lanes / contended phase | Refs reused / computed | Peak memory |
  |---|---|---|---|---|---|---|---|---|
  | cold | 14 | 1 | 134 | 10 s | 1777 s (29.6 min) | 1136 s / 638 s | 0 / 129 | 464 + 314 MB |
  | cold | 14 | 2 | 133 | 11 s | 1562 s (26.0 min) | 1086 s / 473 s | 0 / 130 | 389 + 280 MB |
  | cold | 17 | 1 | 134 | 11 s | 1762 s (29.4 min) | 1124 s / 636 s | 0 / 129 | 449 + 334 MB |
  | cold | 17 | 2 | 133 | 11 s | 1555 s (25.9 min) | 1080 s / 473 s | 0 / 130 | 395 + 302 MB |
  | warm | 14 | 1 | 134 | 13 s | 1454 s (24.2 min) | 815 s / 638 s | 129 / 0 | 333 + 377 MB |
  | warm | 14 | 2 | 133 | 13 s | 1256 s (20.9 min) | 783 s / 471 s | 130 / 0 | 391 + 288 MB |
  | warm | 17 | 1 | 134 | 11 s | 1443 s (24.1 min) | 802 s / 638 s | 129 / 0 | 394 + 271 MB |
  | warm | 17 | 2 | 133 | 11 s | 1251 s (20.9 min) | 777 s / 471 s | 130 / 0 | 396 + 266 MB |

  Warm references only save the Rails side of the non-contended checks (lanes about 28 % faster). Contended checks
  always rerun their Rails side, and templates are rebuilt on a fresh runner.

  Every run was green, with the same outcomes on both majors: 239 `ok`, 16 `ok (failed@…)`, 3 `ok (refused …)` and 9
  C2 effect stops, which C3a has since turned into row comparisons. A cold shard needs about 2200 lane-seconds plus its contended checks (638 s for shard 1, which
  holds 1.10.1, 473 s for shard 2, which holds 1.13.1). With the runner's two lanes that is the same ≈ 30 min per
  shard; with lanes twice as slow as this machine's, ≈ 50 min, plus about 5 min of Actions setup. C3a's list (358
  checks) adds about a third to the lane work: ≈ 36–62 min. Two shards stay; the first cold Actions run confirmed it.
- **GitHub calibration** (2026-09-26, 360 checks, through a `pull_request` trigger on draft PR #3744 that was added
  for these two runs and then reverted). Each job ran 180 checks with 0 failed. Setup took about a minute per job.

  | Run | pg14-shard1 | pg14-shard2 | pg17-shard1 | pg17-shard2 |
  |---|---|---|---|---|
  | cold, `36243570745` (no reference cache yet) | 27.5 min | 30.7 min | 26.4 min | 29.7 min |
  | warm, `36247645747` | 26.7 min | 29.4 min | 26.2 min | 30.1 min |

  The warm run is no faster: on the standard runner the lanes spend their time on the Ecto side and on templates,
  so the reference cache saves little. Every job stays far below the 90-minute limit, so two shards per major
  stay. The pull request's `ecto-counterparts` job runs all 360 checks on one runner in about 56 min.
- **One job.** Ruby comes from `.ruby-version`, OTP/Elixir from `app-phoenix/.tool-versions`, and GEOS from apt, with
  the Bundler and Mix caches. `infra.sh up` starts the job's PostgreSQL. The job then asserts the server major, that
  PostGIS is available and that Redis answers `PING`, before running the matrix inventory preflight, whose output
  also goes to `inventory_preflight.out` (the step still fails with the preflight's exit status).
  The proof step is `exec scripts/schema_parity/ci/prove_shard.sh`, so the runner's cancel signal reaches the
  wrapper itself. The wrapper saves the shard's `--list`, writes `started=` to `nightly/proof.env`, and runs
  `timeout -k 60 150m ecto_prove.sh --shard K/2 --jobs 2 all` in the background into `nightly/proof.out`,
  streaming it to the log with `tail -f --pid`. On SIGINT or SIGTERM (a cancelled run, or a job past its 180
  minutes) it sends TERM to `timeout`, which relays it to the harness's process group. The harness then writes its
  `ABORTED` line, and the wrapper waits for it. At the end it appends the exit code, the end time and the reference
  counts to `proof.env`. `ci/nightly_report.rb leg` then compares the summary with that list.
- **Cache.** Only `tmp/schema_parity/ecto/ref` is cached. Scratch databases, templates, diffs, `.env` files and the
  canonical-dump memo never are. The key is exact, with no `restore-keys`:
  `ecto-ref-nightly-v<REF_CACHE_FORMAT>-<os>-<runner image>-<ISO year-week>-pg<major>-shard<k>-of-<n>-<inputs>`.
  The runner image (`$ImageOS`) and the ISO week make every entry expire at least weekly, so no reference outlives
  a week or a runner image change. `<inputs>` comes from `ci/ref_cache_key.sh`: the code key above (Rails inputs,
  `ruby -v`, `SP_PG_MAJOR`, the harness scripts directly in `scripts/schema_parity/`, `canon.rb` and `normalize.sh`
  included) plus the bytes of `db/schema.rb` (the `fresh` references), `db/release_snapshots/` except its
  `README.md`, `scripts/schema_parity/fixtures/` and `ecto_expectations.tsv`. Separate keys per major and shard keep
  four jobs from racing to write one entry. A job saves its entry only after a green shard, and only on a miss. Each
  check's own reference key stays the final test: a restored reference made under another code key is ignored and
  recomputed. Bump `REF_CACHE_FORMAT` in the workflow to discard every entry.
- **Reference counts.** `refs_computed` counts the references this run wrote. `refs_reused` counts the shard's
  checks that had a reference with the current code key at the start and wrote none themselves. On a green shard,
  those are exactly the checks whose per-check key accepted a stored reference. A restored reference under another
  code key, or with a per-check key the check rejected, does not count. The report shows `-` for a shard whose
  harness did not exit 0.
- **Evidence.** On success and on failure, each job uploads `pg<major>-shard<k>`: the summary, `prove.log`, the
  diffs, `inventory_preflight.txt`, `inventory_preflight.out` and `nightly/` (list, harness output, `proof.env`).
  Neither this artifact nor the
  report sets a retention, so both follow the repository's retention setting.
- **Report.** The `nightly report` job runs after the four jobs whatever their outcome, with `actions: read`. It
  lists the job results and artifact ids through the API and runs `ci/nightly_report.rb report`. It fails, naming the
  shard, when:
  - a job's result is anything but success, including cancelled or timed out;
  - the matrix inventory preflight failed (its message is quoted from `inventory_preflight.out`);
  - an artifact or a proof record is missing, the proof record has no exit (the wrapper was killed), or the harness
    exited non-zero (124 means GNU `timeout`);
  - more than one file matches a proof record, list or summary, instead of one being picked;
  - per PostgreSQL major, the shards' `--list` files overlap, or together differ from the full list, which the
    report job prints with `ruby scripts/schema_parity/list_checks.rb .`. This catches a shard that never ran, or
    `SHARDS` drifting from the matrix;
  - the summary is missing, has an `ABORTED` line, or has a line whose status differs from the declared outcome
    (`ecto_expectations.tsv`, plain `ok` otherwise). The report prints the expected and actual status;
  - a listed check has no line, a line repeats or is not listed, or the lines are out of `--list` order;
  - the matrix result is not success.

  The step summary and the `nightly-report` artifact hold one table row per shard: PG major, shard, job result,
  checks run, elapsed time, references reused/computed, failures and the artifact link. A list of the failures
  follows. A green night is what the matrix owes A12; A12's other gate, the outbox drain, belongs to A1 and A1.x
  (see "C3a: inline effects, and what is handed on"). The report job's `LEGS` must match the matrix; the workflow
  test enforces this.
- **Tests.** `sh scripts/schema_parity/test/prove_term.sh [dash]` covers the TERM paths with a fake `docker`: GNU
  `timeout` during the lanes, a FAIL that finished before the TERM, a TERM during the serial contended phase, a TERM
  during `mix compile`, and a `docker exec` timeout during the database cleanup.
  `sh scripts/schema_parity/test/prove_shard.sh [dash]` runs the proof step as the workflow does
  (`exec …/prove_shard.sh` under `bash -e`). It sends the step SIGINT, SIGTERM and SIGKILL, and checks the reference
  counts on a fake harness, and that check names given as arguments are proved instead of a shard.
  `sh scripts/schema_parity/test/nightly_report.sh` runs the report over synthetic
  artifacts. `ruby scripts/schema_parity/test/nightly_workflow.rb [file]` is a structural check of the
  workflow, used in place of `actionlint`. The `harness-tests` job of `ecto-counterparts.yml` runs all of them on
  every pull request and push (see "What CI runs"). The `ci/` and `test/` scripts sit in subdirectories, outside
  `pr_checks.rb`'s shared inputs and outside the code key: its `scripts/schema_parity/*.sh` and `*.rb` are shell
  globs, expanded to the top-level files before git sees them. Editing them selects no checks and keeps every
  reference.

### At a release

1. Eugene tags the release and fetches the tags.
2. `LANG=en_US.UTF-8 DATABASE_NAME=sp_unused RAILS_ENV=test bin/rails schema_parity:release_map`, then
   `LANG=en_US.UTF-8 scripts/schema_parity/snapshot_all.sh` for the new state (see "Regenerate").
3. Rename `app-phoenix/lib/dawarich/release_migrations/unreleased.ex` to `v<release with dots as underscores>.ex`,
   rename the module to `Dawarich.ReleaseMigrations.V<same>`, set `release/0` to the state's `first_release`, and
   create a new empty `Unreleased` (`release/0` `"unreleased"`, `steps/0` and `data_versions/0` `[]`).
4. Rename `scripts/schema_parity/fixtures/unreleased*` to `<release>*`, and rename the `unreleased` checks in
   `ecto_expectations.tsv` the same way.
5. Update `@releases` in `app-phoenix/lib/dawarich/release_migrations.ex`: the new module goes before `Unreleased`.
6. `scripts/schema_parity/baseline.sh` (required).
7. `ecto_prove.sh fresh step:<release> upgrade:<previous state>` plus the new `rows:` checks, and `mix test` in
   `app-phoenix/`.

### C3a: inline effects, and what is handed on

C3a (`superpowers/plans/2026-09-25-phoenix-c3-migration-app-code-plan.md` at the workspace root, executed as C3a on
2026-09-26) ported every synchronous effect a supported migration reaches. Each port lives in
`app-phoenix/lib/dawarich/release_migrations/effects/`, runs where Rails runs the effect, and is proven by the
release's `rows:` checks against current Rails (see "Proof inventory" for the fixture names):

| Version | Rails effect | Port |
|---|---|---|
| 1.7.6 `20260508193900` | `DataMigrations::DedupeTracksForUniqueIndexJob.perform_now` → `Tracks::Deduplicator`, for every user with duplicates, soft-deleted users included | `dedupe_tracks_for_unique_index.ex` |
| 1.13.1 `20260819120100` | `User.find_each { Geocoding::SeedFromEnv.call(user) }` | `seed_geocoding_from_env.ex` |
| 1.14.0 `20260815100001` | `DataMigrations::BackfillPlacesUserIdJob.perform_now`, then the migration's `remaining=<n>` recount and curated `ActiveRecord::MigrationError` | `backfill_places_user_id.ex` |
| 1.15.0 `20260901150000` | `InstanceSettings::Backfill.call` | `backfill_instance_settings.ex` |
| 1.15.2 `20260714224647`, `20260720170000` | `Achievements::LoadRegions` | `load_regions.ex` |
| 1.15.2 `20260720160000` | `Achievements::MigrateExplorationState` | `migrate_exploration_state.ex` |

- **Encrypted settings.** 1.13.1 and 1.15.0 read and write `service_settings` and `instance_settings` secrets through
  `Dawarich.ActiveRecordEncryption`, which needs the Rails app's environment (item 1 of "How a database is migrated").
  `decrypt_columns.rb` proves that Rails reads what Phoenix writes.
- **Differences** that remain are `ED-021` to `ED-029` in `app-phoenix/parity/expected_diffs.md`; `ED-019` (the
  seven stops) is closed.
- **The outbox has no consumer yet.** Release modules record 22 job classes in `phoenix.release_migration_jobs`
  (`rg -n '\bjob\(' app-phoenix/lib/dawarich/release_migrations`; the per-user and per-import jobs of 1.0.2, 1.1.0
  and `Unreleased` are built across several lines). `ReleaseEffectInventory` gives each an owner: A1.x wave 5 or 6.
  The plan's relay (C3 Task 1) moved to A1, one relay for Rails' job outbox and this one; its workers (C3 Tasks 6–8)
  moved to A1.x waves 5–6. **A12 gate:** before the migrator goes live, every recorded class has a worker and the
  outbox drains.
- **1.0.2 still records no job** (C2's proof). The `Unreleased` step `20260925100100` records
  `DataMigrations::BackfillTransportationModesJob` and `TransportationModes::ImportBackfillJob` (A1.x wave 5).
- **`admin1_world.geojson`** reaches the release through the `app-phoenix/priv` link and the image's `COPY`. A12
  moves the file into `app-phoenix/priv` when the Rails tree goes.
- **No `db/data` migration to port.** All 27 predate the floor, and `pending_data` is `[]` on every supported
  database.

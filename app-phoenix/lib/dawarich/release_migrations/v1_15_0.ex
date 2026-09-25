defmodule Dawarich.ReleaseMigrations.V1_15_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @registry_variables ~w[
    PHOTON_API_HOST
    PHOTON_API_KEY
    PHOTON_API_USE_HTTPS
    NOMINATIM_API_HOST
    NOMINATIM_API_KEY
    NOMINATIM_API_USE_HTTPS
    GEOAPIFY_API_KEY
    LOCATIONIQ_API_KEY
    REVERSE_GEOCODING_RPS
    STORE_GEODATA
  ]

  @impl true
  def release, do: "1.15.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260901140000", &create_instance_settings/1},
      {"20260901150000", &backfill_instance_settings/1},
      {"20260911150000", &create_trip_sources_and_planned_itineraries/1},
      {"20260914090000", &add_lock_versions_to_points_and_tracks/1, transaction: false},
      {"20260914120000", &create_planned_unplanned_places/1},
      {"20260914130000", &add_selection_token_to_trip_sources/1},
      {"20260914140000", &add_importing_to_trip_sources/1},
      {"20260919190000", &add_source_digest_to_notes/1}
    ]
  end

  def registry_variables, do: @registry_variables

  defp create_instance_settings(repo) do
    sql!(repo, ~S"""
    CREATE TABLE "instance_settings" ("id" bigserial primary key, "key" character varying NOT NULL, "value" jsonb, "encrypted_value" text, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL);
    CREATE UNIQUE INDEX "index_instance_settings_on_key" ON "instance_settings" ("key");
    """)
  end

  defp backfill_instance_settings(repo) do
    if exists?(repo, "SELECT 1 FROM users") or Enum.any?(@registry_variables, &env_set?/1) do
      unported!("InstanceSettings::Backfill")
    end
  end

  defp env_set?(name), do: not Regex.match?(~r/\A[\x00\x09-\x0D ]*\z/, System.get_env(name, ""))

  defp create_trip_sources_and_planned_itineraries(repo) do
    sql!(repo, ~S"""
    CREATE TABLE "trip_sources" ("id" bigserial primary key, "user_id" bigint NOT NULL, "provider" character varying NOT NULL, "base_url" character varying NOT NULL, "api_key" text, "status" integer DEFAULT 0 NOT NULL, "last_synced_at" timestamp(6), "last_error" text, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_68802491ff"
    FOREIGN KEY ("user_id")
      REFERENCES "users" ("id")
    );
    CREATE INDEX "index_trip_sources_on_user_id" ON "trip_sources" ("user_id");
    CREATE UNIQUE INDEX "index_trip_sources_on_user_id_and_provider_and_base_url" ON "trip_sources" ("user_id", "provider", "base_url");
    ALTER TABLE "trips" ADD "trip_source_id" bigint;
    CREATE INDEX "index_trips_on_trip_source_id" ON "trips" ("trip_source_id");
    ALTER TABLE "trips" ADD CONSTRAINT "fk_rails_87736b63c9"
    FOREIGN KEY ("trip_source_id")
      REFERENCES "trip_sources" ("id");
    ALTER TABLE "trips" ADD "source_identifier" character varying, ADD "source_status" integer, ADD "source_digest" character varying, ADD "source_synced_at" timestamp(6), ADD "source_snapshot" jsonb DEFAULT '{}' NOT NULL;
    CREATE UNIQUE INDEX "index_trips_on_source_identifier" ON "trips" ("trip_source_id", "source_identifier") WHERE trip_source_id IS NOT NULL AND source_identifier IS NOT NULL;
    CREATE TABLE "planned_days" ("id" bigserial primary key, "trip_id" bigint NOT NULL, "date" date NOT NULL, "position" integer NOT NULL, "title" character varying, "notes" text, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_0731461927"
    FOREIGN KEY ("trip_id")
      REFERENCES "trips" ("id")
    );
    CREATE INDEX "index_planned_days_on_trip_id" ON "planned_days" ("trip_id");
    CREATE UNIQUE INDEX "index_planned_days_on_trip_id_and_date" ON "planned_days" ("trip_id", "date");
    CREATE TABLE "planned_stops" ("id" bigserial primary key, "planned_day_id" bigint NOT NULL, "position" integer NOT NULL, "name" character varying NOT NULL, "address" character varying, "latitude" decimal(10,6), "longitude" decimal(10,6), "starts_at" character varying, "ends_at" character varying, "duration_minutes" integer, "category" character varying, "transport_mode" character varying, "notes" text, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_8f47bacbc3"
    FOREIGN KEY ("planned_day_id")
      REFERENCES "planned_days" ("id")
    );
    CREATE INDEX "index_planned_stops_on_planned_day_id" ON "planned_stops" ("planned_day_id");
    CREATE UNIQUE INDEX "index_planned_stops_on_planned_day_id_and_position" ON "planned_stops" ("planned_day_id", "position");
    CREATE TABLE "planned_day_notes" ("id" bigserial primary key, "planned_day_id" bigint NOT NULL, "position" integer NOT NULL, "noted_at" character varying, "body" text NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_192e307bb0"
    FOREIGN KEY ("planned_day_id")
      REFERENCES "planned_days" ("id")
    );
    CREATE INDEX "index_planned_day_notes_on_planned_day_id" ON "planned_day_notes" ("planned_day_id");
    CREATE UNIQUE INDEX "index_planned_day_notes_on_planned_day_id_and_position" ON "planned_day_notes" ("planned_day_id", "position");
    CREATE TABLE "planned_reservations" ("id" bigserial primary key, "trip_id" bigint NOT NULL, "planned_day_id" bigint, "reservation_type" character varying, "title" character varying NOT NULL, "location" character varying, "starts_at" timestamp(6), "ends_at" timestamp(6), "status" character varying, "notes" text, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_cf56dde9df"
    FOREIGN KEY ("trip_id")
      REFERENCES "trips" ("id")
    , CONSTRAINT "fk_rails_00204e276b"
    FOREIGN KEY ("planned_day_id")
      REFERENCES "planned_days" ("id")
    );
    CREATE INDEX "index_planned_reservations_on_trip_id" ON "planned_reservations" ("trip_id");
    CREATE INDEX "index_planned_reservations_on_planned_day_id" ON "planned_reservations" ("planned_day_id");
    CREATE TABLE "planned_accommodations" ("id" bigserial primary key, "trip_id" bigint NOT NULL, "name" character varying NOT NULL, "address" character varying, "latitude" decimal(10,6), "longitude" decimal(10,6), "starts_on" date, "ends_on" date, "check_in_at" character varying, "check_out_at" character varying, "notes" text, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_1102389bc3"
    FOREIGN KEY ("trip_id")
      REFERENCES "trips" ("id")
    );
    CREATE INDEX "index_planned_accommodations_on_trip_id" ON "planned_accommodations" ("trip_id");
    CREATE TABLE "planned_travellers" ("id" bigserial primary key, "trip_id" bigint NOT NULL, "name" character varying NOT NULL, "owner" boolean DEFAULT FALSE NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_6df76de6a5"
    FOREIGN KEY ("trip_id")
      REFERENCES "trips" ("id")
    );
    CREATE INDEX "index_planned_travellers_on_trip_id" ON "planned_travellers" ("trip_id");
    """)
  end

  defp add_lock_versions_to_points_and_tracks(repo) do
    for table <- ~w[points tracks] do
      case with_lock_retry(repo, fn -> add_lock_version(repo, table) end,
             lock_timeout: "5s",
             attempts: 5,
             backoff_seconds: 5
           ) do
        :acquired -> :ok
        {:not_acquired, error} -> raise error
      end
    end
  end

  defp add_lock_version(repo, table) do
    unless column?(repo, table, "lock_version") do
      sql!(repo, ~s|ALTER TABLE "#{table}" ADD "lock_version" integer DEFAULT 0 NOT NULL;|)
    end
  end

  defp create_planned_unplanned_places(repo) do
    sql!(repo, ~S"""
    CREATE TABLE "planned_unplanned_places" ("id" bigserial primary key, "trip_id" bigint NOT NULL, "position" integer NOT NULL, "name" character varying NOT NULL, "address" character varying, "latitude" decimal(10,6), "longitude" decimal(10,6), "starts_at" character varying, "ends_at" character varying, "duration_minutes" integer, "category" character varying, "transport_mode" character varying, "notes" text, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_5fe1067864"
    FOREIGN KEY ("trip_id")
      REFERENCES "trips" ("id")
    );
    CREATE INDEX "index_planned_unplanned_places_on_trip_id" ON "planned_unplanned_places" ("trip_id");
    CREATE UNIQUE INDEX "index_planned_unplanned_places_on_trip_id_and_position" ON "planned_unplanned_places" ("trip_id", "position");
    """)
  end

  defp add_selection_token_to_trip_sources(repo) do
    sql!(repo, ~S"""
    ALTER TABLE "trip_sources" ADD "selection_token" character varying;
    """)
  end

  defp add_importing_to_trip_sources(repo) do
    sql!(repo, ~S"""
    ALTER TABLE "trip_sources" ADD "importing" boolean DEFAULT FALSE NOT NULL;
    """)
  end

  defp add_source_digest_to_notes(repo) do
    sql!(repo, ~S"""
    ALTER TABLE "notes" ADD "source_digest" character varying;
    """)
  end
end

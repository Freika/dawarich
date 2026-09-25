defmodule Dawarich.ReleaseMigrations.V1_13_1 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @original_path_index_invalid """
  SELECT NOT i.indisvalid
  FROM pg_class c
  JOIN pg_index i ON i.indexrelid = c.oid
  WHERE c.relname = 'index_tracks_on_original_path'
  """

  @impl true
  def release, do: "1.13.1"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260816150000", &create_point_dimension_tables/1, transaction: false},
      {"20260816150100", &drop_visit_null_partial_index/1, transaction: false},
      {"20260816150200", &enqueue_point_dimension_backfills/1},
      {"20260818201239", &add_gist_index_to_tracks_original_path/1, transaction: false},
      {"20260819120000", &create_service_settings/1},
      {"20260819120100", &seed_geocoding_service_settings_from_env/1}
    ]
  end

  defp create_point_dimension_tables(repo) do
    sql!(repo, ~S"""
    CREATE TABLE IF NOT EXISTS "point_sources" ("id" serial NOT NULL PRIMARY KEY, "digest" character varying(32) NOT NULL, "tracker_id" character varying, "topic" character varying, "ssid" character varying, "bssid" character varying, "connection" integer, "trigger" integer, "battery_status" integer, "inrids" text[], "in_regions" text[], "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL);
    """)

    sql!(repo, ~S"""
    CREATE UNIQUE INDEX IF NOT EXISTS "index_point_sources_on_digest" ON "point_sources" ("digest");
    """)

    case with_lock_retry(repo, fn -> add_source_id(repo) end,
           lock_timeout: "1s",
           attempts: 5,
           backoff_seconds: 2,
           on: [:lock_not_available, :query_canceled]
         ) do
      :acquired -> :ok
      {:not_acquired, _} -> :ok
    end
  end

  defp add_source_id(repo) do
    sql!(repo, ~S"""
    ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer;
    """)
  end

  defp drop_visit_null_partial_index(repo) do
    if index?(repo, "points", name: "idx_points_user_visit_null_timestamp") do
      sql!(repo, ~S"""
      DROP INDEX CONCURRENTLY "idx_points_user_visit_null_timestamp";
      """)
    end
  end

  defp enqueue_point_dimension_backfills(repo) do
    cond do
      not column?(repo, "points", "source_id") ->
        {:jobs, [job("DataMigrations::AddPointDimensionColumnsJob")]}

      backfill_allowed?() ->
        {:jobs, [job("DataMigrations::BackfillPointDimensionsJob")]}

      true ->
        nil
    end
  end

  defp backfill_allowed? do
    self_hosted?() and String.trim(System.get_env("SKIP_POINT_DIMENSION_BACKFILL", "")) == ""
  end

  defp add_gist_index_to_tracks_original_path(repo) do
    require_zero_lock_timeout!(repo)

    if original_path_index_invalid?(repo) and
         index?(repo, "tracks", name: "index_tracks_on_original_path") do
      sql!(repo, ~S"""
      DROP INDEX CONCURRENTLY "index_tracks_on_original_path";
      """)
    end

    sql!(repo, ~S"""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_tracks_on_original_path" ON "tracks" USING gist ("original_path");
    """)
  end

  defp original_path_index_invalid?(repo) do
    case repo.query!(@original_path_index_invalid, [], log: false) do
      %{rows: [[invalid] | _]} -> invalid == true
      %{rows: []} -> false
    end
  end

  defp create_service_settings(repo) do
    sql!(repo, ~S"""
    CREATE TABLE IF NOT EXISTS "service_settings" ("id" bigserial primary key, "user_id" bigint NOT NULL, "service" integer NOT NULL, "provider" character varying NOT NULL, "config" jsonb DEFAULT '{}' NOT NULL, "credentials" text, "active" boolean DEFAULT FALSE NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_bcdd50bba4"
    FOREIGN KEY ("user_id")
      REFERENCES "users" ("id")
    );
    CREATE INDEX IF NOT EXISTS "index_service_settings_on_user_id" ON "service_settings" ("user_id");
    CREATE UNIQUE INDEX IF NOT EXISTS "index_service_settings_on_user_id_and_service_and_provider" ON "service_settings" ("user_id", "service", "provider");
    CREATE UNIQUE INDEX IF NOT EXISTS "index_service_settings_on_user_service_active" ON "service_settings" ("user_id", "service") WHERE "active";
    """)
  end

  defp seed_geocoding_service_settings_from_env(repo) do
    if self_hosted?() and exists?(repo, "SELECT 1 FROM users"),
      do: unported!("Geocoding::SeedFromEnv")
  end
end

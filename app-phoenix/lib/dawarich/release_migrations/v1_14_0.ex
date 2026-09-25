defmodule Dawarich.ReleaseMigrations.V1_14_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @places_check_constraint """
  SELECT 1 FROM pg_constraint WHERE conrelid = 'places'::regclass AND contype = 'c' AND conname = 'places_user_id_not_null'
  """

  @places_user_id_not_null """
  SELECT 1 FROM pg_attribute
  WHERE attrelid = '"places"'::regclass AND attname = 'user_id' AND attnum > 0 AND NOT attisdropped
    AND attnotnull
  """

  @impl true
  def release, do: "1.14.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260815100000", &add_places_user_id_not_null_check/1},
      {"20260815100001", &validate_places_user_id_not_null/1, transaction: false},
      {"20260823190000", &enqueue_frozen_fix_anomaly_recalculation/1, transaction: false},
      {"20260825120000", &enqueue_country_alias_backfill/1},
      {"20260825120100", &create_route_videos/1}
    ]
  end

  defp add_places_user_id_not_null_check(repo) do
    unless exists?(repo, @places_check_constraint) do
      sql!(repo, ~S"""
      ALTER TABLE "places" ADD CONSTRAINT places_user_id_not_null CHECK (user_id IS NOT NULL) NOT VALID;
      """)
    end
  end

  defp validate_places_user_id_not_null(repo) do
    unless exists?(repo, @places_user_id_not_null) do
      if exists?(repo, "SELECT 1 FROM places WHERE user_id IS NULL"),
        do: unported!("DataMigrations::BackfillPlacesUserIdJob")

      if exists?(repo, @places_check_constraint) do
        sql!(repo, ~S"""
        ALTER TABLE "places" VALIDATE CONSTRAINT "places_user_id_not_null";
        """)
      end

      sql!(repo, ~S"""
      ALTER TABLE "places" ALTER COLUMN "user_id" SET NOT NULL;
      """)
    end

    if exists?(repo, @places_check_constraint) do
      sql!(repo, ~S"""
      ALTER TABLE "places" DROP CONSTRAINT "places_user_id_not_null";
      """)
    end
  end

  defp enqueue_frozen_fix_anomaly_recalculation(repo) do
    sql!(repo, ~S"""
    UPDATE users SET settings = settings - ARRAY['anomaly_rules_recalculation_queued_at', 'anomaly_rules_recalculated_at', 'anomaly_rules_recalculation_failed_at']::text[] WHERE settings ?| ARRAY['anomaly_rules_recalculation_queued_at', 'anomaly_rules_recalculated_at', 'anomaly_rules_recalculation_failed_at']::text[];
    """)

    {:jobs, [job("DataMigrations::RecalculateAnomaliesJob")]}
  end

  defp enqueue_country_alias_backfill(repo) do
    if backfill_allowed?() and exists?(repo, "SELECT 1 FROM point_sources") do
      {:jobs, [job("DataMigrations::BackfillPointCountryIdJob")]}
    end
  end

  defp create_route_videos(repo) do
    sql!(repo, ~S"""
    CREATE TABLE IF NOT EXISTS "route_videos" ("id" bigserial primary key, "user_id" bigint NOT NULL, "name" character varying NOT NULL, "status" integer DEFAULT 0 NOT NULL, "settings" jsonb DEFAULT '{}' NOT NULL, "expired_at" timestamp(6), "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_02b56b6dae"
    FOREIGN KEY ("user_id")
      REFERENCES "users" ("id")
    );
    CREATE INDEX IF NOT EXISTS "index_route_videos_on_user_id_and_created_at" ON "route_videos" ("user_id", "created_at");
    """)
  end
end

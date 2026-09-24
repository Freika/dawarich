defmodule Dawarich.ReleaseMigrations.V1_15_2 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.15.2"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260714000001", &create_achievement_tables/1},
      {"20260714212634", &create_regions/1},
      {"20260714224647", &seed_achievement_regions/1},
      {"20260720160000", &merge_exploration_progress/1},
      {"20260720170000", &seed_planet_regions/1},
      {"20260918103000", &create_achievement_unlock_events/1},
      {"20260922120000", &enqueue_achievements_backfill/1}
    ]
  end

  defp create_achievement_tables(repo) do
    unless table?(repo, "achievement_progresses") do
      sql!(repo, ~S"""
      CREATE TABLE "achievement_progresses" ("id" bigserial primary key, "user_id" bigint NOT NULL, "achievement_key" character varying NOT NULL, "state" jsonb DEFAULT '{}' NOT NULL, "sharing_enabled" boolean DEFAULT FALSE NOT NULL, "sharing_uuid" character varying, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_103a2f87f0"
      FOREIGN KEY ("user_id")
        REFERENCES "users" ("id")
      );
      CREATE UNIQUE INDEX "index_achievement_progresses_on_user_id_and_achievement_key" ON "achievement_progresses" ("user_id", "achievement_key");
      CREATE UNIQUE INDEX "index_achievement_progresses_on_sharing_uuid" ON "achievement_progresses" ("sharing_uuid");
      """)
    end

    unless table?(repo, "user_achievements") do
      sql!(repo, ~S"""
      CREATE TABLE "user_achievements" ("id" bigserial primary key, "user_id" bigint NOT NULL, "achievement_key" character varying NOT NULL, "earned_at" timestamp(6) NOT NULL, "metadata" jsonb DEFAULT '{}' NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_4efde02858"
      FOREIGN KEY ("user_id")
        REFERENCES "users" ("id")
      );
      CREATE UNIQUE INDEX "index_user_achievements_on_user_id_and_achievement_key" ON "user_achievements" ("user_id", "achievement_key");
      """)
    end
  end

  defp create_regions(repo) do
    unless table?(repo, "regions") do
      sql!(repo, ~S"""
      CREATE TABLE "regions" ("id" bigserial primary key, "code" character varying NOT NULL, "geom" geometry(MULTIPOLYGON,4326) NOT NULL, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL);
      CREATE UNIQUE INDEX "index_regions_on_code" ON "regions" ("code");
      CREATE INDEX "index_regions_on_geom" ON "regions" USING gist ("geom");
      """)
    end
  end

  defp seed_achievement_regions(repo) do
    if table?(repo, "regions") and exists?(repo, "SELECT 1 FROM countries") and
         not exists?(repo, "SELECT 1 FROM regions") do
      unported!("Achievements::LoadRegions")
    end
  end

  defp merge_exploration_progress(repo) do
    if table?(repo, "achievement_progresses") and
         (exists?(repo, "SELECT 1 FROM achievement_progresses") or
            exists?(repo, "SELECT 1 FROM user_achievements")) do
      unported!("Achievements::MigrateExplorationState")
    end
  end

  defp seed_planet_regions(repo) do
    if table?(repo, "regions") do
      sql!(repo, ~S"""
      DELETE FROM "regions" WHERE NOT ((code LIKE '%-%'));
      """)

      if exists?(repo, "SELECT 1 FROM countries"), do: unported!("Achievements::LoadRegions")
    end
  end

  defp create_achievement_unlock_events(repo) do
    unless table?(repo, "achievement_unlock_events") do
      sql!(repo, ~S"""
      CREATE TABLE "achievement_unlock_events" ("id" bigserial primary key, "user_id" bigint NOT NULL, "kind" character varying NOT NULL, "key" character varying NOT NULL, "claimed_at" timestamp(6), "claim_token" character varying, "seen_at" timestamp(6), "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL, CONSTRAINT "fk_rails_ed0477f0f9"
      FOREIGN KEY ("user_id")
        REFERENCES "users" ("id")
       ON DELETE CASCADE);
      CREATE INDEX "index_achievement_unlock_events_on_user_id" ON "achievement_unlock_events" ("user_id");
      CREATE UNIQUE INDEX "index_achievement_unlock_events_on_user_kind_key" ON "achievement_unlock_events" ("user_id", "kind", "key");
      CREATE INDEX "index_achievement_unlock_events_pending" ON "achievement_unlock_events" ("user_id", "id") WHERE seen_at IS NULL;
      """)
    end
  end

  defp enqueue_achievements_backfill(_repo),
    do: {:jobs, [job("DataMigrations::BackfillAchievementsJob")]}
end

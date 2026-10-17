defmodule Dawarich.ReleaseMigrations.V1_14_3 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.14.3"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260901184613", &add_calculation_version_to_stats/1},
      {"20260901203451", &add_stats_swept_at_to_users/1},
      {"20260901204555", &add_repair_deferred_at_to_stats/1},
      {"20260905140000", &add_user_id_created_at_index_to_points/1, transaction: false}
    ]
  end

  defp add_calculation_version_to_stats(repo) do
    unless column?(repo, "stats", "calculation_version") do
      sql!(repo, ~S"""
      ALTER TABLE "stats" ADD "calculation_version" integer DEFAULT 0 NOT NULL;
      """)
    end
  end

  defp add_stats_swept_at_to_users(repo) do
    unless column?(repo, "users", "stats_swept_at") do
      sql!(repo, ~S"""
      ALTER TABLE "users" ADD "stats_swept_at" timestamp(6);
      """)
    end
  end

  defp add_repair_deferred_at_to_stats(repo) do
    unless column?(repo, "stats", "repair_deferred_at") do
      sql!(repo, ~S"""
      ALTER TABLE "stats" ADD "repair_deferred_at" timestamp(6);
      """)
    end
  end

  defp add_user_id_created_at_index_to_points(repo) do
    sql!(repo, ~S"""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_points_on_user_id_and_created_at" ON "points" ("user_id", "created_at");
    """)
  end
end

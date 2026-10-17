defmodule Dawarich.Repo.Migrations.CreateStatsPointCounts do
  use Ecto.Migration

  def change do
    create table(:stats_point_counts, primary_key: false) do
      add :user_id, :bigint, primary_key: true
      add :geocoded, :bigint, null: false
      add :without_data, :bigint
      add :computed_at, :timestamptz, null: false
    end
  end
end

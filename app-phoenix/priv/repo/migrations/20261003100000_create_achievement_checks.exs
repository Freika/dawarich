defmodule Dawarich.Repo.Migrations.CreateAchievementChecks do
  use Ecto.Migration

  def change do
    create table(:achievement_checks, primary_key: false) do
      add :user_id, :bigint, primary_key: true
      add :oldest_timestamp, :bigint, null: false
      add :revision, :bigint, null: false
      add :expires_at, :timestamptz, null: false
    end

    create index(:achievement_checks, [:expires_at])

    execute "CREATE SEQUENCE phoenix.achievement_check_revisions",
            "DROP SEQUENCE phoenix.achievement_check_revisions"
  end
end

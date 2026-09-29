defmodule Dawarich.Repo.Migrations.CreateSupporterChecks do
  use Ecto.Migration

  def change do
    create table(:supporter_checks, primary_key: false) do
      add :cache_key, :text, primary_key: true
      add :result, :jsonb, null: false
      add :checked_at, :timestamptz, null: false
    end
  end
end

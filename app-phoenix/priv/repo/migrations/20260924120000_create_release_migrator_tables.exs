defmodule Dawarich.Repo.Migrations.CreateReleaseMigratorTables do
  use Ecto.Migration

  def change do
    create table(:release_migrator_leases, primary_key: false) do
      add :name, :string, primary_key: true
      add :holder, :string, null: false
      add :expires_at, :timestamptz, null: false
    end

    create table(:release_migration_jobs) do
      add :version, :string, null: false
      add :job_class, :string, null: false
      add :arguments, :jsonb, null: false
      add :wait_seconds, :integer, null: false, default: 0
      add :recorded_at, :timestamptz, null: false, default: fragment("now()")
    end
  end
end

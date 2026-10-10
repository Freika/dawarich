defmodule Dawarich.Repo.Migrations.CreateStatePrimitives do
  use Ecto.Migration

  def change do
    create table(:once_claims, primary_key: false) do
      add :key, :text, primary_key: true
      add :expires_at, :timestamptz, null: false
    end

    create index(:once_claims, [:expires_at])

    create table(:counters, primary_key: false) do
      add :key, :text, primary_key: true
      add :value, :bigint, null: false
      add :expires_at, :timestamptz, null: false
    end

    create index(:counters, [:expires_at])

    create table(:epochs, primary_key: false) do
      add :key, :text, primary_key: true
      add :token, :text, null: false
      add :updated_at, :timestamptz, null: false, default: fragment("now()")
    end

    create table(:leases, primary_key: false) do
      add :name, :text, primary_key: true
      add :holder, :text, null: false
      add :expires_at, :timestamptz, null: false
    end

    create index(:leases, [:expires_at])

    create table(:registration_setting, primary_key: false) do
      add :id, :boolean, primary_key: true, default: true
      add :enabled, :boolean, null: false
      add :updated_at, :timestamptz, null: false, default: fragment("now()")
    end

    create constraint(:registration_setting, :registration_setting_singleton, check: "id")
  end
end

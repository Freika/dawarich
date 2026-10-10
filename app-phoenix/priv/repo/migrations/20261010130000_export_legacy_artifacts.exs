defmodule Dawarich.Repo.Migrations.ExportLegacyArtifacts do
  use Ecto.Migration

  def change do
    create table(:export_legacy_artifacts, primary_key: false, prefix: "phoenix") do
      add :identity, :text, primary_key: true
      add :export_id, :bigint, null: false
      add :user_id, :bigint, null: false
      add :path, :text, null: false
    end

    create unique_index(:export_legacy_artifacts, [:export_id], prefix: "phoenix")
  end
end

defmodule Dawarich.ReleaseMigrations.V1_8_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.8.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260520111503", &add_first_name_and_last_name_to_users/1},
      {"20260531000000", &add_confidence_to_visits/1},
      {"20260602125716", &add_changelog_consent_to_users/1},
      {"20260604120000", &enqueue_orphaned_tracks_cleanup/1}
    ]
  end

  defp add_first_name_and_last_name_to_users(repo) do
    unless column?(repo, "users", "first_name") do
      sql!(repo, ~S|ALTER TABLE "users" ADD "first_name" character varying;|)
    end

    unless column?(repo, "users", "last_name") do
      sql!(repo, ~S|ALTER TABLE "users" ADD "last_name" character varying;|)
    end
  end

  defp add_confidence_to_visits(repo) do
    unless column?(repo, "visits", "confidence") do
      sql!(repo, ~S|ALTER TABLE "visits" ADD "confidence" smallint;|)
    end

    unless column?(repo, "visits", "confidence_breakdown") do
      sql!(repo, ~S|ALTER TABLE "visits" ADD "confidence_breakdown" jsonb DEFAULT '{}' NOT NULL;|)
    end
  end

  defp add_changelog_consent_to_users(repo) do
    unless column?(repo, "users", "changelog_consent") do
      sql!(repo, ~S|ALTER TABLE "users" ADD "changelog_consent" integer;|)
    end
  end

  defp enqueue_orphaned_tracks_cleanup(_repo),
    do: {:jobs, [job("DataMigrations::DestroyOrphanedTracksJob")]}
end

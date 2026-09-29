defmodule Dawarich.ReleaseMigrations.V1_7_1 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.7.1"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260421200001", &add_partial_unique_index_on_users_provider_uid/1, transaction: false},
      {"20260428200000", &drop_redundant_users_provider_uid_index/1, transaction: false}
    ]
  end

  defp add_partial_unique_index_on_users_provider_uid(repo) do
    unless index_name?(repo, "users", "index_users_on_provider_and_uid_present") do
      sql!(
        repo,
        ~S|CREATE UNIQUE INDEX CONCURRENTLY "index_users_on_provider_and_uid_present" ON "users" ("provider", "uid") WHERE provider IS NOT NULL AND uid IS NOT NULL;|
      )
    end
  end

  defp drop_redundant_users_provider_uid_index(repo) do
    if index_name?(repo, "users", "index_users_on_provider_and_uid") do
      sql!(repo, ~S|DROP INDEX CONCURRENTLY "index_users_on_provider_and_uid";|)
    end
  end
end

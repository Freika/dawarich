defmodule Dawarich.ReleaseMigrations.V1_3_1 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.3.1"

  @impl true
  def data_versions, do: []

  @impl true
  def steps, do: [{"20260108192905", &add_deleted_at_to_users/1, transaction: false}]

  defp add_deleted_at_to_users(repo) do
    unless column?(repo, "users", "deleted_at") do
      sql!(repo, ~S|ALTER TABLE "users" ADD "deleted_at" timestamp(6);|)
    end

    unless index?(repo, "users", columns: ["deleted_at"]) do
      sql!(
        repo,
        ~S|CREATE INDEX CONCURRENTLY "index_users_on_deleted_at" ON "users" ("deleted_at");|
      )
    end
  end
end

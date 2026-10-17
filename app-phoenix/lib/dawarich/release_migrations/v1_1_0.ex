defmodule Dawarich.ReleaseMigrations.V1_1_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @initial_delay_seconds 2 * 60
  @user_delay_seconds 30

  @impl true
  def release, do: "1.1.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260201000001", &add_processing_started_at_to_exports_and_imports/1},
      {"20260201000002", &add_error_message_to_exports/1},
      {"20260206202634", &deduplicate_tracks/1, transaction: false}
    ]
  end

  defp add_processing_started_at_to_exports_and_imports(repo) do
    sql!(repo, ~S"""
    ALTER TABLE "exports" ADD "processing_started_at" timestamp(6);
    ALTER TABLE "imports" ADD "processing_started_at" timestamp(6);
    """)
  end

  defp add_error_message_to_exports(repo) do
    sql!(repo, ~S|ALTER TABLE "exports" ADD "error_message" text;|)
  end

  defp deduplicate_tracks(repo) do
    jobs =
      rescue_sql(
        repo,
        fn ->
          repo.query!("SELECT id FROM users WHERE deleted_at IS NULL", [], log: false).rows
          |> Enum.with_index(fn [user_id], index ->
            job(
              "Tracks::DeduplicationJob",
              [user_id],
              @initial_delay_seconds + index * @user_delay_seconds
            )
          end)
        end,
        :any,
        fn _error -> [] end
      )

    {:jobs, jobs}
  end
end

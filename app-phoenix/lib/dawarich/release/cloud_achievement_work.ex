defmodule Dawarich.Release.CloudAchievementWork do
  @moduledoc false
  alias Dawarich.Achievements.BulkCheck
  alias Dawarich.Jobs.Processed

  def complete?(repo, event) do
    if Processed.done?(repo, event) do
      root = event |> BulkCheck.release_job_id() |> BulkCheck.job_id()
      prefix = "achievements.bulk_check:#{root}:"

      published =
        repo.query!(
          "SELECT 1 FROM phoenix.processed_commands WHERE event_id=$1 AND handler='achievements.bulk_check.completed'",
          [Ecto.UUID.dump!(root)],
          log: false
        ).num_rows == 1

      published and
        repo.query!(
          "SELECT handler FROM phoenix.processed_commands WHERE starts_with(handler,$1)",
          [prefix],
          log: false
        ).rows
        |> Enum.all?(fn [handler] ->
          user = handler |> String.replace_prefix(prefix, "") |> String.to_integer()
          Processed.done?(repo, BulkCheck.child_id(root, user))
        end)
    else
      repo.query!("SELECT 1 FROM countries LIMIT 1", [], log: false).num_rows == 0
    end
  end
end

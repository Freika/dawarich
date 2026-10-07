defmodule Dawarich.Points.PositionEffects do
  @moduledoc false
  alias Dawarich.RailsCommands

  def call(repo, user, point, response) do
    safe("publish", fn ->
      Dawarich.RailsEffects.tile_epoch(repo, user.id, [point.timestamp])
    end)

    safe("publish", fn -> Dawarich.MapEdits.Publisher.call(repo, user.id, response) end)

    safe("stats", fn ->
      local =
        Dawarich.UserTimeZone.local(
          Dawarich.UserSettings.get(user),
          DateTime.from_unix!(point.timestamp) |> DateTime.to_naive()
        )

      if Dawarich.Standalone.enabled?() or
           Dawarich.Jobs.Ownership.lock(repo, "command:stats.calculate_month") == :oban do
        Dawarich.Stats.Schedule.calculate(
          repo,
          user.id,
          local.local.year,
          local.local.month,
          true
        )
      else
        RailsCommands.insert!(repo, "stats.calculate_month", %{
          "user_id" => user.id,
          "year" => local.local.year,
          "month" => local.local.month
        })
      end
    end)

    safe("achievements", fn ->
      Dawarich.Points.NativeEffects.achievements(repo, %{
        "user_id" => user.id,
        "oldest_timestamp" => point.timestamp
      })
    end)
  end

  defp safe(operation, fun) do
    fun.()
  rescue
    _ -> Dawarich.Metrics.Map.post_commit_failure(operation)
  end
end

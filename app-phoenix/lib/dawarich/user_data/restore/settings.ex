defmodule Dawarich.UserData.Restore.Settings do
  @moduledoc false
  alias Dawarich.Imports.Fence

  def call(repo, user, data, context) when is_map(data) do
    Fence.run(context, fn ->
      {:ok, true} =
        repo.transaction(fn ->
          [[current]] =
            repo.query!("SELECT settings FROM users WHERE id=$1 FOR UPDATE", [user], log: false).rows

          current = current || %{}
          settings = Map.merge(current, data)

          repo.query!(
            "UPDATE users SET settings=$2,updated_at=$3 WHERE id=$1",
            [user, settings, context.now],
            log: false
          )

          if current["timezone"] != settings["timezone"], do: rebuild(repo, user, context)
          true
        end)

      true
    end)
  end

  def call(_repo, _user, _data, _context), do: false

  defp rebuild(repo, user, context) do
    months =
      repo.query!("SELECT year,month FROM stats WHERE user_id=$1 ORDER BY id", [user], log: false).rows

    if months != [] do
      repo.query!(
        "UPDATE stats SET calculation_version=0,repair_deferred_at=$2 WHERE user_id=$1",
        [user, context.now],
        log: false
      )

      for [year, month] <- months do
        opts = Map.get(context, :stats_opts, [])
        delay = Map.get(context, :stats_jitter, fn -> :rand.uniform(3301) - 1 end).()

        Dawarich.Stats.Schedule.calculate(
          repo,
          user,
          year,
          month,
          false,
          Keyword.put(opts, :schedule_in, delay)
        )
      end
    end
  end
end

defmodule Dawarich.Points.DependentCaches do
  @moduledoc false

  alias Dawarich.Redis

  def invalidate(user, year, repo \\ Dawarich.Jobs.repo()) do
    repo.query!("DELETE FROM phoenix.stats_point_counts WHERE user_id=$1", [user], log: false)

    keys =
      for suffix <- ~w(countries_visited cities_visited points_geocoded_stats total_distance),
          do: "dawarich/user_#{user}_#{suffix}"

    keys = keys ++ Enum.map(keys, &("phoenix/" <> &1))
    {:ok, _} = Redis.cache_command(["UNLINK" | keys])
    pattern = "insights/yearly_digest/#{user}/#{year}/*"
    scan("0", pattern)
    scan("0", "phoenix/" <> pattern)
    :ok
  end

  defp scan(cursor, pattern) do
    {:ok, [next, keys]} = Redis.cache_command(["SCAN", cursor, "MATCH", pattern, "COUNT", "100"])

    if keys != [] do
      {:ok, _} = Redis.cache_command(["UNLINK" | keys])
    end

    if next != "0", do: scan(next, pattern)
  end
end

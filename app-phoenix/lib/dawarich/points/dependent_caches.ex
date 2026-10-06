defmodule Dawarich.Points.DependentCaches do
  @moduledoc false

  alias Dawarich.Redis

  def invalidate(user, year) do
    keys =
      for suffix <- ~w(countries_visited cities_visited points_geocoded_stats total_distance),
          do: "dawarich/user_#{user}_#{suffix}"

    {:ok, _} = Redis.cache_command(["UNLINK" | keys])
    pattern = "insights/yearly_digest/#{user}/#{year}/*"
    scan("0", pattern)
    :ok
  end

  defp scan(cursor, pattern) do
    {:ok, [next, keys]} = Redis.cache_command(["SCAN", cursor, "MATCH", pattern, "COUNT", "100"])
    if keys != [], do: Redis.cache_command(["UNLINK" | keys])
    if next != "0", do: scan(next, pattern)
  end
end

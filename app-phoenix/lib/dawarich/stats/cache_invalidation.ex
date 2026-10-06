defmodule Dawarich.Stats.CacheInvalidation do
  @moduledoc false
  alias Dawarich.{Jobs.Ownership, RailsCommands, Redis, Standalone}

  def call(repo, payload, key \\ "command:stats.calculate_month") do
    if Standalone.enabled?() or Ownership.lock(repo, key) == :oban do
      invalidate(payload)
    else
      RailsCommands.insert!(repo, "stats.caches_invalidated", payload)
    end
  end

  defp invalidate(%{"user_id" => user, "year" => year, "scope" => scope}) do
    suffixes = ~w(countries_visited cities_visited)

    suffixes =
      if scope == "all", do: suffixes ++ ~w(points_geocoded_stats total_distance), else: suffixes

    keys = Enum.map(suffixes, &"dawarich/user_#{user}_#{&1}")
    {:ok, _} = Redis.cache_command(["DEL" | keys])

    pattern =
      if year,
        do: "insights/yearly_digest/#{user}/#{year}/*",
        else: "insights/yearly_digest/#{user}/*"

    scan("0", pattern)
    :ok
  end

  defp scan(cursor, pattern) do
    {:ok, [next, keys]} = Redis.cache_command(["SCAN", cursor, "MATCH", pattern, "COUNT", "1000"])
    if keys != [], do: delete(keys)
    if next != "0", do: scan(next, pattern)
  end

  defp delete(keys) do
    for batch <- Enum.chunk_every(keys, 1000) do
      {:ok, _} = Redis.cache_command(["DEL" | batch])
    end
  end
end

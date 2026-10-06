defmodule Dawarich.Ingest.Closure do
  @moduledoc false
  def points_limit?(user) do
    key = "points_limit_exceeded/#{user.id}"

    case Dawarich.RailsCache.get(key) do
      {:ok, value} ->
        value not in [false, nil]

      _ ->
        value = (user.points_count || 0) >= 10_000_000

        bytes =
          Dawarich.RailsCache.Wire.encode_boolean(value,
            expires_at: System.os_time(:second) + 86400
          )

        Dawarich.Redis.cache_command(["SET", key, bytes, "EX", "86400"])
        value
    end
  end

end

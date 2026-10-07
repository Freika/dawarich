defmodule Dawarich.RailsCache do
  @moduledoc "Reads Rails' RedisCacheStore entries and writes fragment HTML entries Rails reads."
  alias Dawarich.RailsCache.Wire
  alias Dawarich.Redis

  def get(key, opts \\ []) do
    physical = Dawarich.Visits.CacheGeneration.physical_key(key, Dawarich.Jobs.repo())

    result =
      case Redis.cache_command(["GET", physical]) do
        {:ok, nil} -> :miss
        {:ok, bytes} -> entry(physical, bytes, opts)
        error -> error
      end

    if physical == Dawarich.Visits.CacheGeneration.physical_key(key, Dawarich.Jobs.repo()),
      do: result,
      else: :miss
  end

  def put(key, html, expires_in: seconds) do
    key = Dawarich.Visits.CacheGeneration.physical_key(key, Dawarich.Jobs.repo())
    bytes = Wire.encode(html, expires_at: now() + seconds)
    Redis.cache_command(["SET", key, bytes, "PX", to_string(seconds * 1000)])
  end

  defp entry(key, bytes, opts) do
    case Wire.decode(bytes, opts) do
      {:ok, %{expires_at: expires, value: value}} ->
        if expires && expires <= now() do
          Redis.cache_command(["UNLINK", key])
          :miss
        else
          {:ok, value}
        end

      {:error, _} ->
        :miss
    end
  end

  defp now, do: System.system_time(:microsecond) / 1_000_000
end

defmodule Dawarich.RailsCache do
  @moduledoc "Reads Rails' RedisCacheStore entries and writes fragment HTML entries Rails reads."
  alias Dawarich.RailsCache.Wire
  alias Dawarich.Redis

  def get(key, opts \\ []) do
    physical = if opts[:resolved], do: key, else: visible_key(key, opts)

    result =
      case Redis.cache_command(["GET", physical]) do
        {:ok, nil} -> :miss
        {:ok, bytes} -> entry(physical, bytes, opts)
        error -> error
      end

    if opts[:resolved] == true or physical == visible_key(key, opts), do: result, else: :miss
  end

  def put(key, html, opts) do
    seconds = Keyword.fetch!(opts, :expires_in)
    key = if opts[:resolved], do: key, else: visible_key(key, opts)

    bytes = Wire.encode(html, expires_at: now() + seconds)
    Redis.cache_command(["SET", key, bytes, "PX", to_string(seconds * 1000)])
  end

  defp visible_key(key, opts) do
    repo = Keyword.get(opts, :repo, Dawarich.Jobs.repo())
    key = Dawarich.Visits.CacheGeneration.physical_key(key, repo)

    if Dawarich.AfterCommit.Visibility.user_key?(key),
      do: Dawarich.AfterCommit.Visibility.key(repo, key),
      else: key
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

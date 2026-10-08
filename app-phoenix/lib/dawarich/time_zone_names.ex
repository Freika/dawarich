defmodule Dawarich.TimeZoneNames do
  @moduledoc """
  PostgreSQL's accepted timezone names, cached per dynamic repository for one hour.

  Only the database catalogue is cached, never user settings or environment values.
  Call `invalidate/1` after changing the database timezone catalogue to refresh early.
  """

  alias Dawarich.TtlCache

  @ttl_ms :timer.hours(1)

  def member?(repo, name), do: MapSet.member?(names(repo), name)

  def invalidate(repo) do
    if function_exported?(repo, :get_dynamic_repo, 0), do: TtlCache.delete(key(repo)), else: :ok
  end

  defp names(repo) do
    if :ets.whereis(TtlCache) == :undefined or not function_exported?(repo, :get_dynamic_repo, 0),
      do: catalogue(repo),
      else: cached_names(repo)
  end

  defp cached_names(repo) do
    key = key(repo)

    case TtlCache.lookup(key) do
      {:ok, names} -> names
      :error -> load(repo, key)
    end
  end

  defp load(repo, key) do
    # Serialize cold loads on this node; the query runs in the caller's repo context.
    :global.trans(
      {{__MODULE__, key}, self()},
      fn ->
        case TtlCache.lookup(key) do
          {:ok, names} ->
            names

          :error ->
            TtlCache.put(key, catalogue(repo), @ttl_ms)
        end
      end,
      [node()]
    )
  end

  defp catalogue(repo) do
    result =
      if function_exported?(repo, :query!, 3),
        do: repo.query!("SELECT name FROM pg_timezone_names", [], log: false),
        else: repo.query!("SELECT name FROM pg_timezone_names", [])

    result.rows
    |> Enum.map(fn [name] -> name end)
    |> MapSet.new()
  end

  defp key(repo) do
    dynamic = repo.get_dynamic_repo()
    process = if is_atom(dynamic), do: Process.whereis(dynamic), else: dynamic
    {__MODULE__, repo, dynamic, process}
  end
end

defmodule Dawarich.Readiness do
  @moduledoc false
  require Logger

  def check(opts \\ []) do
    database =
      Keyword.get(opts, :database, fn -> Dawarich.Repo.query("SELECT 1", [], log: false) end)

    release = Keyword.get(opts, :release, &Dawarich.Release.readiness/1)
    redis = Keyword.get(opts, :redis, fn -> Dawarich.Redis.command(["PING"]) end)

    with :ready <- lifecycle(release, opts),
         :ready <- dependency(database, :database),
         :ready <- dependency(redis, :redis),
         do: :ready
  end

  defp lifecycle(release, opts) do
    if release.(opts) == :ready, do: :ready, else: {:unavailable, :lifecycle}
  end

  defp dependency(call, kind) do
    case call.() do
      {:ok, %{rows: [[1]]}} when kind == :database -> :ready
      {:ok, "PONG"} when kind == :redis -> :ready
      _ -> {:unavailable, kind}
    end
  end
end

defmodule Dawarich.Readiness do
  @moduledoc false
  require Logger

  def check(opts \\ []) do
    database =
      Keyword.get(opts, :database, fn -> Dawarich.Repo.query("SELECT 1", [], log: false) end)

    release = Keyword.get(opts, :release, &Dawarich.Release.readiness/1)
    redis = Keyword.get(opts, :redis, fn -> Dawarich.Redis.command(["PING"]) end)

    with :ready <- configuration(opts),
         :ready <- lifecycle(release, opts),
         :ready <- dependency(database, :database),
         :ready <- dependency(redis, :redis),
         do: :ready
  end

  defp configuration(opts) do
    env = Keyword.get_lazy(opts, :env, &System.get_env/0)

    case Dawarich.Cloud.Configuration.check(env) do
      :ok ->
        :ready

      {:error, {:cloud_configuration, message}} ->
        Logger.warning(message)
        {:unavailable, :cloud_configuration}
    end
  end

  defp lifecycle(release, opts) do
    guarded(
      fn -> if release.(opts) == :ready, do: :ready, else: {:unavailable, :lifecycle} end,
      :lifecycle
    )
  end

  defp dependency(call, kind) do
    guarded(
      fn ->
        case call.() do
          {:ok, %{rows: [[1]]}} when kind == :database -> :ready
          {:ok, "PONG"} when kind == :redis -> :ready
          _ -> {:unavailable, kind}
        end
      end,
      kind
    )
  end

  defp guarded(call, kind) do
    call.()
  rescue
    error ->
      Logger.warning("Readiness check failed: #{inspect(error.__struct__)}")
      {:unavailable, kind}
  catch
    class, _ ->
      Logger.warning("Readiness check failed: #{class}")
      {:unavailable, kind}
  end
end

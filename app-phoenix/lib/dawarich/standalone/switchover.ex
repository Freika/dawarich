defmodule Dawarich.Standalone.Switchover do
  @moduledoc false

  @sql """
  SELECT
    (SELECT count(*) FROM phoenix.rails_commands)::bigint AS reverse_pending,
    (SELECT count(*) FROM phoenix.rails_commands_dead)::bigint AS reverse_dead,
    (SELECT count(*) FROM public.job_outbox WHERE state = 'pending')::bigint AS outbox_pending,
    (SELECT count(*) FROM public.job_outbox WHERE state = 'quarantined')::bigint AS quarantined
  """
  @sql_keys ~w(reverse_pending reverse_dead outbox_pending quarantined)a

  def check!(plan, opts \\ []) do
    env = Keyword.get(opts, :env, System.get_env())

    if Dawarich.Standalone.enabled?(env) and match?({:native, _}, plan) do
      case status(opts) do
        {:ok, _} -> :ok
        {:error, reason} -> raise message(reason)
      end
    else
      :ok
    end
  end

  def status(opts \\ []) do
    repo = Keyword.get(opts, :repo, Dawarich.Repo)
    config = Keyword.get(opts, :redis, Application.get_env(:dawarich, :redis, []))

    with {:ok, sql} <- sql_counts(repo),
         {:ok, redis} <- Dawarich.Standalone.SourceRedis.counts(config) do
      counts = Map.merge(sql, redis)

      if Enum.all?(counts, fn {_, count} -> count == 0 end),
        do: {:ok, counts},
        else: {:error, {:pending, counts}}
    end
  end

  defp sql_counts(repo) do
    if Process.whereis(repo) do
      {:ok, read_counts(repo)}
    else
      {:ok, result, _} = Ecto.Migrator.with_repo(repo, &read_counts/1)
      {:ok, result}
    end
  rescue
    _ -> {:error, :database_unreadable}
  catch
    _, _ -> {:error, :database_unreadable}
  end

  defp read_counts(repo) do
    %{rows: [values]} = repo.query!(@sql, [], log: false)
    Map.new(Enum.zip(@sql_keys, values))
  end

  defp message(reason) do
    "Standalone switch-over refused: #{describe(reason)}. " <>
      "Fence producers, drain with the retained Rails app, and stop its workers before retrying. " <>
      "See docs/phoenix/standalone-switchover.md. No retained work was changed."
  end

  defp describe({:pending, counts}) do
    counts
    |> Enum.filter(fn {_, count} -> count > 0 end)
    |> Enum.sort()
    |> Enum.map_join(", ", fn {key, count} -> "#{key}=#{count}" end)
  end

  defp describe(reason) when reason in [:database_unreadable, :redis_unreadable],
    do: Atom.to_string(reason)
end

defmodule Dawarich.Cache.Pages do
  @moduledoc false
  alias Dawarich.{Repo, Redis}
  alias Dawarich.Accounts.DataAccess
  alias Dawarich.Analytics.Period
  alias Dawarich.Cache.PagesCodec

  def fetch(subject, resource, params, read, opts \\ []) do
    with {:ok, scope, signature} <- admission(subject, resource, params, opts),
         :ok <- authorize(scope, opts) do
      key = "dawarich:native:data:v1:" <> signature

      case command(opts, ["GET", key]) do
        {:ok, bytes} when is_binary(bytes) ->
          case PagesCodec.decode(bytes) do
            {:ok, %{schema: 1, expires_at: expiry, value: value}} when is_integer(expiry) ->
              if expiry > now(opts),
                do: deliver(subject, resource, params, signature, {:ok, value}, opts),
                else: miss(subject, scope, resource, params, signature, key, read, opts)

            _ ->
              miss(subject, scope, resource, params, signature, key, read, opts)
          end

        _ ->
          miss(subject, scope, resource, params, signature, key, read, opts)
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp miss(subject, scope, resource, params, signature, key, read, opts) do
    result = read.(scope)

    with {:ok, _} = result <- deliver(subject, resource, params, signature, result, opts) do
      write = fn ->
        case admission(subject, resource, params, opts) do
          {:ok, fresh, ^signature} ->
            with :ok <- authorize(fresh, opts),
                 {:ok, value} <- result,
                 true <- cacheable?(value),
                 {:ok, bytes} <-
                   PagesCodec.encode(%{
                     schema: 1,
                     expires_at: now(opts) + ttl(resource),
                     value: value
                   }) do
              command(opts, ["SET", key, bytes, "EX", to_string(ttl(resource))])

              case admission(subject, resource, params, opts) do
                {:ok, _, ^signature} -> :ok
                _ -> command(opts, ["UNLINK", key])
              end
            end

          _ ->
            :ok
        end
      end

      after_commit(opts, write)
      result
    end
  end

  defp deliver(subject, resource, params, signature, result, opts) do
    with {:ok, scope, current} <- admission(subject, resource, params, opts),
         :ok <- authorize(scope, opts),
         true <- current == signature do
      result
    else
      false -> {:error, :stale}
      error -> error
    end
  end

  defp admission(subject, resource, params, opts) do
    with {:ok, scope} <- DataAccess.admit(subject, settings: true),
         {:ok, scope, period} <-
           Period.admit(
             scope,
             params,
             Keyword.get(opts, :period_kind, :insights),
             Keyword.put(opts, :now, DateTime.from_unix!(now(opts)))
           ) do
      revision = Dawarich.Stats.PageRefresh.revision(Repo, scope, resource, period)

      ready =
        Repo.query!(
          "SELECT (SELECT max(updated_at) FROM digests WHERE user_id=$1),(SELECT computed_at FROM phoenix.stats_point_counts WHERE user_id=$1)",
          [scope.user.id],
          log: false
        ).rows

      identity = Dawarich.NativeM5.Dependencies.principal(scope).identity

      fields =
        {1, scope.user.id, scope.locale, scope.user.plan, scope.user.status, identity, resource,
         Map.take(period, [:year, :month, :page, :zone, :unit, :cutoff, :restricted]),
         Keyword.get(opts, :audience, :private), revision, ready, Enum.sort(params)}

      signature =
        :crypto.hash(:sha256, :erlang.term_to_binary(fields)) |> Base.encode16(case: :lower)

      {:ok, scope, signature}
    end
  end

  defp authorize(scope, opts) do
    case Keyword.get(opts, :audience, :private) do
      :private ->
        :ok

      {:public, capability} when is_binary(capability) ->
        case opts[:authorize] do
          fun when is_function(fun, 2) ->
            case fun.(scope, now(opts)) do
              :ok -> :ok
              _ -> {:error, :unauthorized}
            end

          _ ->
            {:error, :unauthorized}
        end

      _ ->
        {:error, :unauthorized}
    end
  end

  defp after_commit(opts, write) do
    cond do
      is_function(opts[:after_commit], 1) -> opts[:after_commit].(write)
      Repo.in_transaction?() -> :ok
      true -> write.()
    end
  end

  defp cacheable?(%{state: state}) when state in [:pending, :failed], do: false
  defp cacheable?(%{points: %{state: state}}) when state in [:pending, :failed], do: false
  defp cacheable?(_), do: true

  defp command(opts, args), do: Keyword.get(opts, :command, &Redis.cache_command/1).(args)
  defp now(opts), do: Keyword.get(opts, :clock, fn -> System.system_time(:second) end).()
  defp ttl(resource) when resource in [:summary, :counts, :index], do: 86400
  defp ttl(_), do: 3600
end

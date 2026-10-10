defmodule Dawarich.Stats.PageRefresh do
  @moduledoc false
  alias Dawarich.{Repo, State}
  alias Dawarich.Accounts.DataAccess
  alias Dawarich.NativeM5.Dependencies
  alias Dawarich.Stats.{EffectIdentity, PageRefreshWorker}

  def request(subject, resource, params, opts \\ []) do
    with {:ok, scope} <- DataAccess.admit(subject, settings: true),
         {:ok, data} <- read(scope, resource, params, opts) do
      if data.state == :restricted or data.period.all_time or data.state == :ready do
        {:ok, %{state: data.state}}
      else
        with {:ok, args} <- specification(scope, resource, data.period) do
          if fun = opts[:before_claim], do: fun.()

          {:ok, result} =
            Dawarich.Transaction.run(Repo, fn ->
              key = key(args)

              if State.claim_persistent_all(Repo, [key]) != [] do
                Oban.insert!(PageRefreshWorker.new(args))
                State.put_cursor(Repo, key, "pending")
              end

              %{
                state: state(Repo, args),
                receipt: args["receipt"],
                revision: args["revision"],
                args: args
              }
            end)

          {:ok, result}
        end
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def retry(subject, resource, params, opts \\ []) do
    with {:ok, %{args: args} = data} <- request(subject, resource, params, opts) do
      {:ok, result} =
        Dawarich.Transaction.run(Repo, fn ->
          jobs =
            Repo.query!(
              "SELECT id FROM oban.oban_jobs WHERE worker=$1 AND args->>'receipt'=$2 AND args->>'user_id'=$3",
              ["Dawarich.Stats.PageRefreshWorker", args["receipt"], to_string(args["user_id"])],
              log: false
            ).rows

          for [id] <- jobs, do: Oban.retry_job(id)
          State.put_cursor(Repo, key(args), "pending")
          %{data | state: :pending}
        end)

      {:ok, result}
    else
      other -> other
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def specification(scope, resource, period, repo \\ Repo) do
    with true <- resource in [:insights, :counts],
         {:ok, scope} <- DataAccess.admit(scope, settings: true) do
      principal = Dependencies.principal(scope)
      revision = revision(repo, scope, resource, period)

      args = %{
        "user_id" => scope.user.id,
        "resource" => to_string(resource),
        "year" => period.year,
        "month" => period.month,
        "zone" => period.zone,
        "unit" => period.unit,
        "revision" => revision,
        "identity" => Base.encode16(principal.identity),
        "version" => 1
      }

      receipt = EffectIdentity.id(revision, "native-page-refresh:" <> args["resource"], args)
      {:ok, Map.put(args, "receipt", receipt)}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def revision(repo, scope, resource, period) do
    rows =
      repo.query!(
        "SELECT count(*),max(updated_at),COALESCE(sum(distance),0) FROM stats WHERE user_id=$1",
        [scope.user.id],
        log: false
      ).rows

    epoch = Dawarich.AfterCommit.Visibility.generation(repo, scope.user.id)

    :crypto.hash(
      :sha256,
      :erlang.term_to_binary(
        {1, scope.user.id, resource, period.year, period.month, period.zone, period.unit,
         scope.user.settings, rows, epoch,
         div(DateTime.to_unix(period.now), if(resource == :counts, do: 86400, else: 3600))}
      )
    )
    |> Base.encode16(case: :lower)
  end

  def state(repo, args) do
    case State.cursor(repo, key(args)) do
      "ready" -> :ready
      "failed" -> :failed
      _ -> :pending
    end
  end

  def key(args),
    do: "native-page-refresh:#{args["user_id"]}:#{args["resource"]}:#{args["receipt"]}"

  def published_key(id, resource, period),
    do: "native-page-published:#{id}:#{resource}:#{period.year}:#{period.month}"

  def stale?(id, period) do
    case State.cursor(Repo, published_key(id, :insights, period)) do
      nil ->
        false

      published ->
        case Dawarich.Accounts.get(id) do
          nil ->
            true

          user ->
            published !=
              revision(Repo, Dawarich.Accounts.Scope.for_user(user, "en"), :insights, period)
        end
    end
  end

  def topic(id), do: "native-analytics:#{id}"

  defp read(scope, :insights, params, opts) do
    with {:ok, data} <- Dawarich.Insights.Pages.details(scope, params, opts),
         do: {:ok, %{data | period: %{data.period | month: data.selected_month}}}
  end

  defp read(scope, :counts, params, opts) do
    with {:ok, data} <- Dawarich.Stats.Pages.index(scope, params, opts),
         do: {:ok, Map.merge(data.points, %{period: data.period})}
  end

  defp read(_, _, _, _), do: {:error, :invalid_input}
end

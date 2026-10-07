defmodule Dawarich.AfterCommit.Worker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 20

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, args) do
    if repo.in_transaction?(),
      do: raise(ArgumentError, "after-commit effect requires a committed intent")

    intent = args["intent_id"]

    repo.checkout(fn ->
      repo.query!("SELECT pg_advisory_lock(hashtextextended($1,0))", [intent], log: false)

      try do
        if not Dawarich.Jobs.Processed.done?(repo, intent) do
          :ok = execute(repo, args["operation"], args["payload"], intent)
          Dawarich.Jobs.Processed.mark!(repo, intent, "after_commit")
        end

        :ok
      after
        repo.query!("SELECT pg_advisory_unlock(hashtextextended($1,0))", [intent], log: false)
      end
    end)
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  defp execute(repo, "stats", payload, _intent),
    do: Dawarich.Stats.CacheInvalidation.invalidate(repo, payload)

  defp execute(_repo, "keys", %{"keys" => keys}, _intent) do
    if keys != [] do
      {:ok, _} = Dawarich.Redis.cache_command(["UNLINK" | keys])
    end

    :ok
  end

  defp execute(repo, "tracks", payload, intent),
    do: Dawarich.Tracks.NativeChanges.deliver(repo, payload, intent)

  defp execute(repo, "visit_months", payload, _intent),
    do: Dawarich.Points.VisitMonthsWorker.run(repo, payload)

  defp execute(repo, "transport_start", payload, intent),
    do: Dawarich.Transportation.AfterCommit.start(repo, payload, intent)

  defp execute(repo, "transport_progress", payload, intent),
    do: Dawarich.Transportation.AfterCommit.progress(repo, payload, intent)

  defp execute(repo, "subscription", %{"user_id" => user}, _intent) do
    case repo.query!("SELECT api_key FROM users WHERE id=$1", [user], log: false).rows do
      [[key]] ->
        {:ok, _} = Dawarich.Subscriptions.Cache.invalidate(key, %{})
        :ok

      [] ->
        :ok
    end
  end

  defp execute(_repo, "rate_limit", %{"key_hash" => hash}, _intent),
    do: Dawarich.TtlCache.delete_digest(DawarichWeb.RateLimit, hash)
end

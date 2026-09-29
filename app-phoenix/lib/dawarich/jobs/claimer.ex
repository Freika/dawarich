defmodule Dawarich.Jobs.Claimer do
  @moduledoc false
  use Task, restart: :transient
  require Logger

  alias Dawarich.Jobs.Registry

  def start_link(opts \\ []), do: Task.start_link(__MODULE__, :run, [opts])

  def run(opts) do
    context = %{
      repo: Keyword.get(opts, :repo),
      oban: Keyword.get(opts, :oban, Oban),
      entries: Keyword.get_lazy(opts, :entries, &Registry.claimable/0),
      ready?: Keyword.get(opts, :ready?, fn -> Dawarich.Release.readiness() == :ready end),
      backoff_ms: Keyword.get(opts, :backoff_ms, 30_000),
      max_backoff_ms: Keyword.get(opts, :max_backoff_ms, 300_000),
      lock_timeout: Keyword.get(opts, :lock_timeout, "2s"),
      sleep: Keyword.get(opts, :sleep, &Process.sleep/1)
    }

    loop(context, context.backoff_ms)
  end

  def next_delay(delay, max), do: min(delay * 2, max)

  defp loop(%{entries: []}, _delay), do: :ok

  defp loop(context, delay) do
    case attempt(context) do
      :done ->
        :ok

      :not_ready ->
        context.sleep.(context.backoff_ms)
        loop(context, delay)

      :failed ->
        context.sleep.(delay)
        loop(context, next_delay(delay, context.max_backoff_ms))
    end
  end

  defp attempt(context) do
    if context.ready?.() do
      repo = context.repo || Oban.config(context.oban).repo
      outcomes = claim_all(repo, context.oban, context.entries, context.lock_timeout)

      for {key, {:error, reason}} <- outcomes,
          do: Logger.warning("[jobs.claimer] #{key} not claimed: #{inspect(reason)}")

      if Enum.all?(outcomes, fn {_key, outcome} -> outcome in [:claimed, :already, :pinned] end),
        do: :done,
        else: :failed
    else
      :not_ready
    end
  rescue
    exception -> failed(inspect(exception.__struct__))
  catch
    kind, _reason -> failed(inspect(kind))
  end

  defp failed(class) do
    Logger.warning("[jobs.claimer] attempt failed (#{class})")
    :failed
  end

  def claim_all(repo, oban, entries, lock_timeout \\ "2s"),
    do: Enum.map(entries, &{&1.key, claim(repo, oban, &1, lock_timeout)})

  def claim(repo, oban, entry, lock_timeout \\ "2s") do
    {:ok, _} =
      repo.transaction(fn ->
        set_lock_timeout(repo, lock_timeout)

        repo.query!(
          "INSERT INTO phoenix.job_owners (key) VALUES ($1) ON CONFLICT (key) DO NOTHING",
          [entry.key],
          log: false
        )
      end)

    with {:ok, outcome} <- repo.transaction(fn -> flip(repo, oban, entry, lock_timeout) end) do
      if outcome == :claimed, do: Logger.info("[jobs.claimer] #{entry.key} now runs on Oban")
      outcome
    end
  rescue
    error in Postgrex.Error -> {:error, get_in(error.postgres, [:code]) || :postgrex}
    DBConnection.ConnectionError -> {:error, :no_connection}
  end

  defp set_lock_timeout(repo, lock_timeout),
    do: repo.query!("SET LOCAL lock_timeout = '#{lock_timeout}'", [], log: false)

  defp flip(repo, oban, entry, lock_timeout) do
    set_lock_timeout(repo, lock_timeout)

    case repo.query!(
           "SELECT owner, pinned FROM phoenix.job_owners WHERE key = $1 FOR UPDATE",
           [entry.key],
           log: false
         ).rows do
      [[_owner, true]] ->
        :pinned

      [["oban", false]] ->
        :already

      [["sidekiq", false]] ->
        repo.query!(
          "UPDATE phoenix.job_owners SET owner = 'oban', updated_at = $2, updated_by = $3 WHERE key = $1",
          [entry.key, DateTime.utc_now(), "claimer:" <> Oban.config(oban).node],
          log: false
        )

        catch_up(repo, oban, entry)
        :claimed

      unexpected ->
        repo.rollback({:unexpected_owner_row, unexpected})
    end
  end

  defp catch_up(_repo, _oban, %{kind: :command}), do: :ok
  defp catch_up(_repo, _oban, %{kind: :cron, catch_up: false}), do: :ok

  defp catch_up(repo, oban, %{kind: :cron, worker: worker}) do
    case Oban.insert(oban, worker.new(%{}), retry: false) do
      {:ok, _job} -> :ok
      _error -> repo.rollback(:catch_up_insert)
    end
  end
end

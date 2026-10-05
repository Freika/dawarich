defmodule Dawarich.Jobs.Claimer do
  @moduledoc false
  use Task, restart: :transient
  require Logger

  alias Dawarich.Jobs.{Ownership, Registry}

  @legacy_schedulers %{
    "cron:trek_sync_job" => "Dawarich.Imports.Trek.ScheduleWorker",
    "cron:teslamate_sync_job" => "Dawarich.Imports.Teslamate.ScheduleWorker"
  }

  def legacy_scheduler_counts(repo) do
    for {key, worker} <- Enum.sort(@legacy_schedulers),
        do: %{key: key, worker: worker, incomplete: legacy_scheduler_count(repo, key)}
  end

  def legacy_scheduler_count(repo, key) do
    case @legacy_schedulers[key] do
      nil ->
        0

      worker ->
        [[count]] =
          repo.query!(
            "SELECT count(*) FROM oban.oban_jobs WHERE worker = $1 AND state NOT IN ('completed', 'cancelled')",
            [worker],
            log: false
          ).rows

        count
    end
  end

  def entries(value) when value in [nil, ""], do: []

  def entries(value) when is_binary(value) do
    if String.trim(value) == "" do
      []
    else
      keys = value |> String.split(",") |> Enum.map(&String.trim/1)
      registry = Map.new(Registry.entries(), &{&1.key, &1})

      if length(keys) != length(Enum.uniq(keys)) or
           Enum.any?(keys, &(not Map.has_key?(registry, &1))),
         do: raise(ArgumentError, "DAWARICH_OBAN_JOB_KEYS requires unique known job keys")

      Enum.map(keys, &Map.fetch!(registry, &1))
    end
  end

  def start_link(opts \\ []), do: Task.start_link(__MODULE__, :run, [opts])

  def run(opts) do
    context = %{
      repo: Keyword.get(opts, :repo),
      oban: Keyword.get(opts, :oban, Oban),
      entries: Keyword.get(opts, :entries, Application.get_env(:dawarich, :job_entries, [])),
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

        Ownership.ensure_rows!(repo, Ownership.joint_keys(entry.key))
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

    keys = Ownership.joint_keys(entry.key)

    owners =
      repo.query!(
        "SELECT owner, pinned FROM phoenix.job_owners WHERE key = ANY($1) ORDER BY key FOR UPDATE",
        [keys],
        log: false
      ).rows

    cond do
      Enum.any?(owners, fn [_, pinned] -> pinned end) ->
        :pinned

      Enum.all?(owners, &(&1 == ["oban", false])) ->
        :already

      length(owners) == length(keys) ->
        count = Enum.sum(Enum.map(keys, &legacy_scheduler_count(repo, &1)))
        if count > 0, do: repo.rollback({:legacy_scheduler_jobs, count})

        repo.query!(
          "UPDATE phoenix.job_owners SET owner = 'oban', updated_at = $2, updated_by = $3 WHERE key = ANY($1)",
          [keys, DateTime.utc_now(), "claimer:" <> Oban.config(oban).node],
          log: false
        )

        for key <- keys do
          selected =
            if key == entry.key, do: entry, else: Enum.find(Registry.entries(), &(&1.key == key))

          catch_up(repo, oban, selected)
        end

        :claimed

      true ->
        repo.rollback({:unexpected_owner_row, owners})
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

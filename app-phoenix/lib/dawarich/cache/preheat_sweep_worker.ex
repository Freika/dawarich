defmodule Dawarich.Cache.PreheatSweepWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

  alias Dawarich.Cache.Schedule
  alias Dawarich.Jobs.Ownership

  @key "cron:cache_preheating_job"
  def key, do: @key

  @impl Oban.Worker
  def perform(%Oban.Job{id: id, args: args, scheduled_at: at}) do
    source = args["source_job_id"] || uuid("cache-sweep/#{id}/#{at}")

    opts = [
      accepted: true,
      source_job_id: source,
      time_zone: args["time_zone"] || System.get_env("TIME_ZONE", "Europe/Berlin")
    ]

    opts = if at, do: Keyword.put(opts, :clock, DateTime.to_unix(at)), else: opts
    run(Dawarich.Jobs.repo(), opts)
  end

  def run(repo, opts \\ []) do
    if hook = opts[:before_delegate], do: hook.()
    source = Keyword.get_lazy(opts, :source_job_id, &Ecto.UUID.generate/0)

    at =
      Keyword.get_lazy(opts, :clock, fn -> System.os_time(:second) end) +
        Keyword.get(opts, :schedule_in, 0)

    opts = opts |> Keyword.put(:clock, at) |> Keyword.put(:schedule_in, 0)
    effect = fn -> sweep(repo, source, opts) end

    result =
      if opts[:accepted],
        do: repo.transaction(effect) |> accepted_result(),
        else: Ownership.with_owner(repo, @key, :oban, effect)

    case result do
      {:ok, :ok} ->
        if hook = opts[:after_delegate], do: hook.()
        :ok

      {:skip, _owner} ->
        {:cancel, :not_owner}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  defp accepted_result({:ok, :ok}), do: {:ok, :ok}
  defp accepted_result(error), do: error

  defp sweep(repo, source, opts) do
    env = Keyword.get(opts, :env, System.get_env())
    filter = if env["SELF_HOSTED"] == "false", do: " AND status IN (1,2)", else: ""
    batch(repo, source, opts, filter, 0)
  end

  defp batch(repo, source, opts, filter, cursor) do
    users =
      repo.query!(
        "SELECT id FROM users WHERE deleted_at IS NULL AND id>$1" <>
          filter <> " ORDER BY id LIMIT 500",
        [cursor]
      ).rows

    for [id] <- users do
      Schedule.preheat_user(repo, id, Keyword.put(opts, :source_job_id, uuid("#{source}/#{id}")))
    end

    if users == [], do: :ok, else: batch(repo, source, opts, filter, hd(List.last(users)))
  end

  defp uuid(value), do: value |> then(&:crypto.hash(:md5, &1)) |> Ecto.UUID.load!()
end

defmodule Dawarich.RawData.ClearWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :maintenance,
    priority: 3,
    max_attempts: 3,
    unique: [keys: [:user_id], states: [:available, :scheduled], period: :infinity]

  require Logger

  alias Dawarich.RawData.UserSweep
  alias Dawarich.ReleaseOperations
  alias Dawarich.State.Lease

  @key "cron:raw_data_clear_job"
  @clear """
  UPDATE points SET raw_data = '{}'::jsonb
  WHERE raw_data_archived = true AND raw_data <> '{}'::jsonb
    AND raw_data_archive_id IN (
      SELECT a.id FROM points_raw_data_archives a
      WHERE a.user_id = $1 AND a.verified_at <= now() - interval '7 days'
    )
    AND id IN (
    SELECT p.id FROM points p
    WHERE p.user_id = $1 AND p.raw_data_archived = true AND p.raw_data <> '{}'::jsonb
      AND p.id > $3
      AND p.raw_data_archive_id IN (
        SELECT a.id FROM points_raw_data_archives a
        WHERE a.user_id = $1 AND a.verified_at <= now() - interval '7 days'
      )
    ORDER BY p.id
    LIMIT $2
  )
  RETURNING id
  """

  def key, do: @key

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}), do: run(Dawarich.Jobs.repo(), conf.name, args)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(20)

  def run(repo, oban, args, opts \\ [])

  def run(repo, _oban, %{"user_id" => user_id}, opts) when is_integer(user_id) do
    if ReleaseOperations.user?(repo, user_id) do
      Lease.with_lease(
        repo,
        "clear_raw_data:#{user_id}",
        fn ->
          cleared = clear(repo, user_id, opts, 0)

          if cleared > 0,
            do: Logger.info("Cleared raw_data for #{cleared} points (user #{user_id})")
        end,
        timeout_ms: 0
      )
    end

    :ok
  end

  def run(repo, oban, args, opts) when args == %{},
    do: UserSweep.run(repo, oban, @key, &new(%{"user_id" => &1}), opts)

  def run(_repo, _oban, _args, _opts), do: {:cancel, :invalid_args}

  defp clear(repo, user_id, opts, total, after_id \\ 0) do
    params = [user_id, Keyword.get(opts, :batch_size, 5_000), after_id]

    case repo.query!(@clear, params, log: false).rows do
      [] ->
        total

      cleared ->
        Keyword.get(opts, :after_batch, fn -> :ok end).()
        last_id = cleared |> List.flatten() |> Enum.max()
        clear(repo, user_id, opts, total + length(cleared), last_id)
    end
  end
end

defmodule Dawarich.RawData.ArchiveWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :maintenance,
    priority: 3,
    max_attempts: 3,
    unique: [
      keys: [:user_id, :cursor, :coverage_floor],
      states: [:available, :scheduled],
      period: :infinity
    ]

  alias Dawarich.RawData.{ArchiveFormat, Archiver, Archives, UserSweep}
  alias Dawarich.{ReleaseOperations, Storage}
  alias Dawarich.State.Lease

  @key "cron:raw_data_archive_job"

  def key, do: @key

  @impl Oban.Worker
  def perform(%Oban.Job{id: id, args: args, conf: conf}),
    do: run(Dawarich.Jobs.repo(), conf.name, args, job_id: id)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(20)

  def run(repo, oban, args, opts \\ [])

  def run(repo, oban, %{"user_id" => user_id, "cursor" => cursor} = args, opts)
      when is_integer(user_id) and is_integer(cursor) do
    storage = Keyword.get_lazy(opts, :storage, fn -> Storage.config!(System.get_env()) end)
    key = Keyword.get_lazy(opts, :archive_key, &ArchiveFormat.key/0)

    result =
      if ReleaseOperations.user?(repo, user_id) do
        Lease.with_lease(
          repo,
          "archive_raw_data:#{user_id}",
          fn ->
            Archives.recover!(repo, storage, user_id)

            Archiver.pass(
              repo,
              storage,
              key,
              user_id,
              min(cursor, Map.get(args, "coverage_floor", cursor)),
              opts
            )
          end,
          timeout_ms: 0
        )
      end

    case result do
      {:ok, {:continue, next}} ->
        continuation = %{"user_id" => user_id, "cursor" => max(cursor, next)}

        continuation =
          if next < cursor, do: Map.put(continuation, "coverage_floor", next), else: continuation

        meta = if opts[:job_id], do: %{"archive_parent_id" => opts[:job_id]}, else: %{}

        case Oban.insert!(oban, new(continuation, meta: meta)) do
          %Oban.Job{id: id} when is_integer(id) ->
            acknowledge(repo.get(Oban.Job, id, prefix: Oban.config(oban).prefix), user_id, next)

          _ ->
            {:snooze, 1}
        end

      {:error, :timeout} ->
        {:snooze, 1}

      _ ->
        :ok
    end
  end

  def run(repo, oban, args, opts) when args == %{},
    do: UserSweep.run(repo, oban, @key, &new(%{"user_id" => &1, "cursor" => 0}), opts)

  def run(_repo, _oban, _args, _opts), do: {:cancel, :invalid_args}

  defp acknowledge(%Oban.Job{args: accepted, state: state}, user_id, next)
       when state in ["available", "scheduled", "executing", "retryable"] do
    if accepted["user_id"] == user_id and accepted["cursor"] >= next and
         Map.get(accepted, "coverage_floor", accepted["cursor"]) <= next,
       do: :ok,
       else: {:snooze, 1}
  end

  defp acknowledge(_, _, _), do: {:snooze, 1}
end

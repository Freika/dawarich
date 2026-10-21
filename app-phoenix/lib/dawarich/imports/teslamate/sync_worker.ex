defmodule Dawarich.Imports.Teslamate.SyncWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 3,
    unique: [keys: [:event_id], states: :incomplete, period: :infinity]

  def args_from_command(1, %{"user_id" => id} = args)
      when is_integer(id) and id > 0 and map_size(args) == 1,
      do: {:ok, args}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: run(Dawarich.Jobs.repo(), job.args, job: job)

  def run(repo, args, opts \\ []) do
    case Dawarich.Imports.Teslamate.Sync.run(repo, args, Keyword.put(opts, :worker, true)) do
      {:ok, _} ->
        :ok

      {:error, message} ->
        {:error, message}

      other ->
        other
    end
  rescue
    error ->
      {:error, error}
  end

  @impl Oban.Worker
  def backoff(job) do
    delay = :math.pow(job.attempt, 4)
    trunc(delay + 2 + :rand.uniform() * 0.15 * delay)
  end
end

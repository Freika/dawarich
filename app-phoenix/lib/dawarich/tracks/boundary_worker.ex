defmodule Dawarich.Tracks.BoundaryWorker do
  @moduledoc false
  use Oban.Worker, queue: :tracks, max_attempts: 5

  alias Dawarich.Tracks.{Boundary, Generation, MetadataRefresher, PerUserLock, Settings}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts, conf: conf}),
    do: run(Dawarich.Jobs.repo(), conf.name, args, attempt: attempt, max_attempts: max_attempts)

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: Integer.pow(attempt, 4) + 2

  @impl Oban.Worker
  def timeout(%Oban.Job{attempt: attempt, max_attempts: max_attempts})
      when attempt >= max_attempts,
      do: :infinity

  def timeout(_job), do: :timer.minutes(30)

  def run(repo, oban, %{"generation_id" => id, "poll_count" => poll_count}, opts \\ []) do
    generation = Generation.get(repo, id)
    Keyword.get(opts, :hook, fn _stage -> :ok end).(:loaded)

    case generation do
      %{status: "running", completed_chunks: done, total_chunks: total} when done < total ->
        case Generation.poll!(repo, oban, generation, poll_count) do
          :missed -> finish_if_done(repo, id, opts)
          _outcome -> :ok
        end

      %{status: "running"} ->
        finish(repo, generation, opts)

      _ ->
        :ok
    end
  rescue
    error ->
      if final?(opts), do: Generation.fail!(repo, id, Exception.message(error))
      reraise error, __STACKTRACE__
  end

  defp finish_if_done(repo, id, opts) do
    case Generation.get(repo, id) do
      %{status: "running", completed_chunks: done, total_chunks: total} = generation
      when done >= total ->
        finish(repo, generation, opts)

      _ ->
        :ok
    end
  end

  defp finish(repo, generation, opts) do
    case Settings.find(repo, generation.user_id) do
      nil ->
        Generation.fail!(repo, generation.id, "User #{generation.user_id} not found")
        :ok

      user ->
        resolve = fn ->
          Boundary.resolve(repo, user)
          MetadataRefresher.run(repo, user)
        end

        case PerUserLock.with_user_lock(user.id, resolve, Keyword.get(opts, :lock, [])) do
          {:ok, _refresh} ->
            Generation.complete!(repo, generation.id)
            :ok

          {:error, reason} ->
            if final?(opts),
              do:
                Generation.fail!(
                  repo,
                  generation.id,
                  "Tracks::PerUserLock: could not acquire lock for user_id=#{user.id}"
                )

            {:error, if(reason == :timeout, do: :lock_busy, else: reason)}
        end
    end
  end

  defp final?(opts), do: Keyword.get(opts, :attempt, 1) >= Keyword.get(opts, :max_attempts, 5)
end

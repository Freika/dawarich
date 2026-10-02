defmodule Dawarich.EnhancedImport.ExtractGpxWorker do
  @moduledoc false
  use Oban.Worker, queue: :extractions, max_attempts: 3

  alias Dawarich.EnhancedImport.{Extract, State}
  alias Dawarich.Storage
  alias Dawarich.Tracks.PerUserLock

  @max_lock_attempts 60
  @margin_ms 60_000

  def args_from_command(1, %{"import_id" => id, "lock_attempt" => n} = p)
      when is_integer(id) and is_integer(n) and n >= 1 and map_size(p) == 2,
      do: {:ok, p}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: trunc(:math.pow(attempt, 4)) + 2

  @impl Oban.Worker
  def timeout(_job), do: Application.fetch_env!(:dawarich, :extraction_timeout_ms)

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: run(Dawarich.Jobs.repo(), job)

  def run(repo, %Oban.Job{args: %{"import_id" => id, "lock_attempt" => first}} = job, opts \\ []) do
    timeout = timeout(job)

    deadline = %{
      at: System.monotonic_time(:millisecond) + timeout - @margin_ms,
      minutes: div(timeout - @margin_ms, 60_000)
    }

    case State.load(repo, id) do
      %{source: 4} = import ->
        extract(repo, import, first + Map.get(job.meta, "snoozed", 0), job, deadline, opts)

      _missing_or_not_gpx ->
        :ok
    end
  end

  defp extract(repo, import, lock_attempt, job, deadline, opts) do
    State.running!(repo, import)
    storage = Keyword.get_lazy(opts, :storage, fn -> Storage.config!(System.get_env()) end)

    process = fn ->
      Extract.process(repo, import, storage, job.args["event_id"], deadline)
    end

    case PerUserLock.with_user_lock(repo, import.user_id, process, Keyword.get(opts, :lock, [])) do
      {:ok, counts} ->
        State.completed!(repo, import, counts)
        :ok

      {:error, :timeout} when lock_attempt >= @max_lock_attempts ->
        State.failed!(repo, import, lock_message(import))
        :ok

      {:error, :timeout} ->
        State.pending!(repo, import)
        {:snooze, 60}
    end
  rescue
    exception -> fail(repo, import, exception, __STACKTRACE__, job)
  end

  defp fail(repo, import, exception, stacktrace, job) do
    message = Exception.message(exception)
    deadlock = match?(%Postgrex.Error{postgres: %{code: :deadlock_detected}}, exception)

    unless deadlock, do: State.retrying!(repo, import, message)
    if job.attempt >= job.max_attempts, do: State.failed!(repo, import, message)

    reraise exception, stacktrace
  end

  defp lock_message(import),
    do: "Tracks::PerUserLock: could not acquire lock for user_id=#{import.user_id} within 30.0s"
end

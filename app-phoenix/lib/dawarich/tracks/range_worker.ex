defmodule Dawarich.Tracks.RangeWorker do
  @moduledoc false
  use Oban.Worker, queue: :tracks, max_attempts: 5

  alias Dawarich.Tracks.{Chunker, Destroy, Generation, PerUserLock, Settings}

  @keys ~w(user_id start_at end_at time_zone mode untracked_only import_id low_priority)

  def args_from_command(1, %{} = p) when map_size(p) == 8 do
    with true <- Enum.all?(@keys, &Map.has_key?(p, &1)),
         true <-
           is_integer(p["user_id"]) and is_binary(p["time_zone"]) and
             p["mode"] in ["bulk", "daily"],
         true <- is_boolean(p["untracked_only"]) and is_boolean(p["low_priority"]),
         true <- is_nil(p["import_id"]) or is_integer(p["import_id"]),
         true <-
           Enum.all?(
             [p["start_at"], p["end_at"]],
             &(is_nil(&1) or (is_binary(&1) and match?({:ok, _, _}, DateTime.from_iso8601(&1))))
           ) do
      {:ok, p}
    else
      _ -> {:error, "invalid_payload"}
    end
  end

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}), do: run(Dawarich.Jobs.repo(), conf.name, args)

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: Integer.pow(attempt, 4) + 2

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  def run(repo, oban, args, opts \\ [])

  def run(repo, oban, %{"user_id" => user_id, "untracked_only" => true} = args, opts) do
    hook = Keyword.get(opts, :hook, fn _stage -> :ok end)

    if Settings.find(repo, user_id),
      do: generate(repo, oban, args, hook, opts),
      else: :ok
  end

  def run(repo, oban, %{"user_id" => user_id} = args, opts) do
    hook = Keyword.get(opts, :hook, fn _stage -> :ok end)

    if Settings.find(repo, user_id) do
      hook.(:locking)

      case PerUserLock.with_user_lock(
             user_id,
             fn -> generate(repo, oban, args, hook, opts) end,
             Keyword.get(opts, :lock, [])
           ) do
        {:ok, :ok} -> :ok
        {:error, :timeout} -> {:error, :lock_busy}
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp generate(repo, oban, %{"event_id" => id, "user_id" => user_id} = args, hook, opts) do
    if Generation.exists?(repo, id) do
      :ok
    else
      hook.(:checked)
      start_at = parse(args["start_at"])
      end_at = parse(args["end_at"])
      chunks = Chunker.chunks(repo, user_id, start_at, end_at, args["time_zone"])

      if args["untracked_only"] == false,
        do: Destroy.clean_range!(repo, user_id, unix(start_at), unix(end_at))

      if chunks != [], do: Generation.start!(repo, oban, args, chunks, opts)
      :ok
    end
  end

  defp parse(nil), do: nil

  defp parse(iso) do
    {:ok, at, _offset} = DateTime.from_iso8601(iso)
    at
  end

  defp unix(nil), do: nil
  defp unix(at), do: DateTime.to_unix(at)
end

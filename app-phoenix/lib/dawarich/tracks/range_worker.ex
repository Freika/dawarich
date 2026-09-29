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

  def run(repo, oban, %{"event_id" => id, "user_id" => user_id} = args, opts \\ []) do
    cond do
      Settings.find(repo, user_id) == nil -> :ok
      Generation.exists?(repo, id) -> :ok
      true -> generate(repo, oban, args, opts)
    end
  end

  defp generate(repo, oban, args, opts) do
    start_at = parse(args["start_at"])
    end_at = parse(args["end_at"])

    with :ok <- clean(repo, args, start_at, end_at, opts) do
      case Chunker.chunks(repo, args["user_id"], start_at, end_at, args["time_zone"]) do
        [] ->
          :ok

        chunks ->
          Generation.start!(repo, oban, args, chunks, opts)
          :ok
      end
    end
  end

  defp clean(repo, %{"untracked_only" => false, "user_id" => user_id}, start_at, end_at, opts) do
    clean_range = fn -> Destroy.clean_range!(repo, user_id, unix(start_at), unix(end_at)) end

    case PerUserLock.with_user_lock(user_id, clean_range, Keyword.get(opts, :lock, [])) do
      {:ok, _destroyed} -> :ok
      {:error, :timeout} -> {:error, :lock_busy}
      {:error, reason} -> {:error, reason}
    end
  end

  defp clean(_repo, _args, _start_at, _end_at, _opts), do: :ok

  defp parse(nil), do: nil

  defp parse(iso) do
    {:ok, at, _offset} = DateTime.from_iso8601(iso)
    at
  end

  defp unix(nil), do: nil
  defp unix(at), do: DateTime.to_unix(at)
end

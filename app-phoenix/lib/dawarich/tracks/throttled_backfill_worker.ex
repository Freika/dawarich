defmodule Dawarich.Tracks.ThrottledBackfillWorker do
  @moduledoc false
  use Oban.Worker, queue: :tracks, priority: 3, max_attempts: 26

  def args_from_command(
        1,
        %{"user_id" => id, "walk_id" => walk, "cursor_timestamp" => cursor, "time_zone" => zone} =
          p
      )
      when map_size(p) == 4 and is_integer(id) and (is_nil(cursor) or is_integer(cursor)) and
             is_binary(zone) do
    case Ecto.UUID.cast(walk) do
      {:ok, _} -> {:ok, p}
      _ -> {:error, "invalid_payload"}
    end
  end

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}), do: run(Dawarich.Jobs.repo(), conf.name, args)

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    count = attempt - 1
    Integer.pow(count, 4) + 15 + :rand.uniform(10 * (count + 1)) - 1
  end

  def run(repo, oban, args, opts \\ []),
    do: Dawarich.Tracks.ThrottledBackfill.run(repo, oban, args, opts)
end

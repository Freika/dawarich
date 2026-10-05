defmodule Dawarich.Tracks.ThrottledBackfill do
  @moduledoc false

  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.RailsCommands
  alias Dawarich.Tracks.{BackfillWalks, RangeWorker, Settings, ThrottledBackfillWorker}

  @key "command:tracks.throttled_backfill"

  def run(repo, oban, args, opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    id = args["user_id"]
    walk = args["walk_id"]
    cursor = args["cursor_timestamp"]

    if Settings.find(repo, id) do
      case BackfillWalks.select(repo, id, walk, cursor, fn -> choose(repo, id, cursor, now) end) do
        {:ok, {:selected, step}} -> start(repo, oban, step, now, opts)
        {:ok, {:empty, _}} -> BackfillWalks.finish(repo, id, walk, cursor, now) |> result()
        {:ok, :stale} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      BackfillWalks.release(repo, id, walk) |> result()
    end
  end

  defp choose(repo, id, cursor, now) do
    case repo.query!(
           "SELECT max(timestamp) FROM points WHERE user_id = $1 AND timestamp < $2",
           [id, cursor || DateTime.to_unix(now)],
           log: false
         ).rows do
      [[nil]] -> nil
      [[maximum]] -> {maximum - 2_592_000, maximum}
    end
  end

  defp start(repo, oban, step, now, opts) do
    repo.transaction(fn ->
      owner = Ownership.lock(repo, @key)
      range_owner = Ownership.lock(repo, "command:tracks.generate_range")
      current = BackfillWalks.current(repo, step.user_id, step.walk_id, step.cursor_timestamp)

      cond do
        is_nil(current) or current.step_event_id != step.step_event_id ->
          :ok

        is_nil(Settings.find(repo, step.user_id)) ->
          BackfillWalks.release(repo, step.user_id, step.walk_id)

        Processed.claim!(repo, step.step_event_id, "tracks.throttled_backfill") ->
          payload = payload(step)
          Keyword.get(opts, :hook, fn _ -> :ok end).({:starting, payload})
          generate(repo, oban, range_owner, payload, opts)

          case BackfillWalks.advance(repo, step, now, &publish(repo, oban, owner, &1)) do
            {:error, reason} -> repo.rollback(reason)
            _ -> :ok
          end

        true ->
          :ok
      end
    end)
    |> result()
  end

  defp generate(repo, oban, :oban, payload, opts) do
    case RangeWorker.run(repo, oban, payload, Keyword.get(opts, :range, [])) do
      {:error, reason} -> repo.rollback(reason)
      :ok -> :ok
    end
  end

  defp generate(repo, _oban, :sidekiq, payload, _opts),
    do: RailsCommands.insert!(repo, "tracks_generate_range", Map.delete(payload, "event_id"))

  defp publish(repo, oban, owner, walk) do
    args = %{
      "user_id" => walk.user_id,
      "walk_id" => walk.walk_id,
      "cursor_timestamp" => walk.cursor_timestamp,
      "time_zone" => walk.time_zone,
      "event_id" => walk.event_id
    }

    case owner do
      :oban ->
        Oban.insert!(oban, ThrottledBackfillWorker.new(args, scheduled_at: walk.due_at))

      :sidekiq ->
        RailsCommands.insert!(
          repo,
          "tracks_throttled_backfill",
          Map.put(args, "scheduled_at", DateTime.to_iso8601(walk.due_at))
        )
    end
  end

  defp payload(step) do
    %{
      "user_id" => step.user_id,
      "start_at" => iso(step.selected_start_timestamp),
      "end_at" => iso(step.selected_end_timestamp),
      "time_zone" => Dawarich.TimeZoneName.to_iana(step.time_zone),
      "mode" => "bulk",
      "untracked_only" => true,
      "import_id" => nil,
      "low_priority" => true,
      "event_id" => step.step_event_id
    }
  end

  defp iso(epoch),
    do: epoch |> DateTime.from_unix!() |> Map.put(:microsecond, {0, 6}) |> DateTime.to_iso8601()

  defp result({:ok, _}), do: :ok
  defp result({:error, reason}), do: {:error, reason}
end

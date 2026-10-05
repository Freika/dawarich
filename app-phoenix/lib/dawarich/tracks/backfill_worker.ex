defmodule Dawarich.Tracks.BackfillWorker do
  @moduledoc false
  use Oban.Worker, queue: :tracks, max_attempts: 26

  require Logger
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Tracks.{BackfillPeriod, RangeWorker}

  def args_from_command(1, %{"user_id" => id, "cycle_id" => cycle, "time_zone" => zone} = p)
      when map_size(p) == 3 and is_integer(id) and
             id in -9_223_372_036_854_775_808..9_223_372_036_854_775_807 and is_binary(zone) and
             is_binary(cycle) and byte_size(cycle) == 36 do
    case Ecto.UUID.cast(cycle) do
      {:ok, _} -> {:ok, p}
      _ -> {:error, "invalid_payload"}
    end
  end

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}), do: run(Dawarich.Jobs.repo(), conf.name, args)

  def run(repo, oban, args, opts \\ []) do
    case repo.transaction(fn -> consume(repo, oban, args, opts) end) do
      {:ok, :ok} -> :ok
      {:error, _} -> rearm(repo, args, opts)
    end
  rescue
    error ->
      Logger.warning("Backfill range publication failed: #{inspect(error.__struct__)}")
      rearm(repo, args, opts)
  end

  defp rearm(repo, args, opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    {:ok, _} =
      repo.transaction(fn ->
        Ownership.lock(repo, "command:tracks.generate_range")

        repo.query!(
          "UPDATE phoenix.track_backfill_ranges SET due_at = $3, expires_at = GREATEST(expires_at, $4), " <>
            "updated_at = $5 WHERE user_id = $1 AND cycle_id = $2",
          [
            args["user_id"],
            Ecto.UUID.dump!(args["cycle_id"]),
            DateTime.add(now, 60),
            DateTime.add(now, 21_600),
            now
          ],
          log: false
        )
      end)

    {:snooze, 60}
  end

  defp consume(repo, oban, %{"user_id" => user_id, "cycle_id" => cycle}, opts) do
    owner = Ownership.lock(repo, "command:tracks.generate_range")
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    case repo.query!(
           "SELECT earliest_timestamp, latest_timestamp, time_zone, expires_at FROM phoenix.track_backfill_ranges " <>
             "WHERE user_id = $1 AND cycle_id = $2 FOR UPDATE",
           [user_id, Ecto.UUID.dump!(cycle)],
           log: false
         ).rows do
      [[earliest, latest, zone, expires_at]] ->
        if Processed.claim!(repo, cycle, "tracks.backfill") and
             DateTime.compare(expires_at, now) == :gt do
          payload = BackfillPeriod.payload(repo, user_id, earliest, latest, zone, now)
          Keyword.get(opts, :hook, fn _ -> :ok end).(:publishing)
          publish(repo, oban, owner, payload, cycle)
        end

        repo.query!(
          "DELETE FROM phoenix.track_backfill_ranges WHERE user_id = $1 AND cycle_id = $2",
          [user_id, Ecto.UUID.dump!(cycle)],
          log: false
        )

      [] ->
        :ok
    end

    :ok
  end

  defp publish(_repo, oban, :oban, payload, cycle),
    do: Oban.insert!(oban, RangeWorker.new(Map.put(payload, "event_id", cycle)))

  defp publish(repo, _oban, :sidekiq, payload, _cycle),
    do: Dawarich.RailsCommands.insert!(repo, "tracks_generate_range", payload)
end

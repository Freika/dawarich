defmodule Dawarich.Tracks.RealtimeWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :tracks,
    max_attempts: 1,
    unique: [period: :infinity, keys: [:user_id], states: [:available, :scheduled]]

  require Logger

  alias Dawarich.Tracks.{Boundary, Builder, Merger, PerUserLock, Points, Settings}

  @lookback 6 * 3_600
  @geocode_window 300

  def args_from_command(1, %{"user_id" => id} = payload)
      when is_integer(id) and map_size(payload) == 1,
      do: {:ok, %{"user_id" => id}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}) do
    repo = Dawarich.Jobs.repo()
    Dawarich.State.unclaim(repo, Dawarich.Tracks.RealtimeCommands.key(args["user_id"]))
    run(repo, conf.name, args)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  def run(repo, oban, %{"user_id" => user_id} = args, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> System.os_time(:second) end)

    case Settings.find(repo, user_id) do
      %{status: status} = user when status in [1, 2] ->
        generate(repo, oban, user, now, Keyword.put(opts, :event_id, args["event_id"]))

      _ ->
        :ok
    end
  rescue
    error ->
      Logger.error(
        "Failed real-time track generation for user #{user_id}: #{Exception.message(error)}"
      )

      :ok
  end

  defp generate(repo, oban, user, now, opts) do
    case PerUserLock.with_user_lock(
           repo,
           user.id,
           fn -> build(repo, user, now) end,
           Keyword.get(opts, :lock, [])
         ) do
      {:ok, :ok} ->
        Dawarich.Tracks.RecentGeocoding.run(
          repo,
          oban,
          user.id,
          now - @geocode_window,
          opts[:event_id]
        )

        :ok

      {:ok, {:error, :race_lost}} ->
        {:error, :race_lost}

      {:error, :timeout} ->
        Logger.warning("Tracks::RealtimeGenerationJob lock_busy user_id=#{user.id}")

        Dawarich.Tracks.RealtimeCommands.trigger(repo, user.id,
          oban: oban,
          now: DateTime.from_unix!(now),
          kind: "tracks_realtime_retrigger"
        )

        :ok
    end
  end

  defp build(repo, user, now) do
    minutes = Settings.minutes_between_routes(user)

    repo
    |> Points.realtime_segments(
      user.id,
      now - @lookback,
      now,
      minutes,
      Settings.meters_between_routes(user)
    )
    |> Enum.reduce_while(:ok, fn segment, :ok ->
      case Builder.create_track!(repo, user, segment.points, segment.distance,
             tracker_id: segment.tracker_id
           ) do
        {:ok, track} ->
          Merger.merge_into_preceding(repo, user, track)
          {:cont, :ok}

        nil ->
          {:cont, :ok}

        {:error, :race_lost} ->
          {:halt, {:error, :race_lost}}
      end
    end)
    |> case do
      :ok ->
        Boundary.resolve(repo, user, now: now)
        :ok

      lost ->
        lost
    end
  end
end

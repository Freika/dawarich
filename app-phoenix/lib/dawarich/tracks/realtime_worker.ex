defmodule Dawarich.Tracks.RealtimeWorker do
  @moduledoc false
  use Oban.Worker, queue: :tracks, max_attempts: 1

  require Logger

  alias Dawarich.RailsCommands
  alias Dawarich.Tracks.{Boundary, Builder, Merger, PerUserLock, Points, Settings}

  @lookback 6 * 3_600
  @geocode_window 300

  def args_from_command(1, %{"user_id" => id} = payload)
      when is_integer(id) and map_size(payload) == 1,
      do: {:ok, %{"user_id" => id}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}), do: run(Dawarich.Jobs.repo(), conf.name, args)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  def run(repo, _oban, %{"user_id" => user_id}, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> System.os_time(:second) end)

    case Settings.find(repo, user_id) do
      %{status: status} = user when status in [1, 2] -> generate(repo, user, now, opts)
      _ -> :ok
    end
  rescue
    error ->
      Logger.error(
        "Failed real-time track generation for user #{user_id}: #{Exception.message(error)}"
      )

      :ok
  end

  defp generate(repo, user, now, opts) do
    case PerUserLock.with_user_lock(
           user.id,
           fn -> build(repo, user, now) end,
           Keyword.get(opts, :lock, [])
         ) do
      {:ok, :ok} ->
        RailsCommands.insert!(repo, "geocode_recent_points", %{
          "user_id" => user.id,
          "since" => now - @geocode_window
        })

        :ok

      {:ok, {:error, :race_lost}} ->
        {:error, :race_lost}

      {:error, :timeout} ->
        Logger.warning("Tracks::RealtimeGenerationJob lock_busy user_id=#{user.id}")
        RailsCommands.insert!(repo, "tracks_realtime_retrigger", %{"user_id" => user.id})
        :ok

      {:error, reason} ->
        Logger.error("Failed real-time track generation for user #{user.id}: #{inspect(reason)}")
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

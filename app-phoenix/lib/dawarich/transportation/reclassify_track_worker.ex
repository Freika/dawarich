defmodule Dawarich.Transportation.ReclassifyTrackWorker do
  @moduledoc false
  use Oban.Worker, queue: :tracks, max_attempts: 2

  alias Dawarich.RailsCommands
  alias Dawarich.Tracks.Effects
  alias Dawarich.Transportation.Segments

  @track "SELECT t.user_id, floor(extract(epoch FROM t.start_at))::bigint, floor(extract(epoch FROM t.end_at))::bigint FROM tracks t WHERE t.id = $1"

  @settings "SELECT COALESCE(settings, '{}'::jsonb) FROM users WHERE id = $1 AND deleted_at IS NULL"

  @guard """
  INSERT INTO phoenix.processed_commands (event_id, handler, processed_at) VALUES ($1, 'transportation.reclassify_track', now())
  ON CONFLICT (event_id) DO NOTHING RETURNING event_id
  """

  def args_from_command(
        1,
        %{"track_id" => id, "report_progress" => report, "user_id" => user_id} = payload
      )
      when is_integer(id) and is_boolean(report) and (is_nil(user_id) or is_integer(user_id)) and
             map_size(payload) == 3,
      do: {:ok, %{"track_id" => id, "report_progress" => report, "user_id" => user_id}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts, conf: conf}),
    do: run(Dawarich.Jobs.repo(), conf.name, args, attempt: attempt, max_attempts: max_attempts)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  def run(repo, _oban, %{"track_id" => track_id} = args, opts \\ []) do
    track = track(repo, track_id)
    report_user = args["user_id"] || (track && track.user_id)
    hook = Keyword.get(opts, :hook, fn _stage -> :ok end)

    {:ok, _} =
      repo.transaction(fn ->
        if track, do: reclassify!(repo, track_id, track, hook)
        if args["report_progress"], do: progress!(repo, report_user, args["event_id"])
      end)

    :ok
  rescue
    error ->
      if args["report_progress"] and
           Keyword.get(opts, :attempt, 1) >= Keyword.get(opts, :max_attempts, 2) do
        user_id = args["user_id"] || (track(repo, track_id) || %{user_id: nil}).user_id
        {:ok, _} = repo.transaction(fn -> progress!(repo, user_id, args["event_id"]) end)
      end

      reraise error, __STACKTRACE__
  end

  defp reclassify!(repo, track_id, track, hook) do
    settings =
      case repo.query!(@settings, [track.user_id], log: false).rows do
        [[settings]] -> settings
        [] -> %{}
      end

    Segments.reclassify!(repo, track_id, settings, fallback: false)
    Effects.write!(repo, track.user_id, %{stamps: [track.start_at, track.end_at]})
    hook.(:reclassified)
  end

  defp progress!(_repo, nil, _event_id), do: :ok

  defp progress!(repo, user_id, event_id) do
    case repo.query!(@guard, [Ecto.UUID.dump!(event_id)], log: false).rows do
      [_] ->
        RailsCommands.insert!(repo, "transport_progress", %{
          "user_id" => user_id,
          "event_id" => event_id
        })

      [] ->
        :ok
    end
  end

  defp track(repo, track_id) do
    case repo.query!(@track, [track_id], log: false).rows do
      [[user_id, start_at, end_at]] -> %{user_id: user_id, start_at: start_at, end_at: end_at}
      [] -> nil
    end
  end
end

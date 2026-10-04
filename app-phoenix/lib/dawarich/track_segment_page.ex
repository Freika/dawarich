defmodule Dawarich.TrackSegmentPage do
  @moduledoc false
  alias Dawarich.{Repo, Transportation.Segments, TripSettings, UserTimeZone}

  def load(user, id, repo \\ Repo) do
    if settings?(user.settings) do
      rows =
        repo.query!(
          "SELECT s.id, t.id, s.start_index, s.end_index, s.start_at, s.end_at, s.distance, s.duration, s.transportation_mode, s.confidence_score, s.corrected_at FROM public.tracks t LEFT JOIN public.track_segments s ON s.track_id = t.id WHERE t.user_id = $1 AND t.id = $2 ORDER BY s.start_at, s.start_index",
          [user.id, id]
        ).rows

      case rows do
        [] ->
          :rails

        [[nil | _]] ->
          {:ok, %{track_id: id, segments: []}}

        rows ->
          segments = Enum.map(rows, &row/1)
          if exact_order?(segments), do: {:ok, %{track_id: id, segments: segments}}, else: :rails
      end
    else
      :rails
    end
  end

  defp exact_order?(segments) do
    keys = Enum.map(segments, &{&1.start_at, &1.start_index})
    starts = segments |> Enum.map(& &1.start_at) |> Enum.reject(&is_nil/1)
    length(Enum.uniq(keys)) == length(keys) and length(Enum.uniq(starts)) == length(starts)
  end

  defp settings?(%{} = settings) do
    modes = settings["enabled_transportation_modes"]
    maps = settings["maps"]

    (is_nil(modes) or (is_list(modes) and Enum.all?(modes, &is_binary/1))) and
      (is_nil(maps) or
         (is_map(maps) and (is_nil(maps["distance_unit"]) or is_binary(maps["distance_unit"])))) and
      (is_nil(settings["timezone"]) or is_binary(settings["timezone"])) and
      TripSettings.zone?(settings, UserTimeZone.name(settings))
  end

  defp settings?(_), do: false

  defp row([
         id,
         track_id,
         first,
         last,
         start_at,
         end_at,
         distance,
         duration,
         mode,
         score,
         corrected
       ]),
       do: %{
         id: id,
         track_id: track_id,
         start_index: first,
         end_index: last,
         start_at: start_at,
         end_at: end_at,
         distance: distance,
         duration: duration,
         transportation_mode: Segments.int_to_mode(mode),
         confidence_score: score,
         corrected_at: corrected
       }
end

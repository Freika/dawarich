defmodule Dawarich.TrackSegmentPage do
  @moduledoc false
  alias Dawarich.{Repo, Transportation.Segments}

  def load(user, id) do
    with [[^id]] <-
           Repo.query!("SELECT t.id FROM public.tracks t WHERE t.user_id = $1 AND t.id = $2", [
             user.id,
             id
           ]).rows,
         [] <-
           Repo.query!(
             "SELECT 1 FROM public.track_segments WHERE track_id = $1 GROUP BY start_at, start_index HAVING count(*) > 1 LIMIT 1",
             [id]
           ).rows do
      rows =
        Repo.query!(
          "SELECT id, track_id, start_index, end_index, start_at, end_at, distance, duration, transportation_mode, confidence_score, corrected_at FROM public.track_segments WHERE track_id = $1 ORDER BY start_at, start_index",
          [id]
        ).rows

      {:ok, %{track_id: id, segments: Enum.map(rows, &row/1)}}
    else
      _ -> :rails
    end
  end

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

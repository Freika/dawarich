defmodule Dawarich.Tracks.Reprocessor do
  @moduledoc false

  alias Dawarich.Tracks.{Settings, Store}
  alias Dawarich.Transportation.{Detector, DominantMode, Segments}

  def reprocess!(repo, user, track) do
    preserved = Segments.clear_inference!(repo, track.id)

    segment_data =
      Detector.call(repo, track,
        enabled_modes: Settings.enabled_modes(user),
        preserved: preserved,
        fallback: false
      )

    if segment_data != [], do: Segments.insert!(repo, track.id, segment_data)

    segments =
      repo.query!(
        "SELECT transportation_mode, distance, duration FROM track_segments WHERE track_id = $1 ORDER BY id",
        [track.id],
        log: false
      ).rows

    mode =
      segments
      |> Enum.map(fn [mode, distance, duration] ->
        %{transportation_mode: Segments.int_to_mode(mode), distance: distance, duration: duration}
      end)
      |> DominantMode.pick()

    if mode,
      do: Store.save!(repo, track, dominant_mode: Segments.mode_to_int(mode)),
      else: track
  end
end

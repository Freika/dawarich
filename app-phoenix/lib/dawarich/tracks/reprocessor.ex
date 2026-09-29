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

    mode =
      repo
      |> Segments.load_segments_for_dominant_mode!(track.id)
      |> DominantMode.pick()

    if mode,
      do: Store.save!(repo, track, dominant_mode: Segments.mode_to_int(mode)),
      else: track
  end
end

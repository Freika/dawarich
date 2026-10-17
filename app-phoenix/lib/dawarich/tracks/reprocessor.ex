defmodule Dawarich.Tracks.Reprocessor do
  @moduledoc false

  alias Dawarich.Tracks.{Effects, Settings, Store}
  alias Dawarich.Transportation.{Detector, DominantMode, Segments}

  def reprocess!(repo, user, track, now \\ nil, opts \\ []) do
    preserved = Segments.clear_inference!(repo, track.id)

    detector = Keyword.get(opts, :detector, &Detector.call/3)

    segment_data =
      detector.(repo, track,
        enabled_modes: user && Settings.enabled_modes(user),
        preserved: preserved,
        fallback: Keyword.get(opts, :fallback, false)
      )

    if segment_data != [], do: Segments.insert!(repo, track.id, segment_data, now)

    mode =
      repo
      |> Segments.load_segments_for_dominant_mode!(track.id)
      |> DominantMode.pick()

    result =
      if mode do
        saved = Store.save!(repo, track, [dominant_mode: Segments.mode_to_int(mode)], now)

        if Keyword.get(opts, :callbacks, false) do
          Effects.write!(repo, track.user_id, %{
            updated: [track.id],
            stamps: [track.start_at, track.end_at]
          })
        end

        saved
      else
        track
      end

    if Keyword.get(opts, :map_matching, true),
      do: Dawarich.Tracks.MapMatching.Enqueuer.defer(repo, track.id)

    result
  end
end

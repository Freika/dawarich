defmodule Dawarich.Transportation.Detector do
  @moduledoc false

  require Logger

  alias Dawarich.RubyInteger

  alias Dawarich.Transportation.{
    Decoder,
    Emissions,
    FeatureExtractor,
    Preprocessor,
    SegmentAssembler,
    Segments,
    Windower
  }

  @all_modes ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle)

  def call(repo, track, opts \\ []) do
    enabled_modes =
      case Keyword.get(opts, :enabled_modes) do
        modes when modes in [nil, []] -> @all_modes
        modes -> modes
      end

    preserved = Keyword.get(opts, :preserved, [])
    decode_fn = Keyword.get(opts, :decode_fn, &Decoder.call/2)

    detect(repo, track, enabled_modes, preserved, decode_fn)
  rescue
    error ->
      if Keyword.get(opts, :fallback, true) do
        Logger.warning(
          "Transportation mode detection failed for track #{track.id}: " <>
            Exception.message(error)
        )

        default_unknown_segment(track)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp detect(repo, track, enabled_modes, preserved, decode_fn) do
    rows = repo |> FeatureExtractor.rows(track.id) |> Preprocessor.call()

    if degenerate?(rows) do
      default_unknown_segment(track)
    else
      windows = Windower.call(rows)

      if windows == [] do
        default_unknown_segment(track)
      else
        decoded = decode_fn.(windows, enabled_modes)
        anchored = anchored_preserved(repo, preserved)
        SegmentAssembler.call(rows, windows, decoded, anchored)
      end
    end
  end

  defp degenerate?(rows) do
    length(rows) < 2 or
      List.last(rows).ts - List.first(rows).ts < Emissions.tuning()[:min_track_duration_s]
  end

  defp default_unknown_segment(track) do
    [
      %{
        mode: "unknown",
        start_at: track.start_at,
        end_at: track.end_at,
        path_wkt: nil,
        distance: track.distance && RubyInteger.to_i(track.distance),
        duration: track.duration,
        avg_speed: track.avg_speed && track.avg_speed * 1.0,
        max_speed: nil,
        confidence: "low",
        confidence_score: 0.0,
        source: "default"
      }
    ]
  end

  defp anchored_preserved(_repo, []), do: []

  defp anchored_preserved(repo, preserved) do
    unanchored_ids =
      preserved
      |> Enum.filter(fn s -> is_nil(s.start_at) and not is_nil(s.start_index) end)
      |> Enum.map(& &1.id)

    if unanchored_ids == [] do
      preserved
    else
      Segments.anchor_now!(repo, unanchored_ids)
      Segments.preserved_by_ids!(repo, Enum.map(preserved, & &1.id))
    end
  end
end

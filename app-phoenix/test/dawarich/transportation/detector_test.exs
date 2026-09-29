defmodule Dawarich.Transportation.DetectorTest do
  use Dawarich.JobsCase

  alias Dawarich.Tracks.TracksFixtures
  alias Dawarich.Transportation.Detector

  @all_modes ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle)

  setup do
    ScratchRepo.query!(
      "TRUNCATE tracks, points, track_segments, imports RESTART IDENTITY CASCADE",
      [],
      log: false
    )

    :ok
  end

  test "degenerate and short tracks give one unknown segment" do
    %{expected: expected} = TracksFixtures.load!(ScratchRepo, "transport_stages")

    for name <- ["sparse", "degenerate"] do
      data = expected[name]
      segments = Detector.call(ScratchRepo, track_map(data["track"]), enabled_modes: @all_modes)

      assert length(segments) == 1
      assert stringify(segments) == data["segments"]
    end
  end

  test "fallback: false propagates, fallback: true degrades" do
    %{expected: expected} = TracksFixtures.load!(ScratchRepo, "transport_stages")
    track = track_map(expected["walk_drive_walk"]["track"])
    raising_decoder = fn _windows, _enabled -> raise "boom" end

    assert_raise RuntimeError, "boom", fn ->
      Detector.call(ScratchRepo, track,
        enabled_modes: @all_modes,
        decode_fn: raising_decoder,
        fallback: false
      )
    end

    segments =
      Detector.call(ScratchRepo, track,
        enabled_modes: @all_modes,
        decode_fn: raising_decoder,
        fallback: true
      )

    assert [%{mode: "unknown", source: "default"}] = segments
  end

  defp track_map(track) do
    %{
      id: track["id"],
      start_at: track["start_at"],
      end_at: track["end_at"],
      distance: track["distance"],
      duration: track["duration"],
      avg_speed: track["avg_speed"]
    }
  end

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), stringify(v)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(other), do: other
end

defmodule Dawarich.MapMatching.FingerprintTest do
  use ExUnit.Case, async: true
  alias Dawarich.MapMatching.{Fingerprint, Input}

  test "fingerprint changes when a timestamp, accuracy, segment boundary or mode changes and is stable across key insertion order" do
    points = [
      %{id: 1, timestamp: 100, lon: 13.4, lat: 52.5, accuracy: 5.0},
      %{id: 2, timestamp: 110, lon: 13.41, lat: 52.51, accuracy: nil}
    ]

    segments = [
      %{
        id: 9,
        start_at: 100,
        end_at: 110,
        start_index: 0,
        end_index: 1,
        transportation_mode: "walking"
      }
    ]

    input = Input.new(points, segments)
    digest = Fingerprint.call(input)
    assert digest =~ ~r/\A[0-9a-f]{64}\z/

    assert Input.fingerprint_payload(input).request == %{
             shape_match: "map_snap",
             format: "geojson",
             include_directions: false
           }

    assert Input.fingerprint_payload(input).points == [
             %{lat: 52.5, lon: 13.4, time: 100, accuracy: 5.0},
             %{lat: 52.51, lon: 13.41, time: 110}
           ]

    for {key, value} <- [timestamp: 101, accuracy: 6.0, lon: 13.45, lat: 52.55] do
      changed = [Map.put(hd(points), key, value), List.last(points)]
      refute Fingerprint.call(Input.new(changed, segments)) == digest
    end

    for {key, value} <- [
          start_at: 101,
          end_at: 111,
          start_index: 1,
          end_index: 2,
          transportation_mode: "running"
        ] do
      refute Fingerprint.call(Input.new(points, [Map.put(hd(segments), key, value)])) == digest
    end

    reversed_keys = Enum.map(points, &(Enum.reverse(Map.to_list(&1)) |> Map.new()))
    assert Fingerprint.call(Input.new(reversed_keys, segments)) == digest
    payload = Input.fingerprint_payload(input)

    assert Fingerprint.call(payload) ==
             Fingerprint.call(Map.new(Enum.reverse(Map.to_list(payload))))

    refute Fingerprint.call(%{payload | points: Enum.reverse(payload.points)}) == digest
  end
end

defmodule Dawarich.Transportation.SegmentAssemblerTest do
  use ExUnit.Case, async: true

  alias Dawarich.Transportation.SegmentAssembler

  test "rounds avg_speed, max_speed and confidence_score exactly as Ruby's RubyFloat.round" do
    rows = [
      %{ts: 0, dist_m: nil, lon: 12.3731, lat: 51.3397, speed_valid: false, speed_mps: nil},
      %{ts: 36, dist_m: 0.15, lon: 12.3732, lat: 51.3398, speed_valid: true, speed_mps: 0.15 / 36}
    ]

    windows = [
      %{start_ts: 0, hints: [], gap_before: false},
      %{start_ts: 30, hints: [], gap_before: false}
    ]

    decoded = [
      %{mode: "walking", posterior: 0.4002},
      %{mode: "walking", posterior: 0.4003}
    ]

    [segment] = SegmentAssembler.call(rows, windows, decoded, [])

    assert segment.avg_speed == 0.02
    assert segment.max_speed == 0.02
    assert segment.confidence_score == 0.4003
  end
end

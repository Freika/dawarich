defmodule Dawarich.MapMatching.ModeMapperTest do
  use ExUnit.Case, async: true
  alias Dawarich.MapMatching.ModeMapper

  test "supported modes use the Rails costing table" do
    for {mode, costing} <- [
          walking: "pedestrian",
          running: "pedestrian",
          cycling: "bicycle",
          driving: "auto",
          bus: "auto",
          motorcycle: "auto"
        ] do
      assert ModeMapper.call(mode) == costing
      assert ModeMapper.call(Atom.to_string(mode)) == costing
    end
  end

  test "unsupported modes map to nil" do
    for mode <- [nil, "unknown", "stationary", "train", "flying", "boat", "teleport"] do
      assert ModeMapper.call(mode) == nil
    end
  end
end

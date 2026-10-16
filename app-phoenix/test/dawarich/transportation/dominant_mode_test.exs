defmodule Dawarich.Transportation.DominantModeTest do
  use ExUnit.Case, async: true
  alias Dawarich.Transportation.DominantMode

  test "equal moving and stationary totals select the lowest persisted segment ID" do
    for {first, second, distance} <- [{"walking", "driving", 100}, {"unknown", "stationary", 0}] do
      a = %{id: 1, transportation_mode: first, distance: distance, duration: 100}
      b = %{id: 2, transportation_mode: second, distance: distance, duration: 100}
      assert DominantMode.pick([b, a]) == first
      assert DominantMode.pick([a, b]) == first
    end
  end
end

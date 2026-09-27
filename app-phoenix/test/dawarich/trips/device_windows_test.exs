defmodule Dawarich.Trips.DeviceWindowsTest do
  use ExUnit.Case, async: true

  alias Dawarich.Trips.DeviceWindows

  test "the busiest device covers its span and hands over where it stops" do
    assert DeviceWindows.primary([["a", 100, 200], ["b", 150, 300]]) == [
             {"a", 100, 200},
             {"b", 201, 300}
           ]
  end

  test "a device fills the gaps around a higher-priority one" do
    assert DeviceWindows.primary([["a", 100, 200], ["b", 50, 400]]) ==
             [{"b", 50, 99}, {"a", 100, 200}, {"b", 201, 400}]
  end

  test "separate sessions of one device stay separate across a silent gap" do
    assert DeviceWindows.primary([["a", 100, 200], ["a", 500, 600]]) == [
             {"a", 100, 200},
             {"a", 500, 600}
           ]
  end
end

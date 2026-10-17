defmodule Dawarich.Build.TimeZonesTest do
  use ExUnit.Case, async: true

  alias Dawarich.RailsTree

  test "the time-zone snapshot uses the tzinfo-data version in Gemfile.lock" do
    [_, version] = Regex.run(~r/^    tzinfo-data \(([^)]+)\)$/m, RailsTree.read("Gemfile.lock"))
    snapshot = "priv/time_zones.json" |> File.read!() |> Jason.decode!()

    assert snapshot["tzinfo_data_version"] == version
  end
end

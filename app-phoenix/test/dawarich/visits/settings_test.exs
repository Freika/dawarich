defmodule Dawarich.Visits.SettingsTest do
  use ExUnit.Case, async: true

  alias Dawarich.Visits.Settings
  alias Dawarich.Wave5bFixtures

  @keys [:stay_radius_m, :min_dwell_s, :min_points, :merge_gap_s, :suggestions_enabled]

  test "defaults, clamps and the string setting" do
    %{"cases" => cases} = Wave5bFixtures.read!("test/fixtures/visits/settings_policy.json")
    assert length(cases) == 6

    for %{"name" => name, "settings" => settings, "expected" => expected} <- cases do
      policy = settings |> Settings.policy() |> Map.take(@keys)
      assert policy == Map.new(expected, fn {k, v} -> {String.to_atom(k), v} end), name
    end

    assert Settings.policy(%{"visit_radius_meters" => "2"}).stay_radius_m == 5
    assert Settings.policy(%{"visit_min_duration_minutes" => nil}).min_dwell_s == 300
    refute Settings.policy(%{"visits_suggestions_enabled" => true}).suggestions_enabled
  end

  test "an absent merge threshold is Rails' default and an explicit nil is zero" do
    assert Settings.policy(%{}).merge_gap_s == 900
    assert Settings.policy(%{"merge_threshold_minutes" => nil}).merge_gap_s == 0
    assert Settings.policy("not a hash").stay_radius_m == 100
  end

  test "pipeline constants" do
    assert Map.take(Settings.policy(%{}), [
             :sweep_gap_s,
             :bridge_cap_s,
             :snap_max_s,
             :attribution_radius_m
           ]) ==
             %{
               sweep_gap_s: 3600,
               bridge_cap_s: 604_800,
               snap_max_s: 900,
               attribution_radius_m: 50
             }
  end
end

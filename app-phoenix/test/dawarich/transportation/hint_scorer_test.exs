defmodule Dawarich.Transportation.HintScorerTest do
  use ExUnit.Case, async: true

  alias Dawarich.Transportation.HintScorer

  test "overland hints keep first-seen order on an equal-boost tie" do
    assert HintScorer.call(%{"motion" => ["walking", "stationary"]}) == [
             {"walking", 2.1972245773362196}
           ]
  end

  test "google probable-activities keep first-seen order on an equal-boost tie (percentages clamp to 1.0)" do
    activities = [
      %{"activityType" => "WALKING", "probability" => 60.5},
      %{"activityType" => "CYCLING", "probability" => 20.1},
      %{"activityType" => "IN_BUS", "probability" => 10.0}
    ]

    assert HintScorer.call(%{"activities" => activities}) == [{"walking", 2.1972245773362196}]
  end

  test "overland hints keep first-seen order on a three-way equal-boost tie" do
    assert HintScorer.call(%{"motion" => ["running", "cycling", "walking"]}) == [
             {"running", 2.1972245773362196}
           ]
  end
end

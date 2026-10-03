defmodule DawarichWeb.InsightsDetailsPartsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]
  alias Dawarich.Test.ParityHTML
  alias DawarichWeb.InsightsDetails.Activity

  for {state, order} <- [
        {"fresh", ~w(walking stationary flying)},
        {"persisted", ~w(flying walking stationary)}
      ] do
    test "actual #{state} JSON order preserves the tied activity full Rails card" do
      order = unquote(order)

      values = %{
        "walking" => %{"duration" => 600, "percentage" => 14},
        "stationary" => %{"duration" => 1800, "percentage" => 43},
        "flying" => %{"duration" => 1800, "percentage" => 43}
      }

      patterns = %Jason.OrderedObject{
        values: [
          {"activity_breakdown", %Jason.OrderedObject{values: Enum.map(order, &{&1, values[&1]})}}
        ]
      }

      attrs = %{"_rails_json" => %{"travel_patterns" => Jason.encode!(patterns)}}
      data = Map.put(Dawarich.RailsCache.JsonOrder.pattern_pairs(attrs), :activity, values)
      actual = render_component(&Activity.render/1, %{locale: "en", data: data})
      expected = File.read!("test/fixtures/insights/activity-#{unquote(state)}.html")
      assert ParityHTML.normalize(actual) == ParityHTML.normalize(expected)
    end
  end
end

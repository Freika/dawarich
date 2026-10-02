defmodule DawarichWeb.InsightsDetailsPartsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]
  alias Dawarich.Test.ParityHTML

  alias DawarichWeb.InsightsDetails.{
    YearComparison,
    Activity,
    Locations,
    Monthly,
    Travel,
    Wellness
  }

  for locale <- ["en", "de"] do
    test "#{locale} comparison, activity and confirmed locations match actual Rails cards" do
      locale = unquote(locale)

      totals = %{
        distance: 50,
        countries: 2,
        cities: 2,
        days: 5,
        biggest_month: %{year: 2024, month: 3, distance: 38}
      }

      previous = %{
        distance: 20,
        countries: 1,
        cities: 1,
        days: 1,
        biggest_month: %{year: 2023, month: 7, distance: 20}
      }

      comparison = %{
        previous: previous,
        distance_change: 150,
        countries_change: 1,
        cities_change: 100,
        days_change: 400
      }

      data = %{
        year: 2024,
        totals: totals,
        comparison: comparison,
        unit: "km",
        activity: %{},
        top_visits: [
          %{name: "Office", visit_count: 2, total_duration: 240},
          %{name: "Home", visit_count: 1, total_duration: 90}
        ]
      }

      corpus = Jason.decode!(File.read!("test/fixtures/insights/b3-corpus.json"))
      id = Enum.find(corpus["users"], &(&1["email"] == "e2e-stats@dawarich.test"))["id"]

      monthly =
        Enum.find(
          corpus["digests"],
          &(&1["user_id"] == id and &1["month"] == 4 and &1["period_type"] == "monthly")
        )

      data =
        Map.merge(data, %{
          monthly: monthly,
          selected_month: 4,
          available_months: [3, 4],
          country_codes: [],
          time_of_day: %{"night" => 0, "morning" => 75, "afternoon" => 25, "evening" => 0},
          seasonality: %{"winter" => 0, "spring" => 100, "summer" => 0, "fall" => 0},
          weekly: [0, 10015, 26036, 14021, 0, 0, 0]
        })

      html = File.read!("test/fixtures/insights/details-#{locale}.html")
      cards = html |> LazyHTML.from_fragment() |> LazyHTML.query("div.card") |> LazyHTML.to_tree()

      for {module, index} <- [
            {YearComparison, 0},
            {Activity, 1},
            {Locations, 2},
            {Monthly, 3},
            {Travel, 4},
            {Wellness, 5}
          ] do
        native = render_component(&module.render/1, %{locale: locale, data: data})
        expected = [Enum.at(cards, index)]

        expected =
          if index == 4,
            do:
              expected ++
                (html
                 |> LazyHTML.from_fragment()
                 |> LazyHTML.query("div.alert")
                 |> LazyHTML.to_tree()),
            else: expected

        actual = ParityHTML.normalize(native)
        expected = ParityHTML.normalize(expected)
        equal = actual == expected

        assert equal,
               "card #{index} first difference: #{inspect(first_difference(actual, expected), limit: 12)}"
      end

      modules = [
        {"year_comparison", YearComparison},
        {"activity_breakdown", Activity},
        {"location_clusters", Locations},
        {"monthly_digest", Monthly},
        {"travel_patterns", Travel},
        {"movement_wellness", Wellness}
      ]

      fragments =
        Map.new(modules, fn {name, module} ->
          {name, render_component(&module.render/1, %{locale: locale, data: data})}
        end)

      frame =
        render_component(&DawarichWeb.InsightsDetails.Body.render/1, %{
          locale: locale,
          data: Map.put(data, :restricted, false),
          fragments: fragments
        })

      same = ParityHTML.normalize(frame) == ParityHTML.normalize(html)

      assert same,
             "whole details frame differs: #{inspect(first_difference(ParityHTML.normalize(frame), ParityHTML.normalize(html)), limit: 10)}"
    end
  end

  test "actual walking activity, escaped location and wellness card retain Rails full DOM" do
    data = %{
      activity: %{"walking" => %{"duration" => 600, "percentage" => 100}},
      top_visits: [
        %{name: "<img src=x onerror=\"alert(1)\"> fixture", visit_count: 1, total_duration: 60}
      ]
    }

    html = File.read!("test/fixtures/insights/details-activity.html")
    cards = html |> LazyHTML.from_fragment() |> LazyHTML.query("div.card") |> LazyHTML.to_tree()

    for {module, index} <- [{Activity, 1}, {Locations, 2}, {Wellness, 5}] do
      native = render_component(&module.render/1, %{locale: "en", data: data})
      actual = ParityHTML.normalize(native)
      expected = ParityHTML.normalize([Enum.at(cards, index)])
      equal = actual == expected

      assert equal,
             "actual activity card #{index} differs: #{inspect(first_difference(actual, expected), limit: 10)}"
    end
  end

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

  defp first_difference(a, a), do: nil

  defp first_difference(a, b) when is_list(a) and is_list(b) and length(a) == length(b),
    do: Enum.zip(a, b) |> Enum.find_value(fn {a, b} -> first_difference(a, b) end)

  defp first_difference(a, b) when is_tuple(a) and is_tuple(b) and tuple_size(a) == tuple_size(b),
    do: first_difference(Tuple.to_list(a), Tuple.to_list(b))

  defp first_difference(a, b), do: {a, b}
end

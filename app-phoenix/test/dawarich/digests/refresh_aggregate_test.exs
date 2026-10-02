defmodule Dawarich.Digests.RefreshAggregateTest do
  use ExUnit.Case, async: true
  alias Dawarich.Digests.Refresh.Aggregate

  @corpus Path.expand("../../fixtures/insights/b3-corpus.json", __DIR__)

  test "year projection matches the actual B3 Rails calculator output" do
    corpus = Jason.decode!(File.read!(@corpus))
    reader = Enum.find(corpus["users"], &(&1["email"] == "e2e-stats@dawarich.test"))
    stats = Enum.filter(corpus["stats"], &(&1["user_id"] == reader["id"]))

    for year <- [2023, 2024] do
      selected = stats |> Enum.filter(&(&1["year"] == year)) |> Enum.sort_by(& &1["month"])

      expected =
        Enum.find(
          corpus["digests"],
          &(&1["user_id"] == reader["id"] and &1["year"] == year and &1["period_type"] == "yearly")
        )

      assert Aggregate.year(selected) ==
               Map.take(expected, ["distance", "toponyms", "monthly_distances"])

      assert Aggregate.first(stats, year, nil) == expected["first_time_visits"]
      assert Aggregate.comparison(stats, year, nil) == expected["year_over_year"]
      assert Aggregate.all_time(stats, stats) == expected["all_time_stats"]
    end
  end

  test "monthly projection preserves actual daily values, comparisons and first visits" do
    corpus = Jason.decode!(File.read!(@corpus))
    reader = Enum.find(corpus["users"], &(&1["email"] == "e2e-stats@dawarich.test"))
    stats = Enum.filter(corpus["stats"], &(&1["user_id"] == reader["id"]))

    for digest <- corpus["digests"],
        digest["user_id"] == reader["id"],
        digest["period_type"] == "monthly" do
      stat = Enum.find(stats, &(&1["year"] == digest["year"] and &1["month"] == digest["month"]))

      assert Aggregate.month(stat) ==
               Map.take(digest, ["distance", "flight_distance", "toponyms", "monthly_distances"])

      assert Aggregate.first(stats, digest["year"], digest["month"]) ==
               digest["first_time_visits"]

      assert Aggregate.comparison(stats, digest["year"], digest["month"]) ==
               digest["year_over_year"]
    end
  end

  test "Ruby toponym empty cities and country-presence rules remain distinct" do
    stats = [
      %{
        "year" => 2024,
        "month" => 1,
        "distance" => 1,
        "toponyms" => [
          %{"country" => "Empty", "cities" => []},
          %{"country" => "No array"},
          %{"country" => "Populated", "cities" => [%{"city" => "A"}]}
        ]
      }
    ]

    assert Aggregate.year(stats)["toponyms"] == [
             %{"country" => "Populated", "cities" => [%{"city" => "A"}]},
             %{"country" => "No array", "cities" => []}
           ]

    assert Aggregate.first(stats, 2024, nil)["countries"] == ["Populated"]

    assert Aggregate.comparison(
             stats ++ [%{"year" => 2023, "month" => 1, "distance" => 1, "toponyms" => []}],
             2024,
             nil
           )["countries_change"] == 3
  end
end

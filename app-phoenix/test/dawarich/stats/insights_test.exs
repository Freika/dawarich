defmodule Dawarich.Stats.InsightsTest do
  use Dawarich.IngestCase, async: false
  import Dawarich.Test.StatsSeeds

  alias Dawarich.RailsTime
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Stats.Insights

  @now ~U[2026-09-26 12:00:00Z]

  defp json({:ok, term}), do: term |> Ruby.json() |> IO.iodata_to_binary()

  defp frame(id, year, now),
    do: RailsTime.with_zone("Europe/Berlin", fn -> Insights.frame(id, year, now) end)

  defp overview(id, year, unit, now \\ @now) do
    with {:ok, frame} <- frame(id, year, now), do: Insights.overview(id, frame, unit)
  end

  defp details(id, year) do
    with {:ok, frame} <- frame(id, year, @now), do: Insights.details(id, frame, "km")
  end

  defp seed_years(id) do
    stat!(id, %{
      year: 2024,
      month: 3,
      distance: 12_345,
      toponyms: [toponym("Germany", ["Berlin"])],
      daily_distance: %{"1" => 5000, "2" => 7345, "3" => 0}
    })

    stat!(id, %{
      year: 2024,
      month: 7,
      distance: 50_000,
      toponyms: [toponym("France", ["Paris", "Lyon"]), toponym("Germany", ["Hamburg"])],
      daily_distance: %{"14" => 50_000}
    })

    stat!(id, %{
      year: 2023,
      month: 5,
      distance: 1000,
      toponyms: [toponym("Germany", ["Berlin"])],
      daily_distance: %{"3" => 1000}
    })

    stat!(id, %{year: 2023, month: 6, distance: 1000})
  end

  defp visit!(id, name, started_at, duration, attrs \\ %{}) do
    Repo.insert_all("visits", [
      Map.merge(
        %{
          user_id: id,
          name: name,
          started_at: started_at,
          ended_at: started_at,
          duration: duration,
          status: 1,
          created_at: started_at,
          updated_at: started_at
        },
        attrs
      )
    ])
  end

  test "overview: the newest year by default, totals in km and the heatmap from the stored rows" do
    id = user!()
    seed_years(id)
    stat!(user!(), %{year: 2025, month: 1, distance: 9_999_999})

    assert json(overview(id, nil, "km")) ==
             ~s({"year":2024,"availableYears":[2024,2023],"totals":{"totalDistance":62,"distanceUnit":"km","countriesCount":2,"citiesCount":4,) <>
               ~s("countriesList":["France","Germany"],"daysTraveling":3,"biggestMonth":{"month":"July","distance":50}},) <>
               ~s("activityHeatmap":{"dailyData":{"2024-03-01":5000,"2024-03-02":7345,"2024-03-03":0,"2024-07-14":50000},) <>
               ~s("activityLevels":{"p25":7345,"p50":7345,"p75":50000,"p90":50000},"maxDistance":50000,"activeDays":3,"currentStreak":0,) <>
               ~s("longestStreak":2,"longestStreakStart":"2024-03-01","longestStreakEnd":"2024-03-02"},"planRestricted":false,"upgradeUrl":null})
  end

  test "an explicit year in miles, the first of two equal months, an empty year, and no stats at all use the local current year" do
    id = user!()
    seed_years(id)

    assert json(overview(id, 2023, "mi")) =~
             ~s("totals":{"totalDistance":1,"distanceUnit":"mi","countriesCount":1,"citiesCount":1,"countriesList":["Germany"],"daysTraveling":1,"biggestMonth":{"month":"May","distance":1}})

    assert json(overview(id, 2020, "km")) =~
             ~s({"year":2020,"availableYears":[2024,2023],"totals":{"totalDistance":0,"distanceUnit":"km","countriesCount":0,"citiesCount":0,"countriesList":[],"daysTraveling":0,"biggestMonth":null})

    assert json(overview(user!(), nil, "km", ~U[2026-12-31 23:30:00Z])) =~
             ~s({"year":2027,"availableYears":[],)
  end

  test "details: the comparison, the yearly digest's patterns in stored key order, weekly totals from monthly digests, the top five visits of the local year" do
    id = user!()
    seed_years(id)

    digest!(id, %{
      year: 2024,
      travel_patterns: %{
        "time_of_day" => %{"morning" => 10, "night" => 2, "afternoon" => 5},
        "seasonality" => nil,
        "activity_breakdown" => %{"walking" => 1}
      }
    })

    digest!(id, %{
      year: 2024,
      month: 3,
      period_type: 0,
      monthly_distances: %{"1" => 5000, "2" => 7345}
    })

    digest!(id, %{year: 2024, month: 7, period_type: 0, monthly_distances: [[14, 50_000]]})
    digest!(id, %{year: 2024, month: 8, period_type: 0, monthly_distances: %{}})

    for {name, at, duration, attrs} <- [
          {"Cafe", ~N[2024-02-01 10:00:00], 10, %{}},
          {"Cafe", ~N[2024-02-02 10:00:00], 20, %{}},
          {"Cafe", ~N[2024-02-03 10:00:00], 30, %{}},
          {"Cafe", ~N[2023-12-31 23:30:00], 40, %{}},
          {"Office", ~N[2024-03-01 09:00:00], 100, %{}},
          {"Office", ~N[2024-03-02 09:00:00], 100, %{}},
          {"Office", ~N[2024-03-03 09:00:00], 100, %{}},
          {"Office", ~N[2024-12-31 23:30:00], 100, %{}},
          {"Park", ~N[2024-04-01 12:00:00], 5, %{}},
          {"Park", ~N[2024-04-02 12:00:00], 5, %{}},
          {"Gym", ~N[2024-05-01 18:00:00], 500, %{}},
          {"Home", ~N[2024-05-02 18:00:00], 50, %{}},
          {"Library", ~N[2024-05-03 18:00:00], 40, %{}},
          {"Cafe", ~N[2024-06-01 10:00:00], 1, %{status: 2}},
          {"Cafe", ~N[2024-06-02 10:00:00], 1, %{status: 0}},
          {"Cafe", ~N[2024-06-03 10:00:00], 1, %{deleted_at: ~N[2024-06-04 00:00:00]}}
        ],
        do: visit!(id, name, at, duration, attrs)

    visit!(user!(), "Cafe", ~N[2024-02-05 10:00:00], 1)

    assert json(details(id, nil)) ==
             ~s({"year":2024,"comparison":{"previousYear":2023,"distanceChangePercent":3000,"countriesChange":1,"citiesChange":300,"daysChange":200},) <>
               ~s("travelPatterns":{"timeOfDay":{"night":2,"morning":10,"afternoon":5},"dayOfWeek":[0,0,0,0,5000,7345,50000],"seasonality":{},) <>
               ~s("activityBreakdown":{"walking":1},"topVisitedLocations":[{"name":"Cafe","visitCount":4,"totalDuration":100},) <>
               ~s({"name":"Office","visitCount":3,"totalDuration":300},{"name":"Park","visitCount":2,"totalDuration":10},) <>
               ~s({"name":"Gym","visitCount":1,"totalDuration":500},{"name":"Home","visitCount":1,"totalDuration":50}]},"planRestricted":false,"upgradeUrl":null})
  end

  test "details without a previous year or digests: a null comparison, empty patterns and seven zeros" do
    id = user!()
    stat!(id, %{year: 2024, month: 3, distance: 1000})

    assert json(details(id, 2024)) ==
             ~s({"year":2024,"comparison":null,"travelPatterns":{"timeOfDay":{},"dayOfWeek":[0,0,0,0,0,0,0],"seasonality":{},) <>
               ~s("activityBreakdown":{},"topVisitedLocations":[]},"planRestricted":false,"upgradeUrl":null})
  end

  test "weekly_pattern: Monday first, nothing for a missing month or a non-collection, Puma for an impossible day" do
    assert Insights.weekly_pattern(2024, 3, {:object, [{"4", 10}, {"10", 5}]}) ==
             {:ok, [10, 0, 0, 0, 0, 0, 5]}

    assert Insights.weekly_pattern(2024, 3, [[4, 1], [4, 2]]) == {:ok, [3, 0, 0, 0, 0, 0, 0]}

    assert {Insights.weekly_pattern(2024, nil, {:object, [{"4", 1}]}),
            Insights.weekly_pattern(2024, 3, "x"),
            Insights.weekly_pattern(2024, 3, {:object, []})} == {{:ok, []}, {:ok, []}, {:ok, []}}

    assert {:replay, _} = Insights.weekly_pattern(2024, 2, {:object, [{"30", 5}]})
  end

  test "stored shapes Rails reads differently or raises on, and top visits that tie, go to Puma" do
    string_daily = user!()
    stat!(string_daily, %{year: 2024, month: 1, distance: 1, daily_distance: "x"})
    assert {:replay, _} = overview(string_daily, 2024, "km")

    null_daily = user!()
    stat!(null_daily, %{year: 2024, month: 1, distance: 1, daily_distance: nil})
    assert {:replay, _} = overview(null_daily, 2024, "km")
    assert {:replay, _} = details(null_daily, 2024)

    tied = user!()
    stat!(tied, %{year: 2024, month: 1, distance: 1})

    for {name, day} <- [{"A", 1}, {"B", 2}],
        do: visit!(tied, name, NaiveDateTime.new!(2024, 2, day, 10, 0, 0), 10)

    assert {:replay, _} = details(tied, 2024)

    array_patterns = user!()
    stat!(array_patterns, %{year: 2024, month: 1, distance: 1})
    digest!(array_patterns, %{year: 2024, travel_patterns: [1]})
    assert {:replay, _} = details(array_patterns, 2024)

    february_30 = user!()
    stat!(february_30, %{year: 2024, month: 1, distance: 1})
    digest!(february_30, %{year: 2024, month: 2, period_type: 0, monthly_distances: %{"30" => 5}})
    assert {:replay, _} = details(february_30, 2024)
  end
end

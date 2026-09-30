defmodule Dawarich.Digests.ApiTest do
  use Dawarich.IngestCase, async: false
  import Dawarich.Test.StatsSeeds

  alias Dawarich.Digests.Api
  alias Dawarich.RailsTime
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @now ~U[2026-09-26 12:00:00Z]

  defp json({:ok, term}), do: term |> Ruby.json() |> IO.iodata_to_binary()
  defp in_zone(zone, fun), do: RailsTime.with_zone(zone, fun)

  test "index: yearly digests before the local current year, newest first, zoned createdAt, Rails' counts and the available years" do
    id = user!()

    digest!(id, %{
      year: 2023,
      distance: 5000,
      created_at: ~N[2024-01-05 11:00:00],
      toponyms: [
        toponym("Germany", ["Berlin", "Munich"]),
        %{"country" => nil, "cities" => [%{"city" => "X"}]},
        %{"country" => " ", "cities" => []}
      ]
    })

    digest!(id, %{year: 2024, created_at: ~N[2025-07-01 10:00:00.5]})
    digest!(id, %{year: 2999})
    digest!(id, %{year: 2025, month: 1, period_type: 0})
    for year <- [2022, 2023, 2024, 2026], do: stat!(id, %{year: year, month: 1, distance: 1})
    digest!(user!(), %{year: 2022})

    assert json(in_zone("Europe/Berlin", fn -> Api.index(id, @now) end)) ==
             ~s({"digests":[{"year":2024,"distance":0,"countriesCount":0,"citiesCount":0,"createdAt":"2025-07-01T12:00:00+02:00"},) <>
               ~s({"year":2023,"distance":5000,"countriesCount":1,"citiesCount":3,"createdAt":"2024-01-05T12:00:00+01:00"}],"availableYears":[2022]})
  end

  test "index: the current year follows the zone at the turn of the year, and UTC prints Z" do
    id = user!()
    digest!(id, %{year: 2025, created_at: ~N[2026-01-01 00:00:00]})
    digest!(id, %{year: 2026, created_at: ~N[2026-12-31 22:00:00]})
    at = ~U[2026-12-31 23:30:00Z]

    assert json(in_zone("UTC", fn -> Api.index(id, at) end)) =~
             ~s({"digests":[{"year":2025,"distance":0,"countriesCount":0,"citiesCount":0,"createdAt":"2026-01-01T00:00:00Z"}],)

    assert json(in_zone("Europe/Berlin", fn -> Api.index(id, at) end)) =~
             ~s({"digests":[{"year":2026,)
  end

  test "show and detail: every field, pass-through JSON in stored key order, monthly floats, the Earth text, zoned times" do
    id = user!()

    digest!(id, %{
      year: 2024,
      distance: 12_345_678,
      created_at: ~N[2025-01-02 03:04:05],
      updated_at: ~N[2025-01-02 03:04:05.678],
      toponyms: [
        toponym("Germany", ["Berlin", "Hamburg"]),
        toponym("France", []),
        %{"country" => nil, "cities" => [%{"city" => "Nowhere"}]}
      ],
      monthly_distances: %{"1" => 1000, "2" => 2500.5, "3" => "12.5km", "12" => nil, "13" => 7},
      time_spent_by_location: %{
        "countries" => [%{"name" => "Germany", "minutes" => 100}],
        "total_country_minutes" => 100
      },
      first_time_visits: %{"countries" => [], "cities" => ["Hamburg"]},
      year_over_year: %{
        "distance_change_percent" => 12.5,
        "countries_change" => 1,
        "cities_change" => -2,
        "previous_year" => 2023
      },
      all_time_stats: %{"total_countries" => 3, "total_cities" => 5, "total_distance" => 2.5e7},
      travel_patterns: %{
        "time_of_day" => %{"morning" => 2, "night" => 1},
        "seasonality" => false
      }
    })

    Repo.query!(
      "UPDATE digests SET all_time_stats = " <>
        "'{\"total_countries\": 3, \"total_cities\": 5, \"total_distance\": 25000000.0}'::jsonb " <>
        "WHERE user_id = $1 AND year = $2",
      [id, 2024]
    )

    assert {:ok, digest} = in_zone("Europe/Berlin", fn -> Api.show(id, 2024) end)
    assert NaiveDateTime.compare(digest.modified, ~N[2025-01-02 03:04:05.678]) == :eq

    zeros =
      Enum.map_join(
        ~w(april may june july august september october november december),
        ",",
        &~s("#{&1}":0.0)
      )

    assert json(Api.detail(digest, "mi")) ==
             ~s({"year":2024,"distance":{"meters":12345678,"converted":7671,"unit":"mi","comparisonText":"That's 30.8% of Earth's circumference!"},) <>
               ~s("toponyms":{"countriesCount":2,"citiesCount":3,"countries":[{"country":"Germany","cities":["Berlin","Hamburg"]},{"country":"France","cities":[]}]},) <>
               ~s("monthlyDistances":{"january":1000.0,"february":2500.5,"march":12.5,#{zeros}},) <>
               ~s("timeSpentByLocation":{"countries":[{"name":"Germany","minutes":100}],"total_country_minutes":100},) <>
               ~s("firstTimeVisits":{"cities":["Hamburg"],"countries":[]},"yearOverYear":{"distanceChangePercent":12.5,"countriesChange":1,"citiesChange":-2},) <>
               ~s("allTimeStats":{"totalCountries":3,"totalCities":5,"totalDistance":"25000000.0"},) <>
               ~s("travelPatterns":{"timeOfDay":{"night":1,"morning":2},"seasonality":{},"activityBreakdown":{}},) <>
               ~s("createdAt":"2025-01-02T04:04:05+01:00","updatedAt":"2025-01-02T04:04:05+01:00"})
  end

  test "detail of an untouched digest: zeros, nulls and empty objects, and the Moon text" do
    id = user!()

    digest!(id, %{
      year: 2023,
      distance: 400_000_000,
      created_at: ~N[2024-01-01 00:00:00],
      updated_at: ~N[2024-01-01 00:00:00]
    })

    {:ok, digest} = in_zone("UTC", fn -> Api.show(id, 2023) end)

    zeros =
      Enum.map_join(
        ~w(january february march april may june july august september october november december),
        ",",
        &~s("#{&1}":0.0)
      )

    assert json(Api.detail(digest, "km")) ==
             ~s({"year":2023,"distance":{"meters":400000000,"converted":400000,"unit":"km","comparisonText":"That's 104.1% of the distance to the Moon!"},) <>
               ~s("toponyms":{"countriesCount":0,"citiesCount":0,"countries":[]},"monthlyDistances":{#{zeros}},"timeSpentByLocation":{},) <>
               ~s("firstTimeVisits":{},"yearOverYear":null,"allTimeStats":{"totalCountries":0,"totalCities":0,"totalDistance":"0"},) <>
               ~s("travelPatterns":{"timeOfDay":{},"seasonality":{},"activityBreakdown":{}},"createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z"})
  end

  test "show: a missing year and another user's digest are :not_found; a monthly digest is not a yearly one" do
    id = user!()
    digest!(user!(), %{year: 2023})
    digest!(id, %{year: 2022, month: 5, period_type: 0})
    assert in_zone("UTC", fn -> Api.show(id, 2023) end) == :not_found
    assert in_zone("UTC", fn -> Api.show(id, 2022) end) == :not_found
  end

  test "stored shapes Rails reads differently or raises on go to Puma; the list still counts a non-array as zero" do
    id = user!()

    shown = fn attrs ->
      Repo.query!("DELETE FROM digests WHERE user_id = $1", [id])
      digest!(id, Map.merge(%{year: 2023}, attrs))
      {:ok, digest} = in_zone("UTC", fn -> Api.show(id, 2023) end)
      Api.detail(digest, "km")
    end

    for attrs <- [
          %{toponyms: [5]},
          %{toponyms: %{"country" => "x"}},
          %{toponyms: [%{"country" => 5}]},
          %{toponyms: [%{"country" => "A", "cities" => [%{"city" => %{"a" => 1}}]}]},
          %{monthly_distances: [1, 2]},
          %{monthly_distances: %{"1" => true}},
          %{year_over_year: [1]},
          %{year_over_year: 5},
          %{all_time_stats: %{"total_distance" => %{"a" => 1}}},
          %{all_time_stats: [1]},
          %{travel_patterns: "x"}
        ],
        do: assert({:replay, _} = shown.(attrs), inspect(attrs))

    Repo.query!("DELETE FROM digests WHERE user_id = $1", [id])
    digest!(id, %{year: 2023, toponyms: %{"country" => "x"}})

    assert json(in_zone("UTC", fn -> Api.index(id, @now) end)) =~
             ~s("countriesCount":0,"citiesCount":0,)

    digest!(id, %{year: 2021, toponyms: [5]})
    assert {:replay, _} = in_zone("UTC", fn -> Api.index(id, @now) end)
  end
end

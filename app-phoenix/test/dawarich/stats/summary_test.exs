defmodule Dawarich.Stats.SummaryTest do
  use Dawarich.IngestCase, async: false
  import Dawarich.Test.StatsSeeds

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.ScratchRepo
  alias Dawarich.Stats.Summary

  @now ~U[2026-09-26 12:00:00Z]
  @zero ~s("january":0,"february":0,"march":0,"april":0,"may":0,"june":0,"july":0,"august":0,"september":0,"october":0,"november":0,"december":0)

  setup do
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(phoenix.stats_point_counts))
    :ok
  end

  defp json(term), do: term |> Ruby.json() |> IO.iodata_to_binary()

  test "StatsSerializer's bytes: floored km, the counters, visited sets over sanitized toponyms, years descending, every month" do
    id = user!(%{points_count: 5})

    stat!(id, %{
      year: 2020,
      month: 1,
      distance: 1999,
      toponyms: [
        toponym("Germany", ["Berlin", "Munich"]),
        %{"country" => nil, "cities" => [%{"city" => "Nowhere"}]}
      ]
    })

    stat!(id, %{
      year: 2020,
      month: 12,
      distance: 2001,
      toponyms: [
        [toponym("France", ["Paris"])],
        %{"country" => " ", "cities" => [%{"city" => "Blank"}]},
        %{"country" => 7}
      ]
    })

    stat!(id, %{
      year: 2021,
      month: 3,
      distance: 999,
      toponyms: [
        toponym("Germany", []),
        %{"country" => "Spain", "cities" => [%{"city" => ""}, "x"]}
      ]
    })

    for n <- 1..3,
        do:
          point!(id, %{timestamp: 1_700_000_000 + n, reverse_geocoded_at: ~N[2026-01-01 00:00:00]})

    point!(id, %{timestamp: 1_700_000_100})
    other = user!()

    stat!(other, %{year: 2020, month: 1, distance: 50_000, toponyms: [toponym("Italy", ["Rome"])]})

    months_2020 =
      String.replace(@zero, ~s("january":0), ~s("january":1))
      |> String.replace(~s("december":0), ~s("december":2))

    assert json(Summary.term(id, true, @now)) ==
             ~s({"totalDistanceKm":4,"totalPointsTracked":5,"totalReverseGeocodedPoints":3,"totalCountriesVisited":2,"totalCitiesVisited":5,) <>
               ~s("yearlyStats":[{"year":2021,"totalDistanceKm":0,"totalCountriesVisited":0,"totalCitiesVisited":0,"monthlyDistanceKm":{#{@zero}}},) <>
               ~s({"year":2020,"totalDistanceKm":4,"totalCountriesVisited":2,"totalCitiesVisited":3,"monthlyDistanceKm":{#{months_2020}}}]})
  end

  test "a user without stats or points: zeros and no years" do
    id = user!()

    assert json(Summary.term(id, false, @now)) ==
             ~s({"totalDistanceKm":0,"totalPointsTracked":0,"totalReverseGeocodedPoints":0,"totalCountriesVisited":0,"totalCitiesVisited":0,"yearlyStats":[]})
  end

  test "the geocoded count is A5's one-day cache row, written through Jobs.repo()" do
    id = user!()
    point!(id, %{timestamp: 1_700_000_001, reverse_geocoded_at: ~N[2026-01-01 00:00:00]})

    assert %{"totalReverseGeocodedPoints" => 1} =
             Jason.decode!(json(Summary.term(id, true, @now)))

    point!(id, %{timestamp: 1_700_000_002, reverse_geocoded_at: ~N[2026-01-01 00:00:00]})

    assert %{"totalReverseGeocodedPoints" => 1} =
             Jason.decode!(json(Summary.term(id, true, DateTime.add(@now, 3600))))

    assert ScratchRepo.query!(
             "SELECT geocoded, without_data FROM phoenix.stats_point_counts WHERE user_id = $1",
             [
               id
             ]
           ).rows == [[1, 1]]
  end

  test "kilometres floor like Ruby's Integer#/" do
    id = user!()
    stat!(id, %{year: 2020, month: 1, distance: -1})
    assert %{"totalDistanceKm" => -1} = Jason.decode!(json(Summary.term(id, false, @now)))
  end
end

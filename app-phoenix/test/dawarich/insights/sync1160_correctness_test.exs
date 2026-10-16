defmodule Dawarich.Insights.Sync1160CorrectnessTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Accounts.Scope
  alias Dawarich.Insights.{Details.Totals, ResidencyPage}
  alias Dawarich.Stats.{Pages, Summary, Toponyms}
  alias Dawarich.Test.FrameSeeds
  import Dawarich.Test.StatsSeeds
  @now ~U[2026-10-16 12:00:00Z]

  test "country-only visits reach totals summary native lists and year places without inventing cities" do
    user = FrameSeeds.user!(91601)
    places = [toponym("France", []), toponym("France", []), toponym("Germany", ["Berlin"])]
    stat!(user.id, %{year: 2025, month: 3, toponyms: places})

    raw = [
      %{
        "year" => 2025,
        "month" => 3,
        "distance" => 0,
        "daily_distance" => [],
        "toponyms" => places
      }
    ]

    assert Totals.calculate(raw, "km").countries == 2
    assert Toponyms.countries(places) == ["France", "Germany"]
    assert Toponyms.cities(places) == ["Berlin"]

    assert {:ok, page} =
             Pages.index(Scope.for_user(user, "en"), %{}, now: @now, self_hosted: true)

    assert page.total_countries == 2
    assert page.countries_visited == ["France", "Germany"]
    assert {"France", []} in hd(page.years).places.grouped
    term = Summary.term(user.id, false, @now)

    result =
      term
      |> Dawarich.ReleaseMigrations.Effects.Support.Ruby.json()
      |> IO.iodata_to_binary()
      |> Jason.decode!()

    assert result["totalCountriesVisited"] == 2
    assert hd(result["yearlyStats"])["totalCountriesVisited"] == 2
  end

  test "previous country-only history prevents false monthly and yearly first visits" do
    history =
      for {y, m, name} <- [{2024, 12, "France"}, {2025, 1, "France"}, {2025, 2, "Germany"}],
          do: %{"year" => y, "month" => m, "toponyms" => [toponym(name, [])]}

    assert Dawarich.Digests.Toponyms.first_visits(history, 2025) == %{
             "countries" => ["Germany"],
             "cities" => []
           }

    assert Dawarich.Digests.Toponyms.first_visits(history, 2025, 1) == %{
             "countries" => [],
             "cities" => []
           }

    assert Dawarich.Digests.Toponyms.first_visits(history, 2025, 2) == %{
             "countries" => ["Germany"],
             "cities" => []
           }
  end

  test "residency ties use country name before first presence and daily ties return data" do
    user = FrameSeeds.user!(91602)

    for {id, time, name} <- [
          {916_021, ~U[2025-01-01 12:00:00Z], "Germany"},
          {916_022, ~U[2025-01-02 12:00:00Z], "France"}
        ] do
      FrameSeeds.point!(user.id, id, DateTime.to_unix(time), %{country_name: name})
    end

    assert {:ok, page} =
             ResidencyPage.load(Scope.for_user(user, "en"), %{"year" => "2025"},
               now: @now,
               self_hosted: true
             )

    assert Enum.map(page.countries, & &1.name) == ["France", "Germany"]

    FrameSeeds.point!(user.id, 916_023, DateTime.to_unix(~U[2025-01-01 13:00:00Z]), %{
      country_name: "France"
    })

    assert {:ok, window} = Dawarich.Residency.window(user.id, 2025, @now)
    assert {:ok, term} = Dawarich.Residency.term(user.id, window)

    result =
      term
      |> Dawarich.ReleaseMigrations.Effects.Support.Ruby.json()
      |> IO.iodata_to_binary()
      |> Jason.decode!()

    assert result["daily_countries"]["2025-01-01"] == "France"
    assert Enum.map(result["countries"], & &1["country_name"]) == ["France", "Germany"]
  end

  test "serializer keeps malformed cities out of yearly country totals" do
    user = FrameSeeds.user!(91607)

    stat!(user.id, %{
      year: 2025,
      month: 3,
      toponyms: [%{"country" => "France"}, %{"country" => "Germany", "cities" => []}]
    })

    result =
      Summary.term(user.id, false, @now)
      |> Dawarich.ReleaseMigrations.Effects.Support.Ruby.json()
      |> IO.iodata_to_binary()
      |> Jason.decode!()

    assert result["totalCountriesVisited"] == 2
    assert hd(result["yearlyStats"])["totalCountriesVisited"] == 1
  end
end

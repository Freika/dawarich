defmodule Dawarich.DigestsTest do
  use ExUnit.Case, async: true

  import Dawarich.Test.StatsSeeds

  alias Dawarich.{Digests, Stats}
  alias Dawarich.Test.RailsUser

  @now ~U[2026-09-26 12:00:00Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    :ok
  end

  defp user(id, attrs \\ %{}) do
    row =
      RailsUser.insert!(
        Map.merge(
          %{
            id: id,
            email: "a5s-dig-#{id}@dawarich.test",
            settings: %{"timezone" => "Europe/Berlin"}
          },
          attrs
        )
      )

    struct(Dawarich.Accounts.User, row)
  end

  test "the index lists past yearly digests newest first; the unfinished year, monthly digests and other users' stay off" do
    me = user(5701)
    other = user(5702)
    for year <- [2023, 2026, 2024], do: digest!(me.id, %{year: year, distance: year})
    digest!(me.id, %{year: 2024, month: 3, period_type: 0})
    digest!(other.id, %{year: 2022})
    index = Digests.index(me.id, Stats.context(me, @now, true))
    assert Enum.map(index.digests, & &1.year) == [2024, 2023]
  end

  test "available years are the window's stat years minus yearly digests minus the current year, newest first" do
    lite = user(5711, %{plan: 0})

    for {year, month} <- [{2024, 6}, {2025, 8}, {2025, 9}, {2026, 2}],
        do: stat!(lite.id, %{year: year, month: month})

    digest!(lite.id, %{year: 2027})
    assert Digests.index(lite.id, Stats.context(lite, @now, false)).available_years == [2025]
    full = user(5712)
    for year <- [2022, 2023, 2024, 2026], do: stat!(full.id, %{year: year, month: 5})
    for year <- [2023, 2024], do: digest!(full.id, %{year: year})
    assert Digests.index(full.id, Stats.context(full, @now, true)).available_years == [2022]
  end

  test "get normalizes the JSON columns with Rails' defaults and finds only the user's yearly row" do
    me = user(5721)

    digest!(me.id, %{
      year: 2024,
      distance: 50_000,
      toponyms: [toponym("Germany", ["Berlin"]), "junk", toponym("Czechia", ["Prague", "Brno"])],
      first_time_visits: %{"countries" => ["Czechia"]},
      time_spent_by_location: %{"countries" => [%{"name" => "Germany", "minutes" => "90"}, 5]},
      year_over_year: %{"distance_change_percent" => 150, "previous_year" => 2023},
      all_time_stats: %{"total_distance" => "70000"},
      monthly_distances: %{"10" => 5, "3" => 38_400},
      sharing_settings: %{"enabled" => true, "expiration" => "1w"}
    })

    digest!(me.id, %{year: 2023, toponyms: %{}, first_time_visits: [], all_time_stats: nil})

    d = Digests.get(me.id, 2024)
    assert Enum.map(d.toponyms, & &1["country"]) == ["Germany", "Czechia"]
    assert {Digests.countries_count(d.toponyms), Digests.cities_count(d.toponyms)} == {2, 3}
    assert {d.first_time_countries, d.first_time_cities} == {["Czechia"], []}
    assert d.top_countries == [%{"name" => "Germany", "minutes" => "90"}]
    assert d.total_minutes == 90
    assert {d.yoy_distance_change, d.previous_year} == {150, 2023}

    assert {d.total_countries_all_time, d.total_cities_all_time, d.total_distance_all_time} ==
             {0, 0, 70_000}

    assert d.monthly_distances == [{"3", 38_400}, {"10", 5}]
    assert {d.sharing_enabled, d.sharing_expiration} == {true, "1w"}

    old = Digests.get(me.id, 2023)

    assert {old.toponyms, old.first_time_countries, old.total_distance_all_time,
            old.monthly_distances} == {[], [], 0, []}

    assert Digests.get(me.id, 2022) == nil
    assert Digests.get(user(5722).id, 2024) == nil
  end
end

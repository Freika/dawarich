defmodule Dawarich.StatsTest do
  use ExUnit.Case, async: false

  import Dawarich.Test.StatsSeeds

  alias Dawarich.Stats
  alias Dawarich.Stats.Toponyms
  alias Dawarich.Test.RailsUser

  @berlin %{"timezone" => "Europe/Berlin"}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Dawarich.ScratchRepo.query!("TRUNCATE phoenix.stats_point_counts", [], log: false)
    :ok
  end

  defp user(id, attrs \\ %{}) do
    row =
      RailsUser.insert!(
        Map.merge(%{id: id, email: "a5s-stats-#{id}@dawarich.test", settings: @berlin}, attrs)
      )

    struct(Dawarich.Accounts.User, Map.put(row, :id, id))
  end

  defp ctx(user, now, self_hosted \\ false), do: Stats.context(user, now, self_hosted)

  test "a restricted user's window is inclusive of the cutoff month, older years are locked" do
    lite = user(5501, %{plan: 0})

    for {year, month} <- [{2023, 5}, {2025, 2}, {2025, 3}, {2026, 1}],
        do: stat!(lite.id, %{year: year, month: month, distance: 1000})

    now = ~U[2026-03-15 12:00:00Z]
    index = Stats.index(lite, ctx(lite, now), true, now)
    assert Enum.map(index.years, & &1.year) == [2026, 2025]
    assert Enum.map(hd(tl(index.years)).stats, & &1.month) == [3]
    assert index.locked_years == [2023]
    assert index.total_distance == 4000
  end

  test "the cutoff month follows the user's zone at the month edge" do
    now = ~U[2026-02-28 23:30:00Z]
    east = user(5511, %{plan: 0, settings: %{"timezone" => "Pacific/Kiritimati"}})
    utc = user(5512, %{plan: 0, settings: %{"timezone" => "UTC"}})
    for u <- [east, utc], do: stat!(u.id, %{year: 2025, month: 2, distance: 1000})
    assert Stats.month(east, 2025, 2, ctx(east, now)).stat == nil
    assert Stats.month(utc, 2025, 2, ctx(utc, now)).stat.distance == 1000
  end

  test "full access shows every year; totals and visited lists cover all stats; foreign rows never appear" do
    me = user(5521)
    other = user(5522)

    stat!(me.id, %{
      year: 2024,
      month: 3,
      distance: 38_400,
      toponyms: [toponym("Germany", ["Berlin"]), toponym("Czechia", ["Prague"])],
      updated_at: ~N[2024-04-01 10:00:00]
    })

    stat!(me.id, %{
      year: 2024,
      month: 4,
      distance: 12_000,
      toponyms: [toponym("Germany", ["Berlin"])],
      updated_at: ~N[2024-05-01 23:30:00]
    })

    stat!(me.id, %{
      year: 2023,
      month: 7,
      distance: 20_000,
      toponyms: [toponym("Austria", []), toponym(nil, ["Nowhere"])]
    })

    stat!(other.id, %{
      year: 2022,
      month: 1,
      distance: 99_000,
      toponyms: [toponym("France", ["Paris"])]
    })

    now = ~U[2026-09-26 12:00:00Z]
    index = Stats.index(me, ctx(me, now, true), true, now)
    assert Enum.map(index.years, & &1.year) == [2024, 2023]
    [y2024 | _] = index.years
    assert Enum.map(y2024.stats, & &1.month) == [4, 3]
    assert y2024.updated_on == ~D[2024-05-02]
    assert Enum.at(y2024.distances, 2) == 38_400 and Enum.at(y2024.distances, 0) == 0
    assert index.locked_years == []
    assert index.total_distance == 70_400
    assert index.countries_visited == ["Czechia", "Germany"]
    assert index.cities_visited == ["Berlin", "Nowhere", "Prague"]
  end

  test "the year chart covers the whole year, the cards only the window" do
    lite = user(5531, %{plan: 0})
    stat!(lite.id, %{year: 2025, month: 8, distance: 8000})
    stat!(lite.id, %{year: 2025, month: 9, distance: 9000})
    now = ~U[2026-09-26 12:00:00Z]
    year = Stats.year(lite, 2025, ctx(lite, now))
    assert Enum.slice(year.distances, 7, 2) == [8000, 9000]
    assert Enum.map(year.stats, & &1.month) == [9]
  end

  test "month: absent row is nil, previous only after January, average over the window in whole km" do
    me = user(5541)
    stat!(me.id, %{year: 2023, month: 12, distance: 5000})
    stat!(me.id, %{year: 2024, month: 1, distance: 1000})
    stat!(me.id, %{year: 2024, month: 3, distance: 38_400})
    stat!(me.id, %{year: 2024, month: 4, distance: 12_100})
    now = ~U[2026-09-26 12:00:00Z]
    c = ctx(me, now, true)
    assert Stats.month(me, 2024, 2, c).stat == nil
    assert Stats.month(me, 2024, 1, c).previous == nil
    april = Stats.month(me, 2024, 4, c)
    assert april.previous.distance == 38_400
    assert Stats.month(me, 2024, 3, c).previous == nil
    assert april.average_km == 17
    assert Stats.month(me, 2024, 2, c).average_km == 17
  end

  test "month JSON: toponyms sanitized as Stat#toponyms, daily distance defaults to no days" do
    me = user(5551)

    raw = [
      [
        %{
          "country" => "DE",
          "cities" => [%{"city" => "Berlin"}, %{"city" => " "}, "x", %{"city" => 5}]
        }
      ],
      %{"country" => 5},
      "junk",
      %{"country" => nil, "cities" => %{"city" => "Map"}}
    ]

    stat!(me.id, %{year: 2024, month: 3, distance: 1, toponyms: raw, daily_distance: nil})
    stat!(me.id, %{year: 2024, month: 4, distance: 1, daily_distance: %{}})

    stat!(me.id, %{
      year: 2024,
      month: 5,
      distance: 1,
      daily_distance: [[1, 100], [2, 0], "x", [3]]
    })

    now = ~U[2026-09-26 12:00:00Z]
    c = ctx(me, now, true)
    march = Stats.month(me, 2024, 3, c).stat

    assert march.toponyms == [
             %{"country" => "DE", "cities" => [%{"city" => "Berlin"}]},
             %{"country" => nil, "cities" => []}
           ]

    assert march.daily == []
    assert Stats.month(me, 2024, 4, c).stat.daily == []
    assert Stats.month(me, 2024, 5, c).stat.daily == [[1, 100], [2, 0]]

    assert Toponyms.visited(march.toponyms) == [
             %{"country" => "DE", "cities" => [%{"city" => "Berlin"}]}
           ]

    assert Toponyms.known_countries(march.toponyms) == 1
  end

  test "sharing settings: enabled only when exactly true" do
    me = user(5561)

    stat!(me.id, %{
      year: 2024,
      month: 3,
      distance: 1,
      sharing_settings: %{"enabled" => "true", "expiration" => "1w"},
      sharing_uuid: Ecto.UUID.dump!("00000000-0000-4000-8000-000000055610")
    })

    stat!(me.id, %{year: 2024, month: 4, distance: 1, sharing_settings: %{"enabled" => true}})
    c = ctx(me, ~U[2026-09-26 12:00:00Z], true)
    march = Stats.month(me, 2024, 3, c).stat
    assert march.sharing == %{enabled: false, expiration: "1w"}
    assert march.sharing_uuid == "00000000-0000-4000-8000-000000055610"
    assert Stats.month(me, 2024, 4, c).stat.sharing.enabled
  end

  test "geocoding is enabled by a stored provider, store_geodata follows the setting" do
    keys =
      ~w(PHOTON_API_HOST GEOAPIFY_API_KEY NOMINATIM_API_HOST LOCATIONIQ_API_KEY STORE_GEODATA)

    previous = Map.new(keys, &{&1, System.get_env(&1)})

    on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    for key <- keys, do: System.delete_env(key)

    refute Dawarich.Geocoding.Config.resolve(Dawarich.Repo).enabled
    geocoding!(false)
    config = Dawarich.Geocoding.Config.resolve(Dawarich.Repo)
    assert config.enabled
    refute config.store_geodata
  end

  test "year_places counts normalized countries with cities and every distinct city, grouped and sorted" do
    table = [{"Germany", "DE"}, {"Czechia", "CZ"}]

    stats = [
      %{
        toponyms: [
          toponym("Germany", ["Berlin"]),
          toponym("Czech Republic", ["Brno"]),
          toponym(nil, ["Nowhere"]),
          toponym("Austria", [])
        ]
      },
      %{toponyms: [toponym("Germany", ["Berlin", "Hamburg"]), toponym("Czechia", ["Prague"])]}
    ]

    places = Dawarich.Stats.Toponyms.year_places(stats, 2023, table)
    assert places.countries_count == 3
    assert places.cities_count == 5

    assert places.grouped == [
             {"Czech Republic", ["Brno"]},
             {"Czechia", ["Prague"]},
             {"Germany", ["Berlin", "Hamburg"]}
           ]

    assert places.modal_id == "countries_cities_modal_2023"
  end
end

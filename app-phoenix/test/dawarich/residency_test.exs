defmodule Dawarich.ResidencyTest do
  use Dawarich.IngestCase, async: true
  import Dawarich.Test.StatsSeeds

  alias Dawarich.{CountryNames, RailsTime, Residency}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @now ~U[2026-09-26 12:00:00Z]

  defp json({:ok, term}), do: term |> Ruby.json() |> IO.iodata_to_binary()

  defp residency(id, year, zone \\ "Europe/Berlin", now \\ @now) do
    with {:ok, window} <- RailsTime.with_zone(zone, fn -> Residency.window(id, year, now) end),
         do: Residency.term(id, window)
  end

  defp at(%DateTime{} = time), do: DateTime.to_unix(time)

  defp points!(id, rows) do
    stamp = NaiveDateTime.utc_now(:second)

    Repo.insert_all(
      "points",
      for(
        {time, country, attrs} <- rows,
        do:
          Map.merge(
            %{
              user_id: id,
              timestamp: at(time),
              country_name: country,
              created_at: stamp,
              updated_at: stamp
            },
            attrs
          )
      )
    )
  end

  test "a year in the user's zone, UTC dates, the busiest country per day, periods, percentages, ISO codes and flags" do
    id = user!()
    for year <- [2024, 2025], do: stat!(id, %{year: year, month: 1, distance: 1})

    points!(id, [
      {~U[2024-12-31 23:30:00Z], "Germany", %{}},
      {~U[2025-01-01 12:00:00Z], "Germany", %{}},
      {~U[2025-01-02 12:00:00Z], "Germany", %{}},
      {~U[2025-01-03 12:00:00Z], "Germany", %{}},
      {~U[2025-01-10 08:00:00Z], "Germany", %{}},
      {~U[2025-01-10 09:00:00Z], "Germany", %{}},
      {~U[2025-01-10 12:00:00Z], "France", %{}},
      {~U[2025-01-11 12:00:00Z], "France", %{}},
      {~U[2025-03-01 12:00:00Z], "Czechia", %{}},
      {~U[2025-03-05 12:00:00Z], "Atlantis", %{}},
      {~U[2025-03-06 12:00:00Z], "Atlantis", %{}},
      {~U[2025-03-07 12:00:00Z], "Atlantis", %{}},
      {~U[2025-02-01 12:00:00Z], "Germany", %{anomaly: true}},
      {~U[2025-02-02 12:00:00Z], "", %{}},
      {~U[2025-02-03 12:00:00Z], nil, %{}},
      {~U[2025-12-31 23:30:00Z], "Germany", %{}}
    ])

    points!(user!(), [{~U[2025-01-01 12:00:00Z], "Spain", %{}}])

    germany =
      ~s({"country_name":"Germany","iso_a2":"DE","days":5,"percentage":50.0,"year_percentage":1.4,"flag":"🇩🇪",) <>
        ~s("periods":[{"start_date":"2024-12-31","end_date":"2025-01-03","consecutive_days":4},{"start_date":"2025-01-10","end_date":"2025-01-10","consecutive_days":1}],"threshold_warning":false})

    atlantis =
      ~s({"country_name":"Atlantis","iso_a2":null,"days":3,"percentage":30.0,"year_percentage":0.8,"flag":null,) <>
        ~s("periods":[{"start_date":"2025-03-05","end_date":"2025-03-07","consecutive_days":3}],"threshold_warning":false})

    france =
      ~s({"country_name":"France","iso_a2":"FR","days":2,"percentage":20.0,"year_percentage":0.5,"flag":"🇫🇷",) <>
        ~s("periods":[{"start_date":"2025-01-10","end_date":"2025-01-11","consecutive_days":2}],"threshold_warning":false})

    czechia =
      ~s({"country_name":"Czechia","iso_a2":"CZ","days":1,"percentage":10.0,"year_percentage":0.3,"flag":"🇨🇿",) <>
        ~s("periods":[{"start_date":"2025-03-01","end_date":"2025-03-01","consecutive_days":1}],"threshold_warning":false})

    assert json(residency(id, 2025)) ==
             ~s({"year":2025,"available_years":[2024,2025],"counting_mode":"any_presence","days_in_year":365,"total_tracked_days":10,) <>
               ~s("daily_countries":{"2024-12-31":"Germany","2025-01-01":"Germany","2025-01-02":"Germany","2025-01-03":"Germany","2025-01-10":"Germany",) <>
               ~s("2025-01-11":"France","2025-03-01":"Czechia","2025-03-05":"Atlantis","2025-03-06":"Atlantis","2025-03-07":"Atlantis"},) <>
               ~s("countries":[#{germany},#{atlantis},#{france},#{czechia}]})
  end

  test "the newest stat year by default; 183 of 366 days warns, 182 does not" do
    id = user!()
    for year <- [2023, 2024], do: stat!(id, %{year: year, month: 1, distance: 1})

    germany =
      for day <- 0..182, do: {DateTime.add(~U[2024-01-01 12:00:00Z], day, :day), "Germany", %{}}

    france =
      for day <- 0..181, do: {DateTime.add(~U[2024-07-02 12:00:00Z], day, :day), "France", %{}}

    points!(id, germany ++ france)

    assert %{
             "year" => 2024,
             "days_in_year" => 366,
             "total_tracked_days" => 365,
             "countries" => [de, fr]
           } = Jason.decode!(json(residency(id, nil, "UTC")))

    assert {de["days"], de["percentage"], de["year_percentage"], de["threshold_warning"]} ==
             {183, 50.1, 50.0, true}

    assert {fr["days"], fr["percentage"], fr["year_percentage"], fr["threshold_warning"]} ==
             {182, 49.9, 49.7, false}

    assert [
             %{
               "start_date" => "2024-07-02",
               "end_date" => "2024-12-30",
               "consecutive_days" => 182
             }
           ] = fr["periods"]
  end

  test "no data: an empty year; no stats at all: the local current year" do
    id = user!()
    stat!(id, %{year: 2024, month: 1, distance: 1})

    assert json(residency(id, 2025)) =~
             ~s("days_in_year":365,"total_tracked_days":0,"daily_countries":{},"countries":[]})

    assert json(residency(user!(), nil, "Europe/Berlin", ~U[2026-12-31 23:30:00Z])) =~
             ~s({"year":2027,"available_years":[],)
  end

  test "ties Rails orders in no stated way go to Puma, and so does a default year outside 1970..2037" do
    days = user!()

    points!(days, [
      {~U[2025-01-01 12:00:00Z], "Germany", %{}},
      {~U[2025-01-02 12:00:00Z], "France", %{}}
    ])

    assert {:replay, _} = residency(days, 2025)

    counts = user!()

    points!(counts, [
      {~U[2025-01-01 10:00:00Z], "Germany", %{}},
      {~U[2025-01-01 11:00:00Z], "Germany", %{}},
      {~U[2025-01-02 10:00:00Z], "Germany", %{}},
      {~U[2025-01-01 12:00:00Z], "France", %{}},
      {~U[2025-01-01 13:00:00Z], "France", %{}}
    ])

    assert {:replay, _} = residency(counts, 2025)

    future = user!()
    stat!(future, %{year: 2045, month: 1, distance: 1})
    assert {:replay, _} = residency(future, nil)
  end

  test "CountryNames.iso_codes/1 and flag/1 follow IsoCodeMapper: exact, alias, any case, then no match" do
    assert {CountryNames.iso_codes("Germany"), CountryNames.iso_codes("Russia"),
            CountryNames.iso_codes("germany")} == {{"DE", "DEU"}, {"RU", "RUS"}, {"DE", "DEU"}}

    assert {CountryNames.iso_codes("Atlantis"), CountryNames.iso_codes(""),
            CountryNames.iso_codes(nil)} == {{nil, nil}, {nil, nil}, {nil, nil}}

    assert {CountryNames.flag("de"), CountryNames.flag("DE"), CountryNames.flag("XX"),
            CountryNames.flag(nil), CountryNames.flag("")} == {"🇩🇪", "🇩🇪", nil, nil, nil}
  end
end

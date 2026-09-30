defmodule Dawarich.CountriesAndCitiesTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.{CountriesAndCities, RailsTime}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @now ~U[2026-09-26 12:00:00Z]
  @t0 1_700_000_000
  @t1 1_700_100_000
  @t2 1_701_000_000

  defp json(term), do: term |> Ruby.json() |> IO.iodata_to_binary()

  defp points!(id, rows) do
    stamp = NaiveDateTime.utc_now(:second)

    Repo.insert_all(
      "points",
      for(row <- rows, do: Map.merge(%{user_id: id, created_at: stamp, updated_at: stamp}, row))
    )
  end

  defp seed(id) do
    {1, [%{id: germany}]} =
      Repo.insert_all(
        "countries",
        [
          %{
            name: "Germany",
            iso_a2: "DE",
            iso_a3: "DEU",
            created_at: ~N[2024-01-01 00:00:00],
            updated_at: ~N[2024-01-01 00:00:00]
          }
        ],
        returning: [:id]
      )

    points!(id, [
      %{timestamp: @t0, city: "Berlin", country_name: "Germany", country_id: germany},
      %{timestamp: @t0 + 1800, city: "Berlin", country_name: "Deutschland", country_id: germany},
      %{timestamp: @t0 + 3600, city: "Berlin", country_name: "Germany", country_id: germany},
      %{timestamp: @t0 + 4000, city: "Berlin", country_name: "Germany", velocity: "200"},
      %{timestamp: @t0 + 4100, city: "Berlin", country_name: "Germany", velocity: "200"},
      %{timestamp: @t0 + 5000, city: "Berlin", country_name: "Germany"},
      %{timestamp: @t0 + 5600, city: "Berlin", country_name: "Germany"},
      %{timestamp: @t0 + 6000, city: "Potsdam", country_name: "Germany"},
      %{timestamp: @t0 + 7000, city: "Potsdam", country_name: "Germany"},
      %{timestamp: @t1, city: "Munich", country_name: "Germany"},
      %{timestamp: @t1 + 3600, city: "Munich", country_name: "Germany"},
      %{timestamp: @t1 + 3600 + 604_801, city: "Munich", country_name: "Germany"},
      %{timestamp: @t1 + 3600 + 604_801 + 1200, city: "Munich", country_name: "Germany"},
      %{timestamp: @t2, city: "Paris", country_name: "France"},
      %{timestamp: @t2 + 3600, city: nil, country_name: "France"},
      %{timestamp: @t2 + 5000, city: "Paris", country_name: "France", velocity: "150"},
      %{timestamp: @t2 + 7200, city: "Paris", country_name: "France"},
      %{timestamp: @t2 + 10_000, city: "Lyon", country_name: "France", anomaly: true},
      %{timestamp: @t2 + 17_200, city: "Lyon", country_name: "France", anomaly: true},
      %{timestamp: 1_702_000_001, city: "Nice", country_name: "France"},
      %{timestamp: 1_702_000_005, city: "Nice", country_name: "France"}
    ])

    points!(user!(), [
      %{timestamp: @t0, city: "Rome", country_name: "Italy"},
      %{timestamp: @t0 + 7200, city: "Rome", country_name: "Italy"}
    ])
  end

  test "presence runs: flyover runs split, single flyover points do not, the bridge cap splits, country ids name the country, the threshold filters" do
    id = user!()
    seed(id)

    assert json(CountriesAndCities.term(id, {1_699_999_999, 1_702_000_000}, 60)) ==
             ~s({"data":[{"country":"Germany","cities":[{"city":"Berlin","points":5,"timestamp":#{@t0 + 5600},"stayed_for":70},) <>
               ~s({"city":"Munich","points":4,"timestamp":#{@t1 + 3600 + 604_801 + 1200},"stayed_for":80}]},) <>
               ~s({"country":"France","cities":[{"city":"Paris","points":2,"timestamp":#{@t2 + 7200},"stayed_for":120}]}]})
  end

  test "a lower min_minutes_spent_in_city keeps shorter stays; no points is an empty list" do
    id = user!()
    seed(id)

    assert json(CountriesAndCities.term(id, {1_699_999_999, 1_702_000_000}, 10)) =~
             ~s({"city":"Potsdam","points":2,"timestamp":#{@t0 + 7000},"stayed_for":16})

    assert json(CountriesAndCities.term(user!(), {0, 1}, 60)) == ~s({"data":[]})
  end

  test "range: epochs clamp to the local 1970 and 2100 midnights, texts parse in the zone, a parse landing in 2000 without \"2000\" means now" do
    assert RailsTime.with_zone("America/New_York", fn ->
             CountriesAndCities.range({:epoch, 0}, {:epoch, 9_999_999_999}, @now)
           end) == {18_000, 4_102_462_800}

    assert RailsTime.with_zone("Europe/Berlin", fn ->
             CountriesAndCities.range(
               {:text, "2024-03-01T10:00+01:00"},
               {:text, "2024-03-01"},
               @now
             )
           end) == {1_709_283_600, 1_709_247_600}

    assert RailsTime.with_zone("UTC", fn ->
             CountriesAndCities.range({:text, "2001-01-01T00:30+01:00"}, {:epoch, 5}, @now)
           end) == {DateTime.to_unix(@now), 5}
  end
end

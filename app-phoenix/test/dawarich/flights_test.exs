defmodule Dawarich.FlightsTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.{Flights, RailsTime}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @now ~U[2026-09-26 12:00:00Z]

  defp json(term), do: term |> Ruby.json() |> IO.iodata_to_binary()

  defp flights(id, filter, zone),
    do: RailsTime.with_zone(zone, fn -> Flights.term(id, filter, @now) end)

  defp ids(term),
    do: for(%{"properties" => %{"id" => id}} <- Jason.decode!(json(term))["features"], do: id)

  defp row(id, attrs) do
    stamp = NaiveDateTime.utc_now(:second)

    Map.merge(
      %{
        user_id: id,
        external_id: System.unique_integer([:positive]),
        from_code: "EDDB",
        to_code: "LFPG",
        from_name: "Berlin Brandenburg",
        to_name: "Paris CDG",
        from_lat: 52.351,
        from_lon: 13.493,
        to_lat: 49.009,
        to_lon: 2.547,
        airline_name: "Air France",
        flight_number: "AF1235",
        distance_km: 878.0,
        created_at: stamp,
        updated_at: stamp
      },
      attrs
    )
  end

  defp flight!(id, attrs) do
    {1, [%{id: flight}]} = Repo.insert_all("flights", [row(id, attrs)], returning: [:id])
    flight
  end

  test "every mappable flight of the user in departure order, undated last, times zoned with milliseconds, dates and floats" do
    id = user!()

    a =
      flight!(id, %{
        departure_time: ~N[2024-03-01 10:00:00.123999],
        arrival_time: ~N[2024-03-01 12:00:00],
        flight_date: ~D[2024-03-01],
        seat: "12A",
        seat_class: "economy"
      })

    b = flight!(id, %{departure_time: ~N[2024-02-01 08:00:00], distance_km: nil, from_name: nil})
    c = flight!(id, %{flight_date: ~D[2024-01-15]})
    flight!(id, %{departure_time: ~N[2024-01-01 00:00:00], to_lat: nil})
    flight!(user!(), %{departure_time: ~N[2024-01-01 00:00:00]})

    geometry = ~s("geometry":{"type":"LineString","coordinates":[[13.493,52.351],[2.547,49.009]]})
    common = ~s("to_code":"LFPG")

    assert json(flights(id, :none, "America/New_York")) ==
             ~s({"type":"FeatureCollection","features":[) <>
               ~s({"type":"Feature",#{geometry},"properties":{"id":#{b},"from_code":"EDDB",#{common},"from_name":null,"to_name":"Paris CDG","airline_name":"Air France","flight_number":"AF1235",) <>
               ~s("flight_date":null,"departure_time":"2024-02-01T03:00:00.000-05:00","arrival_time":null,"seat":null,"seat_class":null,"distance_km":null}},) <>
               ~s({"type":"Feature",#{geometry},"properties":{"id":#{a},"from_code":"EDDB",#{common},"from_name":"Berlin Brandenburg","to_name":"Paris CDG","airline_name":"Air France","flight_number":"AF1235",) <>
               ~s("flight_date":"2024-03-01","departure_time":"2024-03-01T05:00:00.123-05:00","arrival_time":"2024-03-01T07:00:00.000-05:00","seat":"12A","seat_class":"economy","distance_km":878.0}},) <>
               ~s({"type":"Feature",#{geometry},"properties":{"id":#{c},"from_code":"EDDB",#{common},"from_name":"Berlin Brandenburg","to_name":"Paris CDG","airline_name":"Air France","flight_number":"AF1235",) <>
               ~s("flight_date":"2024-01-15","departure_time":null,"arrival_time":null,"seat":null,"seat_class":null,"distance_km":878.0}}]})
  end

  test "a range keeps departures inside it and undated flights whose date lies within the range's local dates" do
    id = user!()
    x = flight!(id, %{departure_time: ~N[2024-03-01 00:30:00]})
    flight!(id, %{departure_time: ~N[2024-02-29 22:30:00]})
    z = flight!(id, %{flight_date: ~D[2024-03-01]})
    flight!(id, %{flight_date: ~D[2024-02-29]})
    v = flight!(id, %{departure_time: ~N[2024-03-31 21:59:59]})
    flight!(id, %{departure_time: ~N[2024-03-31 22:00:00]})

    assert ids(flights(id, {"2024-03-01", "2024-03-31T23:59:59+02:00"}, "Europe/Berlin")) == [
             x,
             v,
             z
           ]
  end

  test "the range's text cast is parsed in the session zone, not UTC" do
    id = user!()
    x = flight!(id, %{departure_time: ~N[2024-02-29 23:30:00]})

    assert ids(flights(id, {"2024-03-01", nil}, "Europe/Berlin")) == [x]
    assert ids(flights(id, {"2024-03-01", nil}, "UTC")) == []
  end

  test "one open side: the start falls back to the epoch, the end to now" do
    id = user!()
    early = flight!(id, %{departure_time: ~N[2023-06-01 10:00:00]})
    undated = flight!(id, %{flight_date: ~D[1999-05-05]})
    flight!(id, %{departure_time: ~N[2027-01-01 10:00:00]})
    flight!(id, %{flight_date: ~D[2027-01-01]})
    mid = flight!(id, %{departure_time: ~N[2024-06-01 10:00:00]})

    assert ids(flights(id, {nil, "2024-01-31"}, "Europe/Berlin")) == [early, undated]
    assert ids(flights(id, {"2024-01-01", nil}, "Europe/Berlin")) == [mid]
  end

  test "at most 2000 flights, the earliest departures" do
    id = user!()

    Repo.insert_all(
      "flights",
      for(
        n <- 1..2001,
        do: row(id, %{departure_time: NaiveDateTime.add(~N[2024-01-01 00:00:00], n, :minute)})
      )
    )

    features = Jason.decode!(json(flights(id, :none, "UTC")))["features"]

    assert {length(features), List.last(features)["properties"]["departure_time"]} ==
             {2000, "2024-01-02T09:20:00.000Z"}
  end
end

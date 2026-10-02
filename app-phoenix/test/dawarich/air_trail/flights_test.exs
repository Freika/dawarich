defmodule Dawarich.AirTrail.FlightsTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  import Dawarich.AirTrailStub, only: [flight: 0, flight: 1]

  alias Dawarich.AirTrail.Flights

  @berlin "Europe/Berlin"

  setup do
    rows("TRUNCATE public.flights, public.notifications RESTART IDENTITY CASCADE")

    settings = %{
      "timezone" => "Europe/Berlin",
      "airtrail_url" => "https://airtrail.example.test",
      "airtrail_api_key" => "k"
    }

    [[user_id]] =
      rows(
        "INSERT INTO users (email, settings, created_at, updated_at) VALUES ('w4-air@example.test', $1, now(), now()) RETURNING id",
        [settings]
      )

    %{user_id: user_id}
  end

  defp store!(user_id, flights, time_zone \\ @berlin),
    do: :ok = Flights.store(ScratchRepo, user_id, flights, Ecto.UUID.generate(), time_zone)

  defp column(user_id, name) do
    rows("SELECT #{name} FROM flights WHERE user_id = $1 ORDER BY external_id", [user_id])
    |> List.flatten()
  end

  defp second(%NaiveDateTime{} = time), do: NaiveDateTime.truncate(time, :second)
  defp second(nil), do: nil

  test "maps the Rails fixture exactly", %{user_id: user_id} do
    input = flight()
    assert store!(user_id, [input]) == :ok

    assert [
             [
               "EDDB",
               49.009,
               "AF",
               "window",
               "economy",
               "F-GKXA",
               ~D[2026-04-20],
               "day",
               854.9,
               departure,
               raw
             ]
           ] =
             rows(
               "SELECT from_code, to_lat, airline_iata, seat, seat_class, aircraft_reg, flight_date, date_precision, distance_km, departure_time, raw FROM flights WHERE user_id = $1",
               [user_id]
             )

    assert second(departure) == ~N[2026-04-20 10:00:00]
    assert raw == input
  end

  test "raw keeps Rails' float text while the coordinate columns keep the full double", %{
    user_id: user_id
  } do
    from = Map.put(flight()["from"], "lat", 52.520008000000004)
    store!(user_id, [flight(%{"from" => from, "duration" => 7200.0})])

    assert rows(
             "SELECT from_lat, raw->'from'->>'lat', raw->>'duration' FROM flights WHERE user_id = $1",
             [user_id]
           ) == [[52.520008000000004, "52.520008", "7200.0"]]
  end

  test "scheduled times stand in for missing actual times", %{user_id: user_id} do
    store!(user_id, [
      flight(%{"departure" => nil, "departureScheduled" => "2026-04-20T10:00:00.000+00:00"})
    ])

    assert Enum.map(column(user_id, "departure_time"), &second/1) == [~N[2026-04-20 10:00:00]]
  end

  test "an offset-less time is read in TIME_ZONE and stored as UTC", %{user_id: user_id} do
    store!(user_id, [flight(%{"departure" => "2026-04-20T12:00:00"})], @berlin)

    assert Enum.map(column(user_id, "departure_time"), &second/1) == [~N[2026-04-20 10:00:00]]
  end

  test "a non-ISO time is NULL", %{user_id: user_id} do
    store!(user_id, [flight(%{"departure" => "April 20"})])

    assert column(user_id, "departure_time") == [nil]
  end

  test "updates by external_id and deletes flights AirTrail no longer returns", %{
    user_id: user_id
  } do
    rows(
      "INSERT INTO flights (user_id, external_id, flight_number, created_at, updated_at) VALUES ($1, 1, 'OLD', now(), now()), ($1, 2, 'GONE', now(), now())",
      [user_id]
    )

    store!(user_id, [flight()])

    assert rows("SELECT external_id, flight_number FROM flights WHERE user_id = $1", [user_id]) ==
             [[1, "AF1235"]]
  end

  test "keeps updated_at when nothing changed", %{user_id: user_id} do
    store!(user_id, [flight()])
    [before] = column(user_id, "updated_at")

    store!(user_id, [flight()])

    assert column(user_id, "updated_at") == [before]
  end

  test "the last duplicate id in a payload wins", %{user_id: user_id} do
    store!(user_id, [flight(%{"note" => "first"}), flight(%{"note" => "second"})])

    assert column(user_id, "note") == ["second"]
  end

  test "an empty payload deletes every flight", %{user_id: user_id} do
    store!(user_id, [flight(), flight(%{"id" => 2})])

    store!(user_id, [])

    assert column(user_id, "id") == []
  end

  test "writes airtrail_last_synced_at in Ruby's iso8601 shape", %{user_id: user_id} do
    synced_at = fn ->
      [[value]] =
        rows("SELECT settings->>'airtrail_last_synced_at' FROM users WHERE id = $1", [user_id])

      value
    end

    store!(user_id, [flight()], "Europe/Berlin")
    assert synced_at.() =~ ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+0[12]:00\z/

    store!(user_id, [flight()], "Etc/UTC")
    assert synced_at.() =~ ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/
  end

  test "commits the flights, the stats command and the processed marker together", %{
    user_id: user_id
  } do
    rows(
      "INSERT INTO flights (user_id, external_id, flight_date, departure_time, created_at, updated_at) VALUES ($1, 10, '2026-03-10', '2026-03-10 08:00:00', now(), now()), ($1, 11, NULL, '2026-02-01 12:00:00', now(), now())",
      [user_id]
    )

    event_id = Ecto.UUID.generate()
    assert Flights.store(ScratchRepo, user_id, [flight()], event_id, @berlin) == :ok

    assert column(user_id, "external_id") == [1]

    epoch = DateTime.to_unix(~U[2026-02-01 12:00:00Z])

    assert rows("SELECT kind, payload FROM phoenix.rails_commands") == [
             [
               "airtrail_stats",
               %{"user_id" => user_id, "months" => [[2026, 3]], "departure_epochs" => [epoch]}
             ]
           ]

    assert rows("SELECT handler FROM phoenix.processed_commands WHERE event_id = $1", [
             Ecto.UUID.dump!(event_id)
           ]) == [["imports.airtrail_flights"]]
  end

  test "departure epochs round down, so a flight just before midnight keeps its month", %{
    user_id: user_id
  } do
    rows(
      "INSERT INTO flights (user_id, external_id, departure_time, created_at, updated_at) VALUES ($1, 11, '2026-02-28 22:59:59.6', now(), now())",
      [user_id]
    )

    store!(user_id, [])

    assert rows("SELECT payload->'departure_epochs' FROM phoenix.rails_commands") == [
             [[DateTime.to_unix(~U[2026-02-28 22:59:59Z])]]
           ]
  end

  test "rolls everything back when the transaction fails", %{user_id: user_id} do
    rows(
      "INSERT INTO flights (user_id, external_id, flight_number, created_at, updated_at) VALUES ($1, 2, 'KEPT', now(), now())",
      [user_id]
    )

    event_id = Ecto.UUID.generate()

    assert Flights.store(ScratchRepo, user_id, [flight(%{"id" => nil})], event_id, @berlin) ==
             {:error, {:store_failed, :not_null_violation}}

    assert rows("SELECT external_id, flight_number FROM flights WHERE user_id = $1", [user_id]) ==
             [[2, "KEPT"]]

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.processed_commands") == [[0]]

    assert rows("SELECT settings ? 'airtrail_last_synced_at' FROM users WHERE id = $1", [user_id]) ==
             [[false]]
  end

  test "distance_km mirrors Ruby for integer coordinates and is nil for non-numbers" do
    assert Flights.distance_km(%{
             "from" => %{"lat" => 52, "lon" => 13},
             "to" => %{"lat" => 49, "lon" => 2}
           }) == 845.4

    assert Flights.distance_km(%{
             "from" => %{"lat" => "52", "lon" => 13},
             "to" => %{"lat" => 49, "lon" => 2}
           }) == nil
  end
end

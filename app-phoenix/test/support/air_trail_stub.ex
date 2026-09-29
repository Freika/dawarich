defmodule Dawarich.AirTrailStub do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def start(test_pid, status, body), do: serve({test_pid, status, body})

  def redirect(location), do: serve({:redirect, location})

  defp serve(opts) do
    pid =
      ExUnit.Callbacks.start_supervised!(
        {Bandit, plug: {__MODULE__, opts}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}"
  end

  def flight(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => 1,
        "date" => "2026-04-20",
        "datePrecision" => "day",
        "departure" => "2026-04-20T10:00:00.000+00:00",
        "arrival" => "2026-04-20T12:00:00.000+00:00",
        "departureScheduled" => nil,
        "arrivalScheduled" => nil,
        "flightNumber" => "AF1235",
        "aircraftReg" => "F-GKXA",
        "note" => nil,
        "duration" => 7200,
        "from" => %{
          "icao" => "EDDB",
          "iata" => "BER",
          "lat" => 52.351,
          "lon" => 13.493,
          "name" => "Berlin"
        },
        "to" => %{
          "icao" => "LFPG",
          "iata" => "CDG",
          "lat" => 49.009,
          "lon" => 2.547,
          "name" => "Paris"
        },
        "airline" => %{"name" => "Air France", "iata" => "AF"},
        "aircraft" => %{"name" => "A320"},
        "seats" => [%{"seat" => "window", "seatNumber" => "14A", "seatClass" => "economy"}]
      },
      overrides
    )
  end

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, {:redirect, location}),
    do: conn |> put_resp_header("location", location) |> send_resp(302, "")

  def call(conn, {test_pid, status, body}) do
    send(
      test_pid,
      {:airtrail_request, conn.request_path, conn.query_string,
       get_req_header(conn, "authorization")}
    )

    conn |> put_resp_content_type("application/json") |> send_resp(status, body)
  end
end

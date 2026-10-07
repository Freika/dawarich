defmodule DawarichWeb.SpatialReadsRegressionTest do
  use Dawarich.DataCase, async: false
  alias Dawarich.MapApi.Hexagons
  alias DawarichWeb.Api.HexagonsController

  setup do
    previous = System.get_env("TIME_ZONE")
    System.put_env("TIME_ZONE", "Etc/UTC")

    on_exit(fn ->
      if previous, do: System.put_env("TIME_ZONE", previous), else: System.delete_env("TIME_ZONE")
    end)

    fixture =
      File.read!("test/fixtures/a12f2c/closure.json") |> Jason.decode!() |> Map.fetch!("hexagons")

    for table <- ~w(users stats) do
      if fixture["setup"][table],
        do: Dawarich.Test.ApiGolden.insert!(table, fixture["setup"][table])
    end

    Repo.query!(
      "UPDATE users SET settings=jsonb_build_object('timezone','Europe/Berlin') WHERE id=810001"
    )

    Repo.query!("DELETE FROM points WHERE user_id=810001")
    uuid = "00000000-0000-0000-0000-000000000001"

    Repo.query!(
      "UPDATE stats SET sharing_uuid=$1::text::uuid,sharing_settings='{\"enabled\":true}' WHERE id=780001",
      [uuid]
    )

    user = %{id: 810_001, timezone: "Europe/Berlin", plan: 1, active_until: nil}
    {:ok, user: user, params: %{"uuid" => uuid}}
  end

  @tag :spatial_month
  test "public monthly bounds use the Rails request zone with inclusive month edges and DST", %{
    user: user,
    params: params
  } do
    cases = [
      {nil, "Etc/UTC", 1, "2025-01-01T00:00:00Z", "2025-01-31T23:59:59Z"},
      {nil, "Pacific/Kiritimati", 1, "2024-12-31T10:00:00Z", "2025-01-31T09:59:59Z"},
      {nil, "Pacific/Pago_Pago", 1, "2025-01-01T11:00:00Z", "2025-02-01T10:59:59Z"},
      {%{user | timezone: nil}, "Etc/UTC", 1, "2025-01-01T00:00:00Z", "2025-01-31T23:59:59Z"},
      {%{user | timezone: "Invalid/Zone"}, "Etc/UTC", 1, "2025-01-01T00:00:00Z",
       "2025-01-31T23:59:59Z"},
      {user, "Europe/Berlin", 1, "2024-12-31T23:00:00Z", "2025-01-31T22:59:59Z"},
      {%{user | timezone: "Pacific/Kiritimati"}, "Pacific/Kiritimati", 1, "2024-12-31T10:00:00Z",
       "2025-01-31T09:59:59Z"},
      {%{user | timezone: "Pacific/Pago_Pago"}, "Pacific/Pago_Pago", 1, "2025-01-01T11:00:00Z",
       "2025-02-01T10:59:59Z"},
      {user, "Europe/Berlin", 3, "2025-02-28T23:00:00Z", "2025-03-31T21:59:59Z"},
      {user, "Europe/Berlin", 10, "2025-09-30T22:00:00Z", "2025-10-31T22:59:59Z"},
      {%{user | timezone: "America/New_York"}, "America/New_York", 3, "2025-03-01T05:00:00Z",
       "2025-04-01T03:59:59Z"}
    ]

    for {actor, zone, month, from, to} <- cases do
      System.put_env("TIME_ZONE", if(is_nil(actor), do: zone, else: "Etc/UTC"))
      Repo.query!("DELETE FROM points WHERE user_id=$1", [user.id])
      Repo.query!("UPDATE stats SET month=$1 WHERE id=780001", [month])
      first = epoch(from)
      last = epoch(to)

      for {stamp, lng} <- [{first - 1, 11}, {first, 13}, {last, 14}, {last + 1, 16}],
          do: point(user.id, stamp, lng)

      for robust <- ["false", "true"] do
        response =
          HexagonsController.call(conn(actor, Map.put(params, "robust", robust)), :bounds)

        assert response.status == 200, zone

        assert Jason.decode!(response.resp_body) == %{
                 "point_count" => 2,
                 "min_lat" => 52.0,
                 "max_lat" => 52.0,
                 "min_lng" => 13.0,
                 "max_lng" => 14.0
               },
               zone
      end
    end
  end

  @tag :spatial_timeline
  test "shared timeline points keep owner local day boundaries across extreme zones and DST", %{
    user: user
  } do
    for {zone, from, to} <- [
          {"Pacific/Kiritimati", "2024-12-31T10:00:00Z", "2025-01-01T09:59:59Z"},
          {"Pacific/Pago_Pago", "2025-01-01T11:00:00Z", "2025-01-02T10:59:59Z"},
          {"Europe/Berlin", "2025-03-29T23:00:00Z", "2025-03-30T21:59:59Z"},
          {"Europe/Berlin", "2025-10-25T22:00:00Z", "2025-10-26T22:59:59Z"}
        ] do
      Repo.query!("DELETE FROM points WHERE user_id=$1", [user.id])

      Repo.query!(
        "UPDATE users SET settings=jsonb_build_object('timezone',$2::text) WHERE id=$1",
        [user.id, zone]
      )

      first = epoch(from)
      last = epoch(to)

      date =
        if String.contains?(from, "03-29"),
          do: "2025-03-30",
          else: if(String.contains?(from, "10-25"), do: "2025-10-26", else: "2025-01-01")

      for stamp <- [first - 1, first, last, last + 1], do: point(user.id, stamp, 13)

      link = %{
        type: "timeline",
        user_id: user.id,
        settings: %{"start_date" => date, "end_date" => date}
      }

      assert {:ok, [[13.0, 52.0, ^first], [13.0, 52.0, ^last]]} =
               Dawarich.SharedApi.Points.index(link)
    end

    link = %{
      type: "timeline",
      user_id: user.id,
      settings: %{"start_date" => "March 30, 2025", "end_date" => "March 30, 2025"}
    }

    Repo.query!("UPDATE users SET settings='{\"timezone\":\"Europe/Berlin\"}' WHERE id=$1", [
      user.id
    ])

    Repo.query!("DELETE FROM points WHERE user_id=$1", [user.id])
    point(user.id, epoch("2025-03-30T12:00:00Z"), 13)
    assert {:ok, [[13.0, 52.0, _]]} = Dawarich.SharedApi.Points.index(link)
  end

  @tag :spatial_h3
  test "every valid Rails H3 boundary including pentagonal descendants and face crossings is returned",
       %{params: params} do
    goldens = File.read!("test/fixtures/spatial_h3_boundaries.json") |> Jason.decode!()

    for {index, expected} <- goldens do
      actual = Dawarich.MapApi.Hexagons.Boundary.polygon(index)["coordinates"] |> hd()
      assert length(actual) == length(expected), index

      for {[lng, lat], [want_lng, want_lat]} <- Enum.zip(actual, expected) do
        assert_in_delta lng, want_lng, 1.0e-10, index
        assert_in_delta lat, want_lat, 1.0e-10, index
      end
    end

    cells =
      for index <- ["8808800001fffff", "8808000001fffff"],
          do: [index, 1, 1_735_689_600, 1_735_689_600]

    Repo.query!("UPDATE stats SET h3_hex_ids=$1::text::jsonb WHERE id=780001", [
      Jason.encode!(cells)
    ])

    assert {:ok, %{"features" => features}} = Hexagons.fetch(nil, params)
    assert length(features) == 2
  end

  @tag :spatial_dates
  test "hexagons accept Rails Date.parse formats without discarding valid monthly history", %{
    user: user
  } do
    oracle = File.read!("test/fixtures/spatial_date_parsing.json") |> Jason.decode!()

    for {text, expected} <- oracle do
      actual =
        case Dawarich.MapApi.RailsDate.parse(text) do
          {:ok, date} -> Date.to_iso8601(date)
          _ -> nil
        end

      assert actual == expected, text
    end

    today = Date.utc_today()
    assert {:ok, date} = Dawarich.MapApi.RailsDate.parse("January")
    assert date == Date.new!(today.year, 1, 1)
    assert {:ok, date} = Dawarich.MapApi.RailsDate.parse("Wed")
    assert date == Date.add(today, 3 - rem(Date.day_of_week(today), 7))

    for date <- [
          "January 1, 2025",
          "1 Jan 2025",
          "01-Jan-2025",
          "2025/01/01",
          "2025.01.01",
          "20250101",
          "2025-001",
          "2025-W01-3",
          "Wed, 01 Jan 2025 23:00:00 -1100",
          "2025-01-01T23:00:00-11:00",
          "25/1/1"
        ] do
      assert {:ok, %{"features" => [_]}} = Hexagons.fetch(user, %{"start_date" => date}), date
    end

    for date <- ["bad", "2025-02-30"] do
      assert {:ok, %{"features" => []}} = Hexagons.fetch(user, %{"start_date" => date})
    end
  end

  @tag :spatial_empty
  test "empty exact and robust bounds retain the Rails zero point count payload", %{user: user} do
    for robust <- ["false", "true"] do
      response =
        HexagonsController.call(
          conn(user, %{
            "start_date" => "2030-01-01",
            "end_date" => "2030-01-02",
            "robust" => robust
          }),
          :bounds
        )

      assert response.status == 404

      assert Jason.decode!(response.resp_body) == %{
               "error" => "No data found for the specified date range",
               "point_count" => 0
             }
    end
  end

  defp epoch(text), do: text |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_unix()

  defp point(id, stamp, lng),
    do:
      Repo.query!(
        "INSERT INTO points(user_id,timestamp,lonlat,anomaly,created_at,updated_at) VALUES($1,$2,ST_SetSRID(ST_MakePoint($3,52),4326),false,NOW(),NOW())",
        [id, stamp, lng / 1]
      )

  defp conn(user, params) do
    Plug.Test.conn(:get, "/api/v1/maps/hexagons/bounds")
    |> Plug.Conn.assign(:api_user, user)
    |> Plug.Conn.assign(:api_params, params)
    |> Plug.Conn.assign(:api_started, System.monotonic_time())
    |> Plug.Conn.assign(:api_headers, [])
    |> Plug.Conn.assign(:api_request_id, "synthetic")
    |> Plug.Conn.assign(:api_tag, "spatial")
    |> Plug.Conn.assign(:api_vary, false)
    |> Plug.Conn.assign(:api_if_none_match, nil)
  end
end

defmodule DawarichWeb.MapNavigationTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Repo, RailsTime}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    user =
      RailsUser.insert!(%{
        id: 891_001,
        email: "map-navigation@example.invalid",
        api_key: "synthetic-map-navigation",
        settings: %{"timezone" => "Europe/Berlin", "onboarding_completed" => true}
      })

    %{user: user}
  end

  @tag :sa_g44_map_navigation
  test "native map date search Turbo envelopes remount maps tracks replay studios and digest controls",
       %{user: user} do
    for route <- ["/map", "/map/v2"],
        range <- [
          "start_at=2020-01-01T00%3A00&end_at=2020-01-01T23%3A59",
          "start_at=2024-10-14T00%3A00&end_at=2024-10-14T23%3A59"
        ] do
      conn =
        RailsUser.signed_in(user.id)
        |> Map.put(:request_path, route)
        |> Map.put(:path_info, String.split(route, "/", trim: true))
        |> Map.put(:query_string, range)
        |> put_req_header("accept", "text/html, application/xhtml+xml")
        |> put_req_header("x-turbo-request-id", "synthetic-map-visit")
        |> Endpoint.call(Endpoint.init([]))

      assert conn.status == 200
      assert conn.resp_body =~ ~s(id="map-shell")
      refute conn.resp_body =~ "turbo-visit-control"
    end

    {output, status} =
      System.cmd("node", ["--experimental-vm-modules", "test/client/turbo_navigation_test.mjs"],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  @tag :sa_g44_map_timestamp
  test "monthly stats points accept local timestamps and preserve the reader timezone", %{
    user: user
  } do
    from = "2024-03-01T00:00:00"
    to = "2024-03-31T23:59:59"
    stamp = 1_709_247_600

    Repo.query!(
      "INSERT INTO points (id,user_id,timestamp,lonlat,created_at,updated_at) VALUES (891001,$1,$2,'SRID=4326;POINT(13 52)',now(),now())",
      [user.id, stamp]
    )

    for {id, at} <- [{891_002, stamp - 1}, {891_003, 1_711_922_400}] do
      Repo.query!(
        "INSERT INTO points (id,user_id,timestamp,lonlat,created_at,updated_at) VALUES ($1,$2,$3,'SRID=4326;POINT(13 52)',now(),now())",
        [id, user.id, at]
      )
    end

    conn =
      RailsUser.signed_in(user.id)
      |> Map.put(:request_path, "/api/v1/points")
      |> Map.put(:path_info, ~w(api v1 points))
      |> Map.put(:query_string, URI.encode_query(%{"start_at" => from, "end_at" => to}))
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer synthetic-map-navigation")
      |> Endpoint.call(Endpoint.init([]))

    assert conn.status == 200
    assert Enum.map(Jason.decode!(conn.resp_body), & &1["id"]) == [891_001]

    RailsTime.with_zone("Europe/Berlin", fn ->
      assert Dawarich.MapApi.Params.safe_range(from, to, ~U[2026-10-08 00:00:00Z]) ==
               {:ok, {stamp, 1_711_922_399}}
    end)

    for invalid <- ["2024-02-30T00:00:00", "2024-03-01T24:00:00", "2024-03-01T10:60:00"] do
      assert {:replay, _} = DawarichWeb.Api.Params.timestamp(invalid)
    end
  end
end

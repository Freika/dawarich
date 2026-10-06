defmodule DawarichWeb.HealthEndpointTest do
  use Dawarich.IngestCase, async: false

  setup do
    saved = Map.new(~w(SELF_HOSTED DAWARICH_RAILS_SLICES), &{&1, System.get_env(&1)})
    routes = Application.get_env(:dawarich, :rails_routes)
    Application.put_env(:dawarich, :rails_routes, [])
    System.delete_env("DAWARICH_RAILS_SLICES")
    Dawarich.Jobs.Health.reset()

    on_exit(fn ->
      Dawarich.Jobs.Health.reset()
      Application.put_env(:dawarich, :rails_routes, routes)

      Enum.each(saved, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)
  end

  test "health is native on self hosted and Cloud without private API authentication" do
    route =
      Phoenix.Router.route_info(
        DawarichWeb.Router,
        "GET",
        "/api/v1/health",
        "staging.dawarich.app"
      )

    assert route.rails_key == "health"
    refute Map.has_key?(route, :slice)

    for mode <- ~w(true false) do
      System.put_env("SELF_HOSTED", mode)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("x-forwarded-proto", "https")
        |> Phoenix.ConnTest.dispatch(DawarichWeb.Endpoint, :get, "/api/v1/health")

      assert conn.status == 200

      assert Jason.decode!(conn.resp_body) == %{
               "status" => "ok",
               "phoenix" => %{"status" => "unknown", "alarm" => false}
             }

      assert Plug.Conn.get_resp_header(conn, "x-dawarich-response") == ["Hey, I'm alive!"]
    end
  end
end

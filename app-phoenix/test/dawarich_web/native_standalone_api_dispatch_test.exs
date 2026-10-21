defmodule DawarichWeb.NativeStandaloneApiDispatchTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.Api

  @matrix [
    {"POST", "/api/v1/recalculations", Api.RecalculationsController, :create, true},
    {"GET", "/api/v1/settings/mobile", Api.MobileSettingsController, :show, false},
    {"PATCH", "/api/v1/settings/mobile", Api.MobileSettingsController, :update, true},
    {"GET", "/api/v1/areas", Api.AreasController, :index, false},
    {"POST", "/api/v1/areas", Api.AreasController, :create, false},
    {"PATCH", "/api/v1/settings", Api.SettingsController, :update, true},
    {"GET", "/api/v1/timeline", Api.TimelineController, :index, false},
    {"GET", "/api/v1/maps/hexagons", Api.HexagonsController, :index, false},
    {"PATCH", "/api/v1/points/0/position", Api.PointPositionsController, :update, true},
    {"GET", "/api/v1/areas/0", Api.AreasController, :show, false},
    {"PATCH", "/api/v1/areas/0", Api.AreasController, :update, false},
    {"PUT", "/api/v1/areas/0", Api.AreasController, :update, false},
    {"DELETE", "/api/v1/areas/0", Api.AreasController, :destroy, false},
    {"GET", "/api/v1/demo_data", Api.DemoDataController, :show, true},
    {"HEAD", "/api/v1/demo_data", Api.DemoDataController, :show, true},
    {"POST", "/api/v1/demo_data", Api.DemoDataController, :create, true},
    {"DELETE", "/api/v1/demo_data", Api.DemoDataController, :destroy, true},
    {"POST", "/api/v1/digests", Api.DigestWritesController, :create, true},
    {"DELETE", "/api/v1/digests/2024", Api.DigestWritesController, :destroy, true}
  ]
  @form "application/x-www-form-urlencoded"

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL), &{&1, System.get_env(&1)})
    limits = Application.get_env(:dawarich, :api_body_limits)
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true", "FORCE_SSL" => "false"})

    on_exit(fn ->
      Application.put_env(:dawarich, :api_body_limits, limits)

      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    [actor, inactive] =
      for label <- ~w(actor inactive) do
        RailsUser.insert!(%{
          id: System.unique_integer([:positive]),
          email: "native-dispatch-#{label}-#{Ecto.UUID.generate()}@example.invalid",
          api_key: Ecto.UUID.generate(),
          settings: %{"timezone" => "UTC", "locale" => "de"}
        })
      end

    Repo.query!("UPDATE users SET status=0 WHERE id=$1", [inactive.id])
    %{actor: actor, inactive: inactive}
  end

  test "all standalone API endpoints dispatch directly without ownership fallback", c do
    refute Code.ensure_loaded?(DawarichWeb.StandaloneRoutes)

    for {method, path, handler, action, active} <- @matrix do
      lookup = if method == "HEAD", do: "GET", else: method
      segments = String.split(path, "/", trim: true)

      assert %{plug: ^handler, plug_opts: ^action} =
               Phoenix.Router.route_info(DawarichWeb.Router, lookup, segments, "www.example.com"),
             "#{method} #{path}"

      anonymous = request(nil, method, path)
      assert anonymous.status == 401, "#{method} #{path}"
      assert anonymous.resp_body in ["", "{\"error\":\"API key is missing\"}"]

      inactive = request(c.inactive, method, path)

      if active,
        do: assert(inactive.status == 401, "#{method} #{path}"),
        else: assert(inactive.status not in [401, 422], "#{method} #{path}")
    end
  end

  test "native API HEAD preserves source status headers and rate method without body", c do
    get = request(c.actor, "GET", "/api/v1/demo_data")
    head = request(c.actor, "HEAD", "/api/v1/demo_data")

    assert get.status == 200
    assert Jason.decode!(get.resp_body) == %{"exists" => false}
    assert head.status == 200
    assert head.resp_body == ""
    assert stable_headers(head) == stable_headers(get)
    assert DawarichWeb.RateLimit.Request.facts(head, true).method == "HEAD"
    assert DawarichWeb.RateLimit.Request.facts(get, true).method == "GET"

    for path <- ~w(/api/v1/areas /api/v1/settings/mobile) do
      refused = request(c.actor, "HEAD", path)
      assert {refused.status, refused.resp_body} == {404, ""}, path
    end
  end

  test "native chunked request limits reject before side effects", c do
    Application.put_env(:dawarich, :api_body_limits, json: 4_096, multipart: 16_384)

    oversized =
      chunked(c.actor, %{
        "settings" => %{"timezone" => "Europe/Berlin"},
        "padding" => String.duplicate("x", 6_000)
      })

    assert oversized.status == 413

    assert Jason.decode!(oversized.resp_body) == %{
             "status" => 413,
             "error" => "Content Too Large"
           }

    assert timezone(c.actor) == "UTC"

    accepted = chunked(c.actor, %{"settings" => %{"timezone" => "Europe/Berlin"}})
    assert accepted.status == 200
    assert timezone(c.actor) == "Europe/Berlin"
  end

  test "promoted API writes honor POST method overrides like Rails", c do
    Dawarich.Jobs.Ownership.put!(Repo, "command:areas.relabel_visits", :oban)
    area = %{"area" => %{"name" => "Zone", "latitude" => 52, "longitude" => 13, "radius" => 100}}

    deleted =
      c.actor
      |> post("/api/v1/areas", Jason.encode!(area), "application/json")
      |> put_req_header("x-http-method-override", "DELETE")
      |> endpoint()

    assert deleted.status == 404
    assert areas(c.actor) == []

    id =
      Repo.query!(
        "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'Synthetic',52.5,13.4,100,now(),now()) RETURNING id",
        [c.actor.id]
      ).rows
      |> hd()
      |> hd()

    renamed =
      c.actor
      |> post("/api/v1/areas/#{id}", "_method=PATCH&area%5Bname%5D=Renamed", @form)
      |> endpoint()

    assert renamed.status == 200
    assert areas(c.actor) == [[id, "Renamed"]]

    destroyed =
      c.actor
      |> post("/api/v1/demo_data", "_method=DELETE", @form)
      |> endpoint()

    assert Jason.decode!(destroyed.resp_body) == %{"status" => "no_demo_data"}

    assert Repo.query!("SELECT count(*) FROM imports WHERE user_id=$1", [c.actor.id]).rows == [
             [0]
           ]
  end

  defp chunked(user, params) do
    body = Jason.encode!(params)

    Plug.Test.conn(:patch, "/api/v1/settings", body)
    |> put_req_header("transfer-encoding", "chunked")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> user.api_key)
    |> DawarichWeb.Endpoint.call(DawarichWeb.Endpoint.init([]))
  end

  defp post(user, path, body, type) do
    Plug.Test.conn(:post, path, body)
    |> put_req_header("content-type", type)
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> user.api_key)
  end

  defp endpoint(conn), do: DawarichWeb.Endpoint.call(conn, DawarichWeb.Endpoint.init([]))

  defp areas(user),
    do: Repo.query!("SELECT id,name FROM areas WHERE user_id=$1 ORDER BY id", [user.id]).rows

  defp request(user, method, path) do
    conn =
      Plug.Test.conn(method, path, "{}")
      |> put_req_header("content-length", "2")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")

    conn =
      if user, do: put_req_header(conn, "authorization", "Bearer " <> user.api_key), else: conn

    DawarichWeb.Endpoint.call(conn, DawarichWeb.Endpoint.init([]))
  end

  defp stable_headers(conn),
    do: Enum.reject(conn.resp_headers, fn {name, _} -> name in ~w(x-request-id x-runtime) end)

  defp timezone(user),
    do:
      Repo.query!("SELECT settings->>'timezone' FROM users WHERE id=$1", [user.id]).rows
      |> hd()
      |> hd()
end

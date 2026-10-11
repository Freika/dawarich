defmodule DawarichWeb.NativePlacesRoutesTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.NativePlaces, as: N
  alias Dawarich.Test.FrameSeeds, as: S
  @endpoint DawarichWeb.Endpoint
  setup do: N.setup!()

  test "native Places route ignores retired list handback configuration", ctx do
    previous = Application.get_env(:dawarich, :rails_routes)
    Application.put_env(:dawarich, :rails_routes, ~w(places))
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, previous) end)
    route = Phoenix.Router.route_info(DawarichWeb.Router, "GET", "/places", "localhost")
    refute Map.has_key?(route, :rails_gate)

    for headers <- [
          [],
          [{"turbo-frame", "places"}],
          [{"turbo-frame", "places"}, {"turbo-frame", "other"}],
          [{"x-requested-with", "XMLHttpRequest"}]
        ] do
      conn =
        Enum.reduce(headers, N.conn(ctx.actor), fn {k, v}, acc ->
          %{acc | req_headers: [{k, v} | acc.req_headers]}
        end)
        |> get("/places?x=1")

      assert conn.status == 200
      assert conn.resp_body =~ "data-native-places"
      assert conn.resp_body =~ "/native/app.js"
      refute conn.resp_body =~ "<turbo-frame"
    end

    conn = N.conn(ctx.actor) |> head("/places")
    assert conn.status == 200
    assert conn.resp_body == ""
    conn = get(build_conn(), "/places")
    assert conn.status == 302
    assert redirected_to(conn) =~ "/users/sign_in"
  end

  test "native Places unsupported formats refuse locally with no fragment", ctx do
    for {path, headers, status} <- [
          {"/places", [{"accept", "application/json"}], 406},
          {"/places?format=json", [], 406},
          {"/places.json", [], 406},
          {"/places?format=turbo_stream", [], 406},
          {"/places", [{"accept", "text/vnd.turbo-stream.html"}], 406},
          {"/places?format=html", [{"accept", "application/json"}], 200}
        ] do
      conn =
        Enum.reduce(headers, N.conn(ctx.actor), fn {k, v}, acc -> put_req_header(acc, k, v) end)
        |> get(path)

      assert conn.status == status, path
      if status == 406, do: assert(conn.resp_body == "")
    end
  end

  test "owned member documents ignore frame hints and preserve private map navigation", ctx do
    S.place!(ctx.actor.id, 118_501, "Owned")
    S.place!(ctx.other.id, 118_502, "Foreign")
    conn = N.conn(ctx.actor) |> get("/places/118501?extra=value")
    assert redirected_to(conn, 302) == "http://www.example.com/map/v2?place_id=118501"

    conn =
      N.conn(ctx.actor)
      |> put_req_header("turbo-frame", "place-drawer")
      |> get("/places/118501?locale=de&extra=value")

    assert redirected_to(conn, 302) == "http://www.example.com/map/v2?place_id=118501"
    refute conn.resp_body =~ "<turbo-frame"

    for path <- ~w(/places/118502 /places/118599 /places/nope /places/118501/edit /places/new) do
      conn = N.conn(ctx.actor) |> get(path)
      assert conn.status == 404, path
      refute conn.resp_body =~ "Foreign"
    end

    assert Dawarich.Repo.query!("SELECT count(*) FROM places WHERE user_id=$1", [ctx.actor.id]).rows ==
             [[1]]
  end

  test "retained map Place writes preserve method CSRF negotiation and list destination", ctx do
    S.place!(ctx.actor.id, 118_501, "Before HTTP")

    S.visit!(ctx.actor.id, 118_521, %{
      place_id: 118_501,
      started_at: ~N[2026-01-01 08:00:00],
      ended_at: ~N[2026-01-01 08:30:00]
    })

    session = Dawarich.Test.RailsUser.session(ctx.actor.id)
    token = DawarichWeb.RailsCsrf.masked_token(session)

    params = %{
      "_method" => "patch",
      "authenticity_token" => token,
      "place" => %{"note" => "HTTP note"}
    }

    headers = [{"accept", "text/html"}, {"origin", "http://www.example.com"}]

    for {attrs, request_headers} <- [
          {Map.put(params, "authenticity_token", "invalid"), headers},
          {params, [{"accept", "text/html"}, {"origin", "http://foreign.invalid"}]},
          {Map.put(params, "place", ["invalid"]), headers}
        ] do
      conn =
        Dawarich.Test.RailsFormRequests.post_form(
          session,
          Plug.Conn.Query.encode(attrs),
          request_headers,
          "/places/118501"
        )

      assert conn.status == 422
      assert Dawarich.Repo.query!("SELECT note FROM places WHERE id=118501", []).rows == [[nil]]
    end

    conn =
      Dawarich.Test.RailsFormRequests.post_form(
        session,
        Plug.Conn.Query.encode(params),
        headers,
        "/places/118501"
      )

    assert redirected_to(conn, 303) == "http://www.example.com/map/v2?place_id=118501"

    assert Dawarich.Repo.query!("SELECT note FROM places WHERE id=118501", []).rows == [
             ["HTTP note"]
           ]

    conn =
      Dawarich.Test.RailsFormRequests.post_form(
        session,
        Plug.Conn.Query.encode(%{"_method" => "delete", "authenticity_token" => token}),
        headers,
        "/places/118501?page=2x"
      )

    assert redirected_to(conn, 303) == "http://www.example.com/places?page=2x"
    assert Dawarich.Repo.query!("SELECT place_id FROM visits WHERE id=118521", []).rows == [[nil]]
  end
end

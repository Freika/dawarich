defmodule DawarichWeb.MapDataFramesTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsFormRequests, RailsUser}
  alias DawarichWeb.{MapDataGate, MapFrames, RailsAuth, Router}
  @endpoint DawarichWeb.Endpoint
  @path "/tracks/8370/segments"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    user = FrameSeeds.user!(8370, %{"timezone" => "UTC", "maps" => %{"distance_unit" => "km"}})

    FrameSeeds.track!(user.id, 8370, %{
      start_at: ~N[2026-10-03 08:00:00],
      end_at: ~N[2026-10-03 09:00:00]
    })

    FrameSeeds.point!(user.id, 837_001, 1_772_359_200)
    %{user: user}
  end

  defp row! do
    FrameSeeds.segment!(8370, 83701, %{
      start_index: 0,
      end_index: 1,
      duration: 600,
      distance: 1000,
      transportation_mode: 2,
      confidence_score: 0.8
    })
  end

  defp request(conn, path \\ @path),
    do: conn |> put_req_header("accept", "text/html, application/xhtml+xml") |> get(path)

  defp no_token(user) do
    cookie = user.id |> RailsUser.session() |> Map.delete("_csrf_token") |> RailsUser.cookie()
    build_conn() |> put_req_cookie("_dawarich_session", cookie)
  end

  test "owned segment frame renders without consuming flash", %{user: user} do
    assert %{plug: MapFrames, pipe_through: [:rails_frame]} =
             Phoenix.Router.route_info(Router, "GET", @path, "localhost")

    row!()
    flash = %{"discard" => [], "flashes" => %{"notice" => "Saved"}}
    conn = user.id |> RailsUser.signed_in(%{"flash" => flash}) |> request()
    assert html_response(conn, 200) =~ ~s(id="segment-row-83701")
    assert get_resp_header(conn, "set-cookie") == []
    assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    assert get_resp_header(conn, "vary") == ["Accept"]
    assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
    assert conn.assigns.rails_session["flash"] == flash
  end

  test "segment forms stage a token only when needed", %{user: user} do
    assert %{plug: MapFrames} = Phoenix.Router.route_info(Router, "GET", @path, "localhost")
    empty = user |> no_token() |> request()
    assert empty.status == 200
    assert get_resp_header(empty, "set-cookie") == []
    row!()
    forms = user |> no_token() |> request()
    assert is_binary(RailsFormRequests.rails_session(forms)["_csrf_token"])
    assert html_response(forms, 200) =~ ~r/name="authenticity_token" value="[^"]+"/
    assert user.id |> RailsUser.signed_in() |> request() |> get_resp_header("set-cookie") == []
  end

  test "matching address frame uses normalized fields without list fallback", %{user: user} do
    assert %{plug: MapFrames} =
             Phoenix.Router.route_info(Router, "GET", "/points/837001/address", "localhost")

    Repo.query!(
      "UPDATE points SET city = 'Fallback', country_name = 'Germany', geodata = '{}'::jsonb WHERE id = 837001"
    )

    conn =
      RailsUser.signed_in(user.id)
      |> put_req_header("turbo-frame", "point-address-837001")
      |> request("/points/837001/address")

    assert html_response(conn, 200) =~ ~s(<turbo-frame id="point-address-837001">)
    refute conn.resp_body =~ "Fallback"
    refute conn.resp_body =~ "<!DOCTYPE"
    assert get_resp_header(conn, "set-cookie") == []

    Repo.query!("UPDATE points SET geodata = $1 WHERE id = 837001", [
      %{
        "properties" => %{
          "street" => "Synthetic Street",
          "city" => "Leipzig",
          "country" => "Germany"
        }
      }
    ])

    html =
      RailsUser.signed_in(user.id)
      |> put_req_header("turbo-frame", "point-address-837001")
      |> request("/points/837001/address")
      |> html_response(200)

    assert html =~ "Synthetic Street, Leipzig, Germany"
  end

  test "direct foreign malformed and query-writing frame requests replay", %{user: user} do
    assert %{plug: MapFrames} =
             Phoenix.Router.route_info(Router, "GET", "/points/837001/address", "localhost")

    refute MapDataGate.point_address?(RailsUser.signed_in(user.id), %{"id" => "837001"})
    other = FrameSeeds.user!(8371)
    FrameSeeds.point!(other.id, 837_002, 1_772_359_200)

    FrameSeeds.track!(other.id, 8371, %{
      start_at: ~N[2026-10-03 08:00:00],
      end_at: ~N[2026-10-03 09:00:00]
    })

    upstream = RailsFormRequests.upstream!()

    for {path, frame, token} <- [
          {"/points/837001/address", nil, true},
          {"/points/837001/address", "point-address-0", true},
          {"/points/837001/address", "point-address-837001", false},
          {"/points/837002/address", "point-address-837002", true},
          {"/points/no/address", "point-address-no", true},
          {"/points/9999999999999999999/address", "point-address-9999999999999999999", true},
          {"/points/837001/address?locale=de", "point-address-837001", true},
          {"/tracks/8370/segments?client=x", nil, true},
          {"/tracks/8371/segments", nil, true}
        ] do
      {{line, body}, conn} =
        RailsFormRequests.forwarded(upstream, fn ->
          conn = if token, do: RailsUser.signed_in(user.id), else: no_token(user)
          conn = if frame, do: put_req_header(conn, "turbo-frame", frame), else: conn
          request(conn, path)
        end)

      assert line == "GET #{path} HTTP/1.1"
      assert body == ""
      assert conn.status == 204
      assert get_resp_header(conn, "set-cookie") == []
    end
  end

  test "frame race replays before any token changes are committed", %{user: user} do
    assert %{plug: MapFrames} = Phoenix.Router.route_info(Router, "GET", @path, "localhost")
    row!()

    conn =
      user
      |> no_token()
      |> Map.put(:request_path, @path)
      |> Map.put(:path_info, ["tracks", "8370", "segments"])

    assert MapDataGate.segments?(conn, %{"track_id" => "8370"})
    Repo.query!("DELETE FROM track_segments WHERE track_id = 8370")
    Repo.query!("DELETE FROM tracks WHERE id = 8370")
    upstream = RailsFormRequests.upstream!()

    {{line, _}, result} =
      RailsFormRequests.forwarded(upstream, fn ->
        conn
        |> RailsAuth.call([])
        |> fetch_query_params()
        |> assign(:locale, "en")
        |> Map.put(:path_params, %{"track_id" => "8370"})
        |> MapFrames.call(:segments)
      end)

    assert line == "GET #{@path} HTTP/1.1"
    assert result.status == 204
    assert result.assigns.api_tag == "tracks"
    assert get_resp_header(result, "set-cookie") == []
    refute Map.has_key?(result.private, :dawarich_rails_session_changes)
  end

  test "signed out segment frame keeps the Devise return URL" do
    assert %{plug: MapFrames} = Phoenix.Router.route_info(Router, "GET", @path, "localhost")
    conn = request(build_conn())
    assert redirected_to(conn, 302) == "http://www.example.com/users/sign_in"
    session = RailsFormRequests.rails_session(conn)
    assert session["user_return_to"] == @path

    assert session["flash"]["flashes"]["alert"] ==
             "You need to sign in or sign up before continuing."
  end
end

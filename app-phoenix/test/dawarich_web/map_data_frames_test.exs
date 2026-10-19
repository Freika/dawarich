defmodule DawarichWeb.MapDataFramesTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  alias DawarichWeb.Router
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

  defp refused(conn) do
    assert conn.status == 410
    assert conn.resp_body =~ "available through the native map"
    assert get_resp_header(conn, "set-cookie") == []
    refute Map.has_key?(conn.private, :dawarich_rails_session_changes)
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  defp open_track(user) do
    {:ok, view, _} =
      Phoenix.LiveViewTest.live(
        RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id),
        "/map/v2?panel=timeline&date=2026-10-03&start_at=2026-10-03T00:00:00&end_at=2026-10-03T23:59:59"
      )

    Phoenix.LiveViewTest.render_async(view, 5000)
    Phoenix.LiveViewTest.render_hook(view, "track:toggle", %{"id" => "8370"})
    view
  end

  defp open(user) do
    {:ok, view, _} =
      Phoenix.LiveViewTest.live(
        RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id),
        "/map/v2"
      )

    view
  end

  test "retired owned segment frame refuses without consuming flash", %{user: user} do
    assert %{plug: DawarichWeb.NativeMapRetired, pipe_through: [:native_map_retired]} =
             Phoenix.Router.route_info(Router, "GET", @path, "localhost")

    row!()
    flash = %{"discard" => [], "flashes" => %{"notice" => "Saved"}}
    refused(user.id |> RailsUser.signed_in(%{"flash" => flash}) |> request())
    assert Repo.query!("SELECT count(*) FROM track_segments WHERE id=83701").rows == [[1]]
  end

  test "retired segment forms never stage a token with or without rows", %{user: user} do
    refused(user |> no_token() |> request())
    row!()
    refused(user |> no_token() |> request())
    refused(user.id |> RailsUser.signed_in() |> request())
    view = open_track(user)
    assert has_element?(view, "#native-track-info #native-segment-drawer")
    refute has_element?(view, "#native-segment-drawer input[name=authenticity_token]")
  end

  test "native address drawer uses normalized fields without list fallback", %{user: user} do
    Repo.query!(
      "UPDATE points SET city='Fallback', country_name='Germany', geodata='{}'::jsonb WHERE id=837001"
    )

    refused(
      RailsUser.signed_in(user.id)
      |> put_req_header("turbo-frame", "point-address-837001")
      |> request("/points/837001/address")
    )

    view = open(user)
    render_hook(view, "address:open", %{"id" => "837001"})
    assert has_element?(view, "#native-point-address")
    refute has_element?(view, "#native-point-address", "Fallback")

    Repo.query!("UPDATE points SET geodata=$1 WHERE id=837001", [
      %{
        "properties" => %{
          "street" => "Synthetic Street",
          "city" => "Leipzig",
          "country" => "Germany"
        }
      }
    ])

    render_hook(view, "address:open", %{"id" => "837001"})
    assert has_element?(view, "#native-point-address", "Synthetic Street, Leipzig, Germany")
  end

  test "direct foreign malformed and query-writing retired frames refuse without effects", %{
    user: user
  } do
    other = FrameSeeds.user!(8371)
    FrameSeeds.point!(other.id, 837_002, 1_772_359_200)

    FrameSeeds.track!(other.id, 8371, %{
      start_at: ~N[2026-10-03 08:00:00],
      end_at: ~N[2026-10-03 09:00:00]
    })

    for frame <- [nil, "point-address-0", "point-address-837001"] do
      conn = no_token(user)
      conn = if frame, do: put_req_header(conn, "turbo-frame", frame), else: conn
      refused(request(conn, "/points/837001/address"))
    end

    for path <-
          ~w(/points/837002/address /points/no/address /points/9999999999999999999/address /points/837001/address?locale=de /tracks/8370/segments?client=x /tracks/8371/segments) do
      refused(request(RailsUser.signed_in(user.id), path))
    end

    view = open(user)
    render_hook(view, "address:open", %{"id" => "837002"})
    refute has_element?(view, "#native-point-address")
    assert Repo.query!("SELECT count(*) FROM points WHERE id IN (837001,837002)").rows == [[2]]
  end

  test "native segment admission race clears the drawer before any write", %{user: user} do
    row!()
    view = open_track(user)
    assert has_element?(view, "#native-track-info #native-segment-drawer")
    Repo.query!("DELETE FROM track_segments WHERE track_id=8370")
    Repo.query!("DELETE FROM tracks WHERE id=8370")
    render_hook(view, "segments:open", %{"track_id" => "8370"})
    refute has_element?(view, "#native-segment-drawer")
    render_hook(view, "segment:mode", %{"segment_id" => "83701", "mode" => "cycling"})
    assert Repo.query!("SELECT count(*) FROM track_segments WHERE track_id=8370").rows == [[0]]
    refused(user |> no_token() |> request())
  end

  test "signed out retired segment frame refuses locally and the native map retains Devise admission" do
    refused(request(build_conn()))
    conn = get(build_conn(), "/map/v2")
    assert redirected_to(conn, 302) == "http://www.example.com/users/sign_in"
  end
end

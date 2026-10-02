defmodule DawarichWeb.MapFramesTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias Dawarich.Test.FrameSeeds, as: S
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.MapFramesGate

  @endpoint DawarichWeb.Endpoint
  @frame "text/html, application/xhtml+xml"
  @browser "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    %{user: S.user!(7021)}
  end

  defp frame_get(user, path, accept \\ @frame),
    do:
      RailsUser.signed_in(user.id)
      |> put_req_header("accept", accept)
      |> put_req_header("x-turbo-request-id", "a6s2-frame")
      |> get(path)

  describe "the track card" do
    setup %{user: user} do
      S.track!(user.id, 7221, %{
        start_at: ~N[2026-09-27 05:00:00],
        end_at: ~N[2026-09-27 06:00:00],
        distance: 12_345,
        avg_speed: 18.47,
        dominant_mode: 4,
        elevation_gain: 120,
        elevation_loss: 0
      })

      :ok
    end

    test "an owner gets Rails' card with Rails' headers", %{user: user} do
      conn = frame_get(user, "/map/timeline_feeds/7221/track_info")
      html = html_response(conn, 200)

      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
      assert get_resp_header(conn, "vary") == ["Accept"]
      assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
      assert html =~ ~s(<turbo-frame id="track-info-7221">)
      assert html =~ ~s(data-track-start="2026-09-27T07:00:00+02:00")
      assert html =~ ~s(href="/tracks/7221/share_link/new")
      assert html =~ ~s(src="/tracks/7221/segments")
      assert html =~ "12.3 km"
      assert html =~ ~s(id="track-replay-play-icon")
      refute html =~ "↓"
    end

    test "a browser-like or empty Accept gets no Vary", %{user: user} do
      for accept <- [@browser, ""] do
        assert frame_get(user, "/map/timeline_feeds/7221/track_info", accept)
               |> get_resp_header("vary") == []
      end
    end

    test "another user's track is Rails' 404", %{user: user} do
      other = S.user!(7022)

      S.track!(other.id, 7222, %{
        start_at: ~N[2026-09-27 05:00:00],
        end_at: ~N[2026-09-27 06:00:00]
      })

      assert_error_sent 404, fn -> frame_get(user, "/map/timeline_feeds/7222/track_info") end
    end

    test "a signed-out request is Devise's redirect with the return path and alert" do
      conn =
        build_conn()
        |> put_req_header("accept", @frame)
        |> get("/map/timeline_feeds/7221/track_info")

      assert redirected_to(conn, 302) == "http://www.example.com/users/sign_in"
      assert [cookie] = get_resp_header(conn, "set-cookie")
      assert cookie =~ "_dawarich_session="
    end
  end

  describe "MapFramesGate.track?/2" do
    defp gate_conn(path), do: build_conn(:get, path)

    test "refuses the locale and client markers" do
      assert MapFramesGate.track?(gate_conn("/map/timeline_feeds/5/track_info"), %{})
      refute MapFramesGate.track?(gate_conn("/map/timeline_feeds/5/track_info?locale=de"), %{})
      refute MapFramesGate.track?(gate_conn("/map/timeline_feeds/5/track_info?client=ios"), %{})

      refute "/map/timeline_feeds/5/track_info"
             |> gate_conn()
             |> put_req_header("x-dawarich-client", "ios")
             |> MapFramesGate.track?(%{})
    end
  end
end

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

  describe "the day feed" do
    @feed "/map/timeline_feeds?start_at=2026-09-27T00:00:00&end_at=2026-09-27T23:59:59"

    test "renders the day, its rows and the forms with the session's masked token", %{user: user} do
      S.place!(user.id, 7321, "Café Kowalski, Karl-Liebknecht-Straße, 10, Leipzig, Sachsen")

      S.visit!(user.id, 7121, %{
        started_at: ~N[2026-09-27 06:00:00],
        ended_at: ~N[2026-09-27 07:00:00],
        name: "",
        place_id: 7321,
        duration: 60
      })

      S.visit!(user.id, 7122, %{
        started_at: ~N[2026-09-27 09:00:00],
        ended_at: ~N[2026-09-27 10:00:00],
        duration: 60
      })

      S.track!(user.id, 7223, %{
        start_at: ~N[2026-09-27 07:05:00],
        end_at: ~N[2026-09-27 07:35:00],
        distance: 2400,
        duration: 1800
      })

      html = user |> frame_get(@feed) |> html_response(200)

      assert html =~ ~s(<turbo-frame id="timeline-feed-frame">)
      assert html =~ ~s(data-day="2026-09-27")
      assert html =~ ~s(id="visit_entry_7121")
      assert html =~ ~s(data-started-at="2026-09-27T08:00:00+02:00")
      assert html =~ ~s(data-max-bulk-visits="500")
      assert html =~ ~s(action="/visits/7121")
      assert html =~ ~s(data-frame-id="track-info-7223")
      assert html =~ "Karl-Liebknecht-Straße 10, Leipzig"
      assert length(Regex.scan(~r/name="authenticity_token" value="[^"]+"/, html)) == 6
    end

    test "leaves the session's pending flash and token alone", %{user: user} do
      S.visit!(user.id, 7124, %{
        started_at: ~N[2026-09-27 06:00:00],
        ended_at: ~N[2026-09-27 07:00:00]
      })

      flash = %{"discard" => [], "flashes" => %{"notice" => "Saved"}}

      conn =
        RailsUser.signed_in(user.id, %{"flash" => flash})
        |> put_req_header("accept", @frame)
        |> get(@feed)

      assert conn.status == 200
      assert get_resp_header(conn, "set-cookie") == []
    end

    test "a session without a token gets one when the feed renders forms, as form_with creates it",
         %{user: user} do
      cookie = user.id |> RailsUser.session() |> Map.delete("_csrf_token") |> RailsUser.cookie()

      request = fn ->
        build_conn()
        |> put_req_cookie("_dawarich_session", cookie)
        |> put_req_header("accept", @frame)
        |> get(@feed)
      end

      assert request.() |> get_resp_header("set-cookie") == []

      S.visit!(user.id, 7123, %{
        started_at: ~N[2026-09-27 06:00:00],
        ended_at: ~N[2026-09-27 07:00:00]
      })

      assert [set] = request.() |> get_resp_header("set-cookie")
      [_, value] = Regex.run(~r/_dawarich_session=([^;]+)/, set)

      read =
        build_conn()
        |> put_req_cookie("_dawarich_session", value)
        |> DawarichWeb.RailsAuth.call([])

      assert is_binary(read.assigns.rails_session["_csrf_token"])
    end

    test "an empty day keeps the day navigator for the requested date", %{user: user} do
      html = user |> frame_get(@feed) |> html_response(200)

      assert html =~ ~s(data-testid="day-header-label">Sunday, September 27<)
      refute html =~ "timeline-entries"
    end
  end

  describe "MapFramesGate.feed?/2" do
    test "owns digits and ISO start/end only" do
      ok = &MapFramesGate.feed?(build_conn(:get, "/map/timeline_feeds?" <> &1), %{})

      assert ok.("start_at=1790460000&end_at=1790546399")
      assert ok.("start_at=2026-09-27T00:00:00&end_at=2026-09-27%2023:59")
      refute ok.("end_at=2026-09-27T23:59:59")
      refute ok.("start_at=%20&end_at=2026-09-27T23:59:59")
      refute ok.("start_at=yesterday&end_at=2026-09-27T23:59:59")
      refute ok.("start_at[]=1&end_at=2")
    end
  end

  describe "the calendar" do
    test "Turbo's stream request gets the replace stream, a frame request the frame", %{
      user: user
    } do
      stream =
        frame_get(
          user,
          "/map/timeline_feeds/calendar?month=2026-09",
          "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"
        )

      frame = frame_get(user, "/map/timeline_feeds/calendar?month=2026-09")

      assert get_resp_header(stream, "content-type") == [
               "text/vnd.turbo-stream.html; charset=utf-8"
             ]

      assert stream.resp_body =~
               ~r/\A<turbo-stream action="replace" target="timeline-calendar-frame"><template><turbo-frame id="timeline-calendar-frame">/

      assert html_response(frame, 200) =~ ~s(<turbo-frame id="timeline-calendar-frame">)
      assert get_resp_header(frame, "vary") == ["Accept"]
    end

    test "a lone */* gets the stream; browser-like and empty Accept get HTML without Vary", %{
      user: user
    } do
      path = "/map/timeline_feeds/calendar?month=2026-09"

      assert frame_get(user, path, "*/*") |> get_resp_header("content-type") == [
               "text/vnd.turbo-stream.html; charset=utf-8"
             ]

      for accept <- [@browser, ""] do
        conn = frame_get(user, path, accept)
        assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
        assert get_resp_header(conn, "vary") == []
      end
    end
  end

  describe "MapFramesGate.calendar?/2" do
    defp calendar(query, accept \\ "text/html, application/xhtml+xml"),
      do:
        build_conn(:get, "/map/timeline_feeds/calendar" <> query)
        |> put_req_header("accept", accept)
        |> MapFramesGate.calendar?(%{})

    test "owns YYYY-MM months, blank or missing months, and the Accept shapes Turbo and browsers send" do
      assert calendar("?month=2026-09")
      assert calendar("")
      assert calendar("?month=")
      assert calendar("?month=2026-09", "*/*")
      assert calendar("?month=2026-09", "")
      refute calendar("?month=2026-9")
      refute calendar("?month=0000-01")
      refute calendar("?month[]=2026-09")
      refute calendar("?month=2026-09", "text/html;level=1, text/vnd.turbo-stream.html")
      refute calendar("?month=2026-09", "TEXT/HTML, application/xhtml+xml")
    end
  end

  describe "the residency card" do
    setup %{user: user} do
      S.stat!(user.id, 2026, 1)

      for {country, days} <- [{"Germany", 1..5}, {"Czechia", 10..12}, {"Atlantis", 20..20}],
          day <- days,
          do:
            S.point!(
              user.id,
              7700 + day,
              DateTime.to_unix(DateTime.new!(Date.new!(2026, 3, day), ~T[12:00:00], "Etc/UTC")),
              %{country_name: country}
            )

      :ok
    end

    test "renders countries, periods and the year grid", %{user: user} do
      html = user |> frame_get("/map/residency?year=2026") |> html_response(200)

      assert html =~ ~s(<turbo-frame id="residency-content">)
      assert html =~ ~s(data-testid="residency-country-list")
      assert html =~ "bg-blue-600"
      assert html =~ ~s(data-tip="Germany — )
      assert length(Regex.scan(~r/<details class="group bg-base-100 rounded-lg">/, html)) == 3
    end

    test "the default year is the latest stats year, not the current one" do
      old = S.user!(7025)
      S.stat!(old.id, 2024, 5)
      S.stat!(old.id, 2025, 5)

      S.point!(old.id, 7790, DateTime.to_unix(~U[2025-05-01 12:00:00Z]), %{
        country_name: "Germany"
      })

      assert old |> frame_get("/map/residency") |> html_response(200) =~ "Germany"
    end

    test "an empty year shows Rails' empty card with the year", %{user: user} do
      html = user |> frame_get("/map/residency?year=2025") |> html_response(200)

      assert html =~ "2025."
      refute html =~ "residency-country-list"
    end

    test "countries with equal day counts are Rails' to order", %{user: user} do
      S.point!(user.id, 7799, DateTime.to_unix(~U[2026-03-21 12:00:00Z]), %{
        country_name: "Atlantis"
      })

      S.point!(user.id, 7798, DateTime.to_unix(~U[2026-03-22 12:00:00Z]), %{
        country_name: "Narnia"
      })

      S.point!(user.id, 7797, DateTime.to_unix(~U[2026-03-23 12:00:00Z]), %{
        country_name: "Narnia"
      })

      ctx = %{user: user, locale: "en", query: %{"year" => "2026"}, now: ~U[2026-09-29 10:00:00Z]}

      assert {:replay, _reason} = DawarichWeb.MapFrames.body(:residency, ctx)
    end

    test "the year runs from local midnight to local midnight in the user's zone", %{user: user} do
      S.point!(user.id, 7796, DateTime.to_unix(~U[2026-12-31 23:30:00Z]), %{
        country_name: "Czechia"
      })

      assert user |> frame_get("/map/residency?year=2026") |> html_response(200) =~ "9 / 365"
    end
  end

  describe "MapFramesGate.residency?/2" do
    setup do
      on_exit(fn -> System.delete_env("SELF_HOSTED") end)
    end

    defp residency(user, query),
      do:
        RailsUser.signed_in(user.id)
        |> Map.put(:query_string, query)
        |> MapFramesGate.residency?(%{})

    test "owns self-hosted users and Cloud users with full access, years 1970–2037 and no year" do
      lite = S.user!(7023, %{"timezone" => "Europe/Berlin"}, %{plan: 0})
      pro = S.user!(7024)

      assert residency(lite, "year=2026")
      System.put_env("SELF_HOSTED", "false")
      refute residency(lite, "year=2026")
      assert residency(pro, "year=2026")
      assert residency(pro, "")
      refute residency(pro, "year=1969")
      refute residency(pro, "year=26")
      refute residency(pro, "year=")
    end
  end
end

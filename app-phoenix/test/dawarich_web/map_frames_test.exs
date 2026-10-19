defmodule DawarichWeb.MapFramesTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
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

  defp native_map(user) do
    {:ok, view, _} =
      live(
        RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id),
        "/map/v2?panel=timeline&date=2026-09-27&start_at=2026-09-27T00:00:00&end_at=2026-09-27T23:59:59"
      )

    render_async(view)
    view
  end

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

    test "native owner opens the scoped track card with replay sharing and segment controls", %{
      user: user
    } do
      view = native_map(user)
      render_hook(view, "track:toggle", %{"id" => "7221"})
      assert has_element?(view, "#native-track-info[data-track-id='7221']", "12.3 km")

      assert has_element?(
               view,
               "[data-track-replay][data-track-start='2026-09-27T07:00:00+02:00']"
             )

      assert has_element?(view, "a[href='/tracks/7221/share_link/new']")
      assert has_element?(view, "button[phx-click='segments:open'][phx-value-track_id='7221']")
      refute has_element?(view, "turbo-frame, [data-controller]")
      refute render(view) =~ "↓"
    end

    test "a browser-like or empty Accept gets no Vary", %{
      user: user
    } do
      for accept <- [@frame, @browser, ""] do
        conn = frame_get(user, "/map/timeline_feeds/7221/track_info", accept)
        assert conn.status == 410
        assert conn.resp_body == "This map command is available through the native map."
        assert get_resp_header(conn, "cache-control") == ["no-store"]
        assert get_resp_header(conn, "set-cookie") == []
      end
    end

    test "native track selection refuses another owner and clears the selected track", %{
      user: user
    } do
      other = S.user!(7022)

      S.track!(other.id, 7222, %{
        start_at: ~N[2026-09-27 05:00:00],
        end_at: ~N[2026-09-27 06:00:00]
      })

      view = native_map(user)
      render_hook(view, "track:toggle", %{"id" => "7221"})
      assert has_element?(view, "#native-track-info[data-track-id='7221']")
      render_hook(view, "track:toggle", %{"id" => "7222"})
      refute has_element?(view, "#native-track-info")
      assert :sys.get_state(view.pid).socket.assigns.track_info == nil
      assert_push_event(view, "track:selection", %{id: nil, points: false})
    end

    test "native map guests receive sign-in and retired track reads expose no data" do
      conn = build_conn() |> get("/map/v2?panel=timeline")
      assert redirected_to(conn, 302) == "http://www.example.com/users/sign_in"
      assert [cookie] = get_resp_header(conn, "set-cookie")
      assert cookie =~ "_dawarich_session="

      retired =
        build_conn()
        |> put_req_header("accept", @frame)
        |> get("/map/timeline_feeds/7221/track_info")

      assert retired.status == 410
      refute retired.resp_body =~ "7221"
      assert get_resp_header(retired, "set-cookie") == []
    end
  end

  describe "MapFramesGate.track?/2" do
    defp gate_conn(path), do: build_conn(:get, path)

    test "accepts scalar locale and client markers" do
      assert MapFramesGate.track?(gate_conn("/map/timeline_feeds/5/track_info"), %{})
      assert MapFramesGate.track?(gate_conn("/map/timeline_feeds/5/track_info?locale=de"), %{})
      assert MapFramesGate.track?(gate_conn("/map/timeline_feeds/5/track_info?client=ios"), %{})

      assert "/map/timeline_feeds/5/track_info"
             |> gate_conn()
             |> put_req_header("x-dawarich-client", "ios")
             |> MapFramesGate.track?(%{})
    end
  end

  describe "the day feed" do
    @feed "/map/timeline_feeds?start_at=2026-09-27T00:00:00&end_at=2026-09-27T23:59:59"

    test "native day feed preserves owned visits journeys local times and scoped actions", %{
      user: user
    } do
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

      view = native_map(user)
      assert has_element?(view, "#native-timeline-feed [data-day='2026-09-27']")
      assert has_element?(view, "#visit_entry_7121[data-started-at='2026-09-27T08:00:00+02:00']")
      assert has_element?(view, "#visit_entry_7122")
      assert has_element?(view, "[data-track-id='7223'][data-entry-type=journey]")

      assert has_element?(
               view,
               "#visit_entry_7121 button[phx-click='visit:inline'][phx-value-id='7121']"
             )

      assert has_element?(view, "#visit_entry_7121 form.button_to[phx-submit*='visit:delete']")

      assert render(view) =~ "Karl-Liebknecht-Straße 10, Leipzig"

      refute has_element?(
               view,
               "turbo-frame, #native-timeline-feed input[name=authenticity_token]:not([value=''])"
             )
    end

    test "retired day feed leaves pending flash and session token unchanged", %{user: user} do
      S.visit!(user.id, 7124, %{
        started_at: ~N[2026-09-27 06:00:00],
        ended_at: ~N[2026-09-27 07:00:00]
      })

      flash = %{"discard" => [], "flashes" => %{"notice" => "Saved"}}

      conn =
        RailsUser.signed_in(user.id, %{"flash" => flash})
        |> put_req_header("accept", @frame)
        |> get(@feed)

      assert conn.status == 410
      assert get_resp_header(conn, "set-cookie") == []
    end

    test "native timeline commands need no Rails form token from the retired feed",
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

      assert request.().status == 410
      assert request.() |> get_resp_header("set-cookie") == []
      view = native_map(user)
      assert has_element?(view, "#visit_entry_7123 button[phx-click='visit:inline']")

      refute has_element?(
               view,
               "#native-timeline-feed input[name=authenticity_token]:not([value=''])"
             )
    end

    test "native empty day keeps navigation for the requested date", %{user: user} do
      view = native_map(user)
      assert has_element?(view, "[data-testid=day-header-label]", "Sunday, September 27")
      assert has_element?(view, "button[phx-click='calendar:day'][phx-value-date='2026-09-26']")
      assert has_element?(view, "button[phx-click='calendar:day'][phx-value-date='2026-09-28']")
      assert render(view) =~ "No visits tracked this day"
      refute has_element?(view, "[data-entry-type=visit], [data-entry-type=journey]")
    end
  end

  describe "MapFramesGate.feed?/2" do
    test "admits Rails timestamp fallback and structured native error cases" do
      ok = &MapFramesGate.feed?(build_conn(:get, "/map/timeline_feeds?" <> &1), %{})

      assert ok.("start_at=1790460000&end_at=1790546399")
      assert ok.("start_at=2026-09-27T00:00:00&end_at=2026-09-27%2023:59")
      assert ok.("end_at=2026-09-27T23:59:59")
      assert ok.("start_at=%20&end_at=2026-09-27T23:59:59")
      assert ok.("start_at=yesterday&end_at=2026-09-27T23:59:59")
      assert ok.("start_at[]=1&end_at=2")
    end
  end

  describe "the calendar" do
    test "native calendar event renders the selected month while retired transports refuse", %{
      user: user
    } do
      view = native_map(user)
      render_hook(view, "calendar:month", %{"month" => "2026-09"})
      render_async(view)

      assert has_element?(
               view,
               "#native-timeline-calendar [data-testid=calendar-title]",
               "September 2026"
             )

      assert has_element?(view, "button[data-day='2026-09-27'][phx-click='calendar:day']")

      for accept <- [@frame, "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"] do
        conn = frame_get(user, "/map/timeline_feeds/calendar?month=2026-09", accept)
        assert conn.status == 410
        refute conn.resp_body =~ "turbo-"
      end
    end

    test "retired calendar refuses wildcard browser and empty Accept without session writes", %{
      user: user
    } do
      for accept <- ["*/*", @browser, ""] do
        conn = frame_get(user, "/map/timeline_feeds/calendar?month=2026-09", accept)
        assert conn.status == 410
        assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
        assert get_resp_header(conn, "set-cookie") == []
        refute conn.resp_body =~ "turbo-"
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
      assert calendar("?month=2026-9")
      assert calendar("?month=0000-01")
      assert calendar("?month[]=2026-09")
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

    test "countries with equal day counts render in the captured source order", %{user: user} do
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

      assert {:ok, "text/html", _html} = DawarichWeb.MapFrames.body(:residency, ctx)
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
      previous = System.get_env("SELF_HOSTED")

      on_exit(fn ->
        if previous,
          do: System.put_env("SELF_HOSTED", previous),
          else: System.delete_env("SELF_HOSTED")
      end)
    end

    defp residency(user, query),
      do:
        RailsUser.signed_in(user.id)
        |> Map.put(:query_string, query)
        |> MapFramesGate.residency?(%{})

    test "admits residency authentication and year failures to the native action" do
      lite = S.user!(7023, %{"timezone" => "Europe/Berlin"}, %{plan: 0})
      pro = S.user!(7024)

      assert residency(lite, "year=2026")
      System.put_env("SELF_HOSTED", "false")
      assert residency(lite, "year=2026")
      assert residency(pro, "year=2026")
      assert residency(pro, "")
      assert residency(pro, "year=1969")
      assert residency(pro, "year=26")
      assert residency(pro, "year=")
    end
  end

  describe "the place drawer" do
    setup %{user: user} do
      S.place!(user.id, 7_084_101, "Café")
      :ok
    end

    defp drawer_get(conn),
      do:
        conn
        |> put_req_header("accept", @frame)
        |> put_req_header("turbo-frame", "place-drawer")
        |> get("/places/7084101")
        |> then(fn conn ->
          location = conn |> get_resp_header("location") |> List.first() |> URI.parse()
          recycle(conn) |> get(location.path <> "?" <> (location.query || ""))
        end)

    defp csrf_meta?(conn) do
      html_response(conn, 200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("meta[name=csrf-token]")
      |> LazyHTML.attribute("content")
      |> Enum.any?(&(is_binary(&1) and byte_size(&1) > 0))
    end

    test "stages a CSRF token only when the session has none", %{user: user} do
      cookie = user.id |> RailsUser.session() |> Map.delete("_csrf_token") |> RailsUser.cookie()
      staged = build_conn() |> put_req_cookie("_dawarich_session", cookie) |> drawer_get()

      assert csrf_meta?(staged)

      [set] =
        Enum.filter(
          get_resp_header(staged, "set-cookie"),
          &String.starts_with?(&1, "_dawarich_session=")
        )

      [_, value] = Regex.run(~r/_dawarich_session=([^;]+)/, set)

      read =
        build_conn()
        |> put_req_cookie("_dawarich_session", value)
        |> DawarichWeb.RailsAuth.call([])

      assert is_binary(read.assigns.rails_session["_csrf_token"])

      kept = user.id |> RailsUser.signed_in() |> drawer_get()
      assert csrf_meta?(kept)

      refute Enum.any?(
               get_resp_header(kept, "set-cookie"),
               &String.starts_with?(&1, "_dawarich_session=")
             )
    end

    test "a place that leaves after the gate is replayed", %{user: user} do
      ctx = %{user: user, locale: "en", id: "7084199", csrf: "CSRF", csrf_changes: %{}}
      assert {:replay, _reason} = DawarichWeb.MapFrames.body(:place, ctx)
    end
  end
end

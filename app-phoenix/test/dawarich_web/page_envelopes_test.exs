defmodule DawarichWeb.PageEnvelopesTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias DawarichWeb.{Endpoint, Strangler}
  alias Dawarich.Test.RailsUser

  @routes Jason.decode!(
            File.read!(Path.expand("../fixtures/page_envelopes/routes.json", __DIR__))
          )

  @source Jason.decode!(File.read!(Path.expand("../fixtures/page_envelopes/rails.json", __DIR__)))

  setup do
    keys = [:rails_routes, :rails_upstream]
    previous = Map.new(keys, &{&1, Application.fetch_env(:dawarich, &1)})
    env = Map.new(~w(DAWARICH_RAILS SELF_HOSTED), &{&1, System.get_env(&1)})
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    Application.put_env(:dawarich, :rails_routes, [])
    Application.delete_env(:dawarich, :rails_upstream)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    RailsUser.insert!(%{
      id: 880_001,
      email: "envelopes@example.invalid",
      admin: true,
      changelog_consent: 2,
      settings: %{"timezone" => "UTC", "onboarding_completed" => true}
    })

    on_exit(fn ->
      for {k, v} <- env, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))

      for {k, v} <- previous do
        case v do
          {:ok, value} -> Application.put_env(:dawarich, k, value)
          :error -> Application.delete_env(:dawarich, k)
        end
      end
    end)

    :ok
  end

  @tag envelope: :suffix
  test "HTML suffixes select the original handler and constraints for every audited page" do
    assert length(@routes) == 62
    assert request("/imports/42.html", [], false).status == 302

    for %{"route" => pattern} <- @routes, pattern != "/" do
      path = concrete(pattern)
      prepared = Strangler.call(Plug.Test.conn(:get, path <> ".html"), [])
      assert prepared.path_info == Plug.Test.conn(:get, path).path_info, pattern
      base = Phoenix.Router.route_info(DawarichWeb.Router, "GET", path, "localhost")

      formatted =
        Phoenix.Router.route_info(DawarichWeb.Router, "GET", prepared.path_info, "localhost")

      assert base == formatted, pattern
    end

    for path <- ~w(/tags /stats /map/v2 /settings/general /family/new /insights/details) do
      assert request(path <> ".html").status == @source[path]["suffix"]["status"], path
    end
  end

  @tag envelope: :query
  test "explicit HTML query format overrides Accept without polluting page gates" do
    for path <- ~w(/tags /tags/new /trips/new /settings/visits /map/timeline_feeds/calendar) do
      conn = request(path <> "?format=html", [{"accept", "application/json"}])
      assert conn.status == 200, path
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    end

    guest = request("/tags.html?format=html", [], false)

    {:ok, stored} =
      Dawarich.RailsCookies.decrypt(
        guest.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        Dawarich.RailsSecret.fetch(),
        DateTime.utc_now()
      )

    assert stored["user_return_to"] == "/tags.html?format=html"
    conn = request("/map/timeline_feeds/calendar.html?format=turbo_stream")
    assert conn.status == 200
    refute conn.resp_body =~ "<turbo-stream"
  end

  @tag envelope: :xhr
  test "XHR HTML requests render the same native page instead of a terminal refusal" do
    for path <- ~w(/tags /map /stats /imports /exports /insights /settings/general /family/new) do
      conn = request(path, [{"x-requested-with", "XMLHttpRequest"}, {"accept", "text/html"}])
      assert conn.status == @source[path]["xhr"]["status"], path
      assert conn.resp_body =~ "<html"
      refute conn.resp_body =~ "Unprocessable Entity"
    end

    assert request("/tags", [{"x-requested-with", "XMLHttpRequest"}, {"accept", ""}]).status ==
             200

    bare = request("/tags", [{"x-requested-with", "XMLHttpRequest"}, {"accept", ""}])
    refute bare.resp_body =~ "<html"
    js = request("/tags", [{"x-requested-with", "XMLHttpRequest"}, {"accept", "text/javascript"}])
    assert js.status == 200
    refute js.resp_body =~ "<html"
    absent = request("/tags", [{"x-requested-with", "XMLHttpRequest"}, {"accept", nil}])
    assert absent.status == @source["_raw_xhr"]["status"]
    refute absent.resp_body =~ "<html"

    assert request("/map/timeline_feeds/calendar", [
             {"x-requested-with", "XMLHttpRequest"},
             {"accept", nil}
           ]).status == 406

    guest = request("/tags", [{"x-requested-with", "XMLHttpRequest"}], false)
    assert guest.status == 401
    assert guest.resp_body == "You need to sign in or sign up before continuing."
    assert get_resp_header(guest, "location") == []
  end

  @tag envelope: :formatted_xhr
  test "explicit HTML formats override the implicit XHR fragment layout" do
    for target <- ~w(/tags.html /tags?format=html /tags.html?format=turbo_stream),
        accept <- [nil, ""] do
      conn = request(target, [{"x-requested-with", "XMLHttpRequest"}, {"accept", accept}])
      document? = String.contains?(conn.resp_body, "<html")
      assets? = String.contains?(conn.resp_body, "/assets/application.css")
      assert conn.status == 200
      assert document?, target
      assert assets?, target
    end
  end

  @tag envelope: :stream
  test "Turbo-only calendar streams and redirect actions preserve Rails successes" do
    conn =
      request("/map/timeline_feeds/calendar?month=2026-10", [
        {"accept", "text/vnd.turbo-stream.html"}
      ])

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/vnd.turbo-stream.html; charset=utf-8"]
    assert conn.resp_body =~ ~s(<turbo-stream action="replace" target="timeline-calendar-frame")

    assert request("/map/timeline_feeds/calendar?format=turbo_stream").resp_body =~
             "<turbo-stream"

    assert request("/map/timeline_feeds/calendar.turbo_stream").resp_body =~ "<turbo-stream"

    for path <- ["/", "/trial/upgrade", "/settings/theme?theme=dark"] do
      conn = request(path, [{"accept", "text/vnd.turbo-stream.html"}])
      assert conn.status == 302, path
      assert get_resp_header(conn, "location") != []
    end

    assert request("/tags", [{"accept", "text/vnd.turbo-stream.html"}]).status == 406

    for path <-
          ~w(/digests/2026 /family /family/edit /shared/digest/00000000-0000-4000-8000-000000000042) do
      assert request(path, [{"accept", "text/vnd.turbo-stream.html"}]).status == 302, path
    end

    assert request("/tags", [{"accept", "text/vnd.turbo-stream.html"}], false).status == 302

    assert request("/places/nearby?latitude=51&longitude=12", [
             {"accept", "text/vnd.turbo-stream.html"}
           ]).status == 500
  end

  @tag envelope: :frame
  test "Turbo frame pages use the Rails minimal frame layout while document visits stay native" do
    for path <- ~w(/tags /map /stats /imports /exports /settings/general /family/new) do
      conn =
        request(path, [
          {"turbo-frame", "envelope-frame"},
          {"x-turbo-request-id", "synthetic-visit"}
        ])

      assert conn.status == 200, path
      assert conn.resp_body =~ "<html"
      refute conn.resp_body =~ "turbo-visit-control"

      if path in ~w(/map /map/v2),
        do: assert(conn.resp_body =~ "/assets/application.css"),
        else: refute(conn.resp_body =~ "/assets/application.css")
    end

    hub = request("/share_links/hub", [{"turbo-frame", "envelope-frame"}])
    assert hub.status == 200
    assert hub.resp_body =~ "<html"
    refute hub.resp_body =~ "/assets/application.css"
    form = request("/share_links/live/new", [{"turbo-frame", "envelope-frame"}])
    assert form.status == 200
    refute form.resp_body =~ "<html"
    conn = request("/tags", [{"x-turbo-request-id", "synthetic-visit"}])
    assert conn.status == 200
    refute conn.resp_body =~ "turbo-visit-control"
    assert conn.resp_body =~ "/assets/application.css"
  end

  @tag envelope: :navigation
  test "historical Turbo native navigation endpoints return the exact Rails HTML in every envelope" do
    for {action, body} <- [
          {"recede", "Going back…"},
          {"resume", "Staying put…"},
          {"refresh", "Refreshing…"}
        ],
        suffix <- ["", ".html", ".json", "?format=html", "?format=json"],
        headers <- [
          [],
          [{"accept", "text/vnd.turbo-stream.html"}],
          [{"x-requested-with", "XMLHttpRequest"}]
        ] do
      conn = request("/#{action}_historical_location" <> suffix, headers, false)
      assert conn.status == 200
      assert conn.resp_body == body
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    end

    conn = request("/recede_historical_location", [], false, :head)
    assert conn.status == 200
    assert conn.resp_body == ""
  end

  @tag envelope: :coexistence
  test "coexistence retains the original envelope refusal and Turbo visit reload" do
    System.delete_env("DAWARICH_RAILS")

    for {target, headers} <- [
          {"/tags.html", []},
          {"/tags?format=html", []},
          {"/tags", [{"x-requested-with", "XMLHttpRequest"}]},
          {"/tags", [{"accept", "text/vnd.turbo-stream.html"}]}
        ] do
      conn =
        Enum.reduce(headers, Plug.Test.conn(:get, target), fn {k, v}, c ->
          put_req_header(c, k, v)
        end)

      refute Strangler.page_request?(conn)
    end

    assert DawarichWeb.TurboVisit.call(
             Plug.Test.conn(:get, "/tags") |> put_req_header("x-turbo-request-id", "synthetic"),
             []
           ).resp_body =~ "turbo-visit-control"
  end

  defp concrete(pattern) do
    pattern
    |> String.replace(~r/:uuid|:token/, "00000000-0000-4000-8000-000000000042")
    |> String.replace(":year", "2026")
    |> String.replace(":month", "10")
    |> String.replace(~r/:[a-z_]+/, "42")
  end

  defp request(path, headers \\ [], signed_in \\ true, method \\ :get) do
    conn = Plug.Test.conn(method, path) |> put_req_header("accept", "text/html")

    conn =
      if signed_in,
        do:
          put_req_header(
            conn,
            "cookie",
            "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(880_001))
          ),
        else: conn

    conn =
      Enum.reduce(headers, conn, fn
        {k, nil}, c -> delete_req_header(c, k)
        {k, v}, c -> put_req_header(c, k, v)
      end)

    Endpoint.call(conn, Endpoint.init([]))
  end
end

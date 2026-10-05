defmodule DawarichWeb.InsightsEndpointTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP
  import Phoenix.ConnTest, only: [get: 2, html_response: 2]
  import Phoenix.LiveViewTest, only: [live: 1, render: 1]

  @endpoint DawarichWeb.Endpoint

  alias Dawarich.Test.{InsightsSeeds, RailsUser, TripsSeeds}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    Dawarich.State.put_registration_enabled(Dawarich.Repo, false)
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    routes = Application.get_env(:dawarich, :rails_routes, [])

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, nil)
      Application.put_env(:dawarich, :rails_routes, routes)
    end)

    TripsSeeds.user!(9301, %{"timezone" => "Europe/Berlin", "maps" => %{"distance_unit" => "km"}})
    InsightsSeeds.start_cache!()

    %{
      upstream: upstream,
      port: serve(),
      cookie: "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(9301))
    }
  end

  defp serve do
    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    port
  end

  defp request(target, headers, method \\ "GET") do
    lines = Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end)
    "#{method} #{target} HTTP/1.1\r\nHost: a\r\n#{lines}Content-Length: 0\r\n\r\n"
  end

  defp phoenix(port, request) do
    client = connect(port)
    send_raw(client, request)
    read_response(client)
  end

  defp puma(port, upstream, request) do
    client = connect(port)
    send_raw(client, request)
    puma = accept(upstream)
    {head, _rest} = read_head(puma)
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
    assert {200, _headers, "puma"} = read_response(client)
    {request_line(head), header(head, "cookie")}
  end

  test "a signed-in Turbo frame request gets the details frame in Turbo's minimal layout", ctx do
    frame = [{"Cookie", ctx.cookie}, {"Turbo-Frame", "insights_details"}]

    assert {200, _headers, body} =
             phoenix(ctx.port, request("/insights/details?year=all", frame))

    assert String.starts_with?(body, "<html>")
    assert body =~ ~s(<turbo-frame id="insights_details">)

    for absent <- ["<!DOCTYPE", "<title", "<script", "class=\"navbar"],
        do: refute(body =~ absent, "frame response contains #{absent}")
  end

  test "a direct signed-in request gets the app layout with the navbar", ctx do
    assert {200, _headers, body} =
             phoenix(ctx.port, request("/insights/details?year=all", [{"Cookie", ctx.cookie}]))

    assert body =~ "<!DOCTYPE html>"
    assert body =~ ~s(<div class="navbar bg-base-100 h-16">)
    assert body =~ ~s(<turbo-frame id="insights_details">)
  end

  test "a signed-in visit to / is redirected to the map by Phoenix", ctx do
    assert {302, headers, ""} = phoenix(ctx.port, request("/", [{"Cookie", ctx.cookie}]))
    assert values(headers, "location") == ["http://a/map/v2"]
  end

  test "guest root renders native public home and details go to Puma intact", ctx do
    assert {200, _headers, body} = phoenix(ctx.port, request("/", []))
    assert body =~ "The only location history tracker"
    assert body =~ ~s(href="/users/sign_in")

    target = "/insights/details?year=2024"
    assert {line, []} = puma(ctx.port, ctx.upstream, request(target, []))
    assert line == "GET #{target} HTTP/1.1"
  end

  test "writes, formats, JSON and XHR go to Puma with the Rails cookie", ctx do
    cookie = {"Cookie", ctx.cookie}

    for {method, target, headers} <- [
          {"POST", "/insights/details", [cookie]},
          {"GET", "/insights/details?format=csv", [cookie]},
          {"GET", "/insights/details.csv", [cookie]},
          {"GET", "/insights/details", [cookie, {"Accept", "application/json"}]},
          {"GET", "/insights/details", [cookie, {"X-Requested-With", "XMLHttpRequest"}]}
        ] do
      assert {line, [forwarded]} = puma(ctx.port, ctx.upstream, request(target, headers, method))
      assert line == "#{method} #{target} HTTP/1.1"
      assert forwarded == ctx.cookie
    end
  end

  test "home and insights independently hand their owned paths to Puma", ctx do
    Application.put_env(:dawarich, :rails_routes, ["insights"])
    assert {302, headers, ""} = phoenix(ctx.port, request("/", [{"Cookie", ctx.cookie}]))
    assert values(headers, "location") == ["http://a/map/v2"]

    for {key, target} <- [{"home", "/"}, {"insights", "/insights/details?year=all"}] do
      Application.put_env(:dawarich, :rails_routes, [key])

      assert {line, [_cookie]} =
               puma(ctx.port, ctx.upstream, request(target, [{"Cookie", ctx.cookie}]))

      assert line == "GET #{target} HTTP/1.1"
    end

    Application.put_env(:dawarich, :rails_routes, ["home"])

    assert {200, _headers, body} =
             phoenix(ctx.port, request("/insights/details?year=all", [{"Cookie", ctx.cookie}]))

    assert body =~ ~s(<turbo-frame id="insights_details">)
  end

  test "a non-string year or month goes to Puma", ctx do
    for target <- [
          "/insights/details?year%5B%5D=2024",
          "/insights/details?year=2024&month%5Bx%5D=4"
        ] do
      assert {line, [_cookie]} =
               puma(ctx.port, ctx.upstream, request(target, [{"Cookie", ctx.cookie}]))

      assert line == "GET #{target} HTTP/1.1"
    end
  end

  defp digest_user!(ctx) do
    InsightsSeeds.user!()
    InsightsSeeds.yearly_digest!()
    InsightsSeeds.monthly_digest!(4, ~N[2024-04-01 00:00:00])
    Map.put(ctx, :cookie, "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(93)))
  end

  defp digests, do: Dawarich.Repo.query!("SELECT id, updated_at FROM digests ORDER BY id").rows

  test "warm nil stale cold failed and handed-back details preserve existing proxy admission",
       ctx do
    oracle =
      Path.expand("../fixtures/a12d1b4/cache.json", __DIR__) |> File.read!() |> Jason.decode!()

    ctx = digest_user!(ctx)
    cookie = ctx.cookie
    frame = [{"Cookie", cookie}, {"Turbo-Frame", "insights_details"}, {"Accept", "text/html"}]
    target = "/insights/details?year=2024&month=4&user_id=9301"
    key = Dawarich.Insights.Details.yearly_key(93, 2024, ~N[2024-03-05 00:00:00])
    before = digests()

    for state <- ~w(warm stale_snapshot cached_nil cold corrupt) do
      expected = Enum.find(oracle["readers"], &(&1["state"] == state))
      assert expected["calculation_calls"] == 0
      Dawarich.Redis.cache_command(["DEL", key])

      if state == "stale_snapshot",
        do: Dawarich.Repo.query!("UPDATE digests SET distance=888 WHERE id=71", [])

      if state in ~w(warm stale_snapshot), do: InsightsSeeds.warm!()
      if state == "cached_nil", do: InsightsSeeds.cache!(key, Base.decode64!(expected["wire"]))
      if state == "corrupt", do: Dawarich.Redis.cache_command(["SET", key, "corrupt fixture"])

      if state in ~w(warm stale_snapshot cached_nil) do
        assert {200, headers, body} = phoenix(ctx.port, request(target, frame))
        assert values(headers, "content-type") == ["text/html; charset=utf-8"]
        assert body =~ ~s(<turbo-frame id="insights_details">)
        refute body =~ "<!DOCTYPE"
        client = connect(ctx.port)
        send_raw(client, request(target, frame, "HEAD"))
        assert {200, _, ""} = read_response(client, method: "HEAD")
      else
        assert {line, [^cookie]} = puma(ctx.port, ctx.upstream, request(target, frame))
        assert line == "GET #{target} HTTP/1.1"
      end

      assert digests() == before
    end

    InsightsSeeds.warm!()
    Application.put_env(:dawarich, :rails_routes, ["insights"])
    assert {line, [^cookie]} = puma(ctx.port, ctx.upstream, request(target, frame))
    assert line == "GET #{target} HTTP/1.1"
    Application.put_env(:dawarich, :rails_routes, [])

    for {path, headers} <- [
          {target, []},
          {"/insights/details?year%5B%5D=2025", frame},
          {target, [{"Cookie", cookie}, {"Accept", "application/json"}]}
        ] do
      assert {line, _} = puma(ctx.port, ctx.upstream, request(path, headers))
      assert line == "GET #{path} HTTP/1.1"
    end

    stop_supervised!(Dawarich.Redis.Cache)
    assert {line, [^cookie]} = puma(ctx.port, ctx.upstream, request(target, frame))
    assert line == "GET #{target} HTTP/1.1"
    assert digests() == before
  end

  test "disconnected and connected mounts preserve source fragment hits write policy and TTL" do
    before = digests()
    conn = get(RailsUser.signed_in(9301), "/insights/details?year=all")
    assert html_response(conn, 200) =~ ~s(<turbo-frame id="insights_details">)
    assert {:ok, keys} = Dawarich.Redis.cache_command(["KEYS", "views/*"])
    assert length(keys) == 6

    for key <- keys do
      assert {:ok, ttl} = Dawarich.Redis.cache_command(["TTL", key])
      assert ttl > 86_390 and ttl <= 86_400
      Dawarich.RailsCache.put(key, "<b>source mount fragment</b>", expires_in: 86400)
    end

    {:ok, view, html} = live(RailsUser.connecting_as(conn, 9301))
    assert length(String.split(html, "source mount fragment")) == 7
    assert render(view) =~ "source mount fragment"
    for key <- keys, do: Dawarich.Redis.cache_command(["DEL", key])
    GenServer.stop(view.pid)
    {:ok, view, html} = live(RailsUser.connecting_as(conn, 9301))
    assert html =~ ~s(<turbo-frame id="insights_details">)
    refute render(view) =~ "source mount fragment"
    assert {:ok, []} = Dawarich.Redis.cache_command(["KEYS", "views/*"])
    assert digests() == before
  end

  test "a warm yearly digest is answered by Phoenix without writing digests", ctx do
    ctx = digest_user!(ctx)
    InsightsSeeds.warm!()
    before = digests()
    frame = [{"Cookie", ctx.cookie}, {"Turbo-Frame", "insights_details"}]

    assert {200, _headers, body} =
             phoenix(ctx.port, request("/insights/details?year=2024&month=4", frame))

    assert body =~ ~s(<turbo-frame id="insights_details">)
    assert digests() == before
  end

  test "a digest Rails would calculate or cache sends the request to Puma unchanged", ctx do
    ctx = digest_user!(ctx)
    cookie = [{"Cookie", ctx.cookie}]

    for target <- ["/insights/details?year=2024&month=4", "/insights/details?year=2024&month=3"] do
      if target =~ "month=3", do: InsightsSeeds.warm!()
      assert {line, [_cookie]} = puma(ctx.port, ctx.upstream, request(target, cookie))
      assert line == "GET #{target} HTTP/1.1"
    end

    assert length(digests()) == 2
  end

  test "a cached value that is not a digest hands the request to Puma", ctx do
    ctx = digest_user!(ctx)
    InsightsSeeds.warm!(<<0, 17, 1, -1.0::little-float-64, -1::little-signed-32, 4, 8, ?i, 86>>)
    target = "/insights/details?year=2024&month=4"

    assert {_line, [_cookie]} =
             puma(ctx.port, ctx.upstream, request(target, [{"Cookie", ctx.cookie}]))
  end

  test "a gate that cannot read the database hands the request to Puma", ctx do
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :manual)
    target = "/insights/details?year=all"

    assert {_line, [_cookie]} =
             puma(ctx.port, ctx.upstream, request(target, [{"Cookie", ctx.cookie}]))
  end

  test "a connected details LiveView renders the frame and writes no fragments" do
    conn = get(RailsUser.signed_in(9301), "/insights/details?year=all")
    assert html_response(conn, 200) =~ ~s(<turbo-frame id="insights_details">)
    assert {:ok, [_ | _]} = Dawarich.Redis.cache_command(["KEYS", "views/*"])
    {:ok, "OK"} = Dawarich.Redis.cache_command(["FLUSHDB"])
    {:ok, view, _html} = live(RailsUser.connecting_as(conn, 9301))
    assert render(view) =~ ~s(<turbo-frame id="insights_details">)
    assert {:ok, []} = Dawarich.Redis.cache_command(["KEYS", "views/*"])
  end
end

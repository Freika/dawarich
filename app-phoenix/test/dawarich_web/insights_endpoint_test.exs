defmodule DawarichWeb.InsightsEndpointTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP
  import Phoenix.ConnTest, only: [get: 2, html_response: 2]
  import Phoenix.LiveViewTest, only: [live: 1, render_async: 2]

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

  defp assert_details_document(html) do
    document = LazyHTML.from_document(html)

    assert document
           |> LazyHTML.query(
             "#insights-details-loading, #insights-details-ready, #insights-details-pending"
           )
           |> Enum.count() == 1

    assert document |> LazyHTML.query("#insights-period") |> Enum.count() == 0
  end

  test "old framed native details requests receive the full authorized native document", ctx do
    frame = [{"Cookie", ctx.cookie}, {"Turbo-Frame", "insights_details"}]

    assert {200, _headers, body} =
             phoenix(ctx.port, request("/insights/details?year=all", frame))

    assert body =~ "<!DOCTYPE html>"
    assert_details_document(body)
    assert body =~ "navbar"
    refute body =~ "turbo-frame"
    refute body =~ "type=\"importmap\""
  end

  test "a direct signed-in request gets the app layout with the navbar", ctx do
    assert {200, _headers, body} =
             phoenix(ctx.port, request("/insights/details?year=all", [{"Cookie", ctx.cookie}]))

    assert body =~ "<!DOCTYPE html>"
    assert body =~ ~s(<div class="navbar bg-base-100 h-16">)
    assert_details_document(body)
  end

  test "a signed-in visit to / is redirected to the map by Phoenix", ctx do
    assert {302, headers, ""} = phoenix(ctx.port, request("/", [{"Cookie", ctx.cookie}]))
    assert values(headers, "location") == ["http://a/map/v2"]
  end

  test "guest root and details redirect to sign in", ctx do
    assert {302, root_headers, ""} = phoenix(ctx.port, request("/", []))
    assert values(root_headers, "location") == ["http://a/users/sign_in"]

    target = "/insights/details?year=2024"
    assert {302, headers, ""} = phoenix(ctx.port, request(target, []))
    assert values(headers, "location") == ["http://a/users/sign_in"]
  end

  test "external details writes preserve the cookie while native formats refuse without forwarding",
       ctx do
    cookie = {"Cookie", ctx.cookie}

    assert {404, _, _} = phoenix(ctx.port, request("/insights/details", [cookie], "POST"))
    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)

    for {target, headers, status} <- [
          {"/insights/details?format=csv", [cookie], 406},
          {"/insights/details.csv", [cookie], 406},
          {"/insights/details", [cookie, {"Accept", "application/json"}], 406},
          {"/insights/details", [cookie, {"X-Requested-With", "XMLHttpRequest"}], 200}
        ] do
      assert {^status, _, body} = phoenix(ctx.port, request(target, headers))
      refute body == "puma"
    end
  end

  test "home rollback remains while independent native insights stays owned", ctx do
    Application.put_env(:dawarich, :rails_routes, ["insights"])
    assert {302, headers, ""} = phoenix(ctx.port, request("/", [{"Cookie", ctx.cookie}]))
    assert values(headers, "location") == ["http://a/map/v2"]

    for {key, target} <- [{"home", "/"}] do
      Application.put_env(:dawarich, :rails_routes, [key])

      assert {302, headers, ""} = phoenix(ctx.port, request(target, [{"Cookie", ctx.cookie}]))
      assert values(headers, "location") == ["http://a/map/v2"]
      assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
    end

    Application.put_env(:dawarich, :rails_routes, ["home"])

    assert {200, _headers, body} =
             phoenix(ctx.port, request("/insights/details?year=all", [{"Cookie", ctx.cookie}]))

    assert_details_document(body)
  end

  test "a non-string year or month fails natively", ctx do
    for target <- [
          "/insights/details?year%5B%5D=2024",
          "/insights/details?year=2024&month%5Bx%5D=4"
        ] do
      assert {200, _headers, body} = phoenix(ctx.port, request(target, [{"Cookie", ctx.cookie}]))
      assert body =~ "alert"
    end
  end

  defp digest_user!(ctx) do
    InsightsSeeds.user!()
    InsightsSeeds.yearly_digest!()
    InsightsSeeds.monthly_digest!(4, ~N[2024-04-01 00:00:00])
    Map.put(ctx, :cookie, "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(93)))
  end

  defp digests, do: Dawarich.Repo.query!("SELECT id, updated_at FROM digests ORDER BY id").rows

  test "warm nil stale cold failed and legacy rollback details preserve native ownership", ctx do
    ctx = digest_user!(ctx)
    frame = [{"Cookie", ctx.cookie}, {"Turbo-Frame", "insights_details"}, {"Accept", "text/html"}]
    target = "/insights/details?year=2024&month=4&user_id=9301"
    key = Dawarich.Insights.Details.yearly_key(93, 2024, ~N[2024-03-05 00:00:00])

    for state <- ~w(warm stale_snapshot cached_nil cold corrupt) do
      Dawarich.Redis.cache_command(["DEL", key])
      if state in ~w(warm stale_snapshot), do: InsightsSeeds.warm!()

      if state == "cached_nil" do
        oracle =
          File.read!(Path.expand("../fixtures/a12d1b4/cache.json", __DIR__)) |> Jason.decode!()

        value = Enum.find(oracle["readers"], &(&1["state"] == state))
        InsightsSeeds.cache!(key, Base.decode64!(value["wire"]))
      end

      if state == "corrupt", do: Dawarich.Redis.cache_command(["SET", key, "corrupt fixture"])
      assert {200, headers, body} = phoenix(ctx.port, request(target, frame))
      assert values(headers, "content-type") == ["text/html; charset=utf-8"]
      assert_details_document(body)
      assert body =~ "<!DOCTYPE"
    end

    assert Dawarich.Repo.query!("SELECT count(*) FROM phoenix.rails_commands", []).rows == [[0]]
    Application.put_env(:dawarich, :rails_routes, ["insights"])
    assert {200, _, body} = phoenix(ctx.port, request(target, frame))
    assert_details_document(body)
    Application.put_env(:dawarich, :rails_routes, [])
    stop_supervised!(Dawarich.Redis.Cache)
    assert {200, _headers, _body} = phoenix(ctx.port, request(target, frame))
  end

  test "native disconnected and connected details ignore source HTML cache without writes" do
    before = digests()
    conn = get(RailsUser.signed_in(9301), "/insights/details?year=all")
    assert_details_document(html_response(conn, 200))
    assert {:ok, []} = Dawarich.Redis.cache_command(["KEYS", "views/*"])
    user = Dawarich.Accounts.get(9301)
    data = Dawarich.Insights.Details.load(user, %{"year" => "all"})

    keys =
      for name <-
            ~w(year_comparison activity_breakdown location_clusters monthly_digest travel_patterns movement_wellness),
          do: Dawarich.Insights.Fragments.key(user, "en", data, name)

    for key <- keys,
        do: Dawarich.RailsCache.put(key, "<b>source mount fragment</b>", expires_in: 86400)

    {:ok, view, html} = live(RailsUser.connecting_as(conn, 9301))
    refute html =~ "source mount fragment"
    refute render_async(view, 5000) =~ "source mount fragment"
    for key <- keys, do: Dawarich.Redis.cache_command(["DEL", key])
    GenServer.stop(view.pid)
    {:ok, view, html} = live(RailsUser.connecting_as(conn, 9301))
    assert_details_document(html)
    refute render_async(view, 5000) =~ "source mount fragment"
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

    assert_details_document(body)
    assert digests() == before
  end

  test "cold native details publish durable refresh without calculating on either GET", ctx do
    Dawarich.Repo.query!("SELECT setval('digests_id_seq', 71, false)")
    ctx = digest_user!(ctx)
    cookie = [{"Cookie", ctx.cookie}]
    before = digests()

    for target <- ["/insights/details?year=2024&month=4", "/insights/details?year=2024&month=3"] do
      if target =~ "month=3", do: InsightsSeeds.warm!()
      assert {200, _headers, body} = phoenix(ctx.port, request(target, cookie))
      assert_details_document(body)
    end

    assert digests() == before

    assert Dawarich.Repo.query!(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Stats.PageRefreshWorker'",
             []
           ).rows == [[2]]
  end

  test "a corrupt legacy cache cannot replace native persisted details", ctx do
    ctx = digest_user!(ctx)
    InsightsSeeds.warm!(<<0, 17, 1, -1.0::little-float-64, -1::little-signed-32, 4, 8, ?i, 86>>)
    target = "/insights/details?year=2024&month=4"

    assert {200, _headers, body} = phoenix(ctx.port, request(target, [{"Cookie", ctx.cookie}]))
    assert_details_document(body)
  end

  test "a native read that cannot access the database fails natively", ctx do
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :manual)
    target = "/insights/details?year=all"

    assert {500, _headers, _body} = phoenix(ctx.port, request(target, [{"Cookie", ctx.cookie}]))
  end

  test "connected native details render persisted values without HTML fragments" do
    conn = get(RailsUser.signed_in(9301), "/insights/details?year=all")
    assert_details_document(html_response(conn, 200))
    assert {:ok, []} = Dawarich.Redis.cache_command(["KEYS", "views/*"])
    {:ok, "OK"} = Dawarich.Redis.cache_command(["FLUSHDB"])
    {:ok, view, _html} = live(RailsUser.connecting_as(conn, 9301))
    assert render_async(view, 5000) =~ ~s(id="insights-details-ready")
    assert {:ok, []} = Dawarich.Redis.cache_command(["KEYS", "views/*"])
  end
end

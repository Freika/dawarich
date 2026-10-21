defmodule DawarichWeb.EndpointTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP

  setup do
    upstream = listen()

    previous =
      Map.new([:rails_upstream, :rails_routes], &{&1, Application.fetch_env(:dawarich, &1)})

    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, configured} -> Application.put_env(:dawarich, key, configured)
          :error -> Application.delete_env(:dawarich, key)
        end
      end
    end)

    %{upstream: upstream}
  end

  defp serve(extra \\ []) do
    bandit =
      start_supervised!(
        {Bandit,
         [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0) ++ extra}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    port
  end

  @tag a10_boundary: :id
  test "unroutable user export never matches the numeric target route" do
    a10_actor!()

    for suffix <- ["", "/edit"] do
      route =
        Phoenix.Router.route_info(
          DawarichWeb.Router,
          "GET",
          "/settings/users/10001" <> suffix,
          "a"
        )

      refute Map.has_key?(route, :rails_gate)

      assert true ==
               not DawarichWeb.NativeRequest.call(Dawarich.Test.RailsUser.signed_in(10001), []).halted

      assert DawarichWeb.RouteConstraints.valid?(route)
      refute DawarichWeb.RouteConstraints.valid?(%{route | path_params: %{"id" => "export"}})

      refute DawarichWeb.RouteConstraints.valid?(%{
               route
               | path_params: %{"id" => "1000000000000000000"}
             })
    end
  end

  defp a10_actor! do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    Dawarich.State.put_registration_enabled(Dawarich.Repo, false)
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    original = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")
    Application.put_env(:dawarich, :rails_routes, [])

    on_exit(fn ->
      if original,
        do: System.put_env("SELF_HOSTED", original),
        else: System.delete_env("SELF_HOSTED")
    end)

    Dawarich.Test.RailsUser.insert!(%{
      id: 10001,
      email: "a10-route@example.invalid",
      admin: true,
      api_key: "a10-k-10001",
      settings: %{"timezone" => "Europe/Berlin", "onboarding_completed" => true}
    })

    "Cookie: _dawarich_session=#{Dawarich.Test.RailsUser.cookie(Dawarich.Test.RailsUser.session(10001))}\r\n"
  end

  test "Phoenix answers /notifications itself" do
    client = connect(serve())
    send_raw(client, "GET /notifications HTTP/1.1\r\nHost: a\r\n\r\n")

    assert {302, headers, _body} = read_response(client)
    assert values(headers, "location") == ["http://a/users/sign_in"]
    assert values(headers, "x-frame-options") == ["SAMEORIGIN"]
  end

  defp assert_write_transport(port, upstream, request, method, target) do
    path = URI.parse(target).path
    route = Phoenix.Router.route_info(DawarichWeb.Router, method, path, "a")
    conn = %{method: method, path_info: String.split(path, "/", trim: true)}

    expected =
      cond do
        String.starts_with?(path, "/settings/") or path == "/users" -> [302, 303, 404, 422]
        DawarichWeb.NativeM4RetiredWrites.retired?(conn) or route == :error -> [404]
        method == "POST" and path == "/exports" -> [422]
        method == "GET" -> [200, 302, 404]
        true -> [302, 422]
      end

    assert answered_by_phoenix(port, request) in expected
    assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 0)
  end

  defp answered_by_phoenix(port, request) do
    client = connect(port)
    send_raw(client, request)
    {status, _headers, _body} = read_response(client)
    status
  end

  test "retired no-socket notification writes refuse without Puma", ctx do
    port = serve()

    for target <- ~w(/notifications/mark_as_read /notifications/destroy_all /notifications/5) do
      body = "_method=post&authenticity_token=x"

      request =
        "POST #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert answered_by_phoenix(port, request) == 404
      assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
    end
  end

  test "Phoenix answers the imports and exports lists itself" do
    port = serve()

    for target <-
          ~w(/imports /imports/new /exports /imports?page=2 /exports?order_by=asc&sort_by=name) do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302, target
    end
  end

  test "router lists exactly the owned import and export methods" do
    actual =
      DawarichWeb.Router.__routes__()
      |> Enum.filter(&String.starts_with?(&1.path, ["/imports", "/exports"]))
      |> Enum.map(&{String.upcase(to_string(&1.verb)), &1.path})
      |> Enum.sort()

    expected = [
      {"GET", "/imports"},
      {"GET", "/imports/new"},
      {"GET", "/imports/:id"},
      {"GET", "/imports/:id/edit"},
      {"GET", "/imports/:id/download"},
      {"GET", "/exports"},
      {"POST", "/exports"}
    ]

    assert actual == Enum.sort(expected)
  end

  test "signed-out retired import writes refuse without Puma", ctx do
    port = serve()
    body = "import%5Bname%5D=x"

    for {method, target} <- [
          {"POST", "/imports"},
          {"POST", "/imports/5"},
          {"PATCH", "/imports/5"},
          {"DELETE", "/imports/5"},
          {"POST", "/imports/5/extraction"},
          {"DELETE", "/imports/5/extraction"}
        ] do
      client = connect(port)

      send_raw(
        client,
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"
      )

      assert {404, _, _} = read_response(client)
      assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
    end
  end

  test "foreign and unsupported import documents refuse natively while downloads retain their contract",
       ctx do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    alias Dawarich.Test.{RailsUser, ImportsExportsSeeds}
    RailsUser.insert!(%{id: 7691, email: "tcp-owner@example.test"})
    RailsUser.insert!(%{id: 7692, email: "tcp-foreign@example.test"})
    ImportsExportsSeeds.import!(%{id: 769_101, user_id: 7691, name: "private-owner.gpx"})
    ImportsExportsSeeds.import!(%{id: 769_102, user_id: 7692, name: "unsupported", source: 16})
    ImportsExportsSeeds.import!(%{id: 769_103, user_id: 7692, name: "own.geojson", source: 6})
    session = RailsUser.session(7692)
    cookie = RailsUser.cookie(session)
    token = DawarichWeb.RailsCsrf.masked_token(session)
    port = serve()

    for id <- [769_101, 769_102],
        target <- ["/imports/#{id}", "/imports/#{id}/edit"] do
      request = "GET #{target} HTTP/1.1\r\nHost: a\r\nCookie: _dawarich_session=#{cookie}\r\n\r\n"
      assert answered_by_phoenix(port, request) == 302
    end

    for id <- [769_101, 769_102] do
      target = "/imports/#{id}/download"
      request = "GET #{target} HTTP/1.1\r\nHost: a\r\nCookie: _dawarich_session=#{cookie}\r\n\r\n"
      assert answered_by_phoenix(port, request) == 404
      assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
    end

    body = "import%5Bname%5D=stolen"

    for id <- [769_101, 769_102],
        {method, target} <- [
          {"PATCH", "/imports/#{id}"},
          {"POST", "/imports/#{id}"},
          {"DELETE", "/imports/#{id}"},
          {"POST", "/imports/#{id}/extraction"},
          {"DELETE", "/imports/#{id}/extraction"}
        ] do
      request =
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\nCookie: _dawarich_session=#{cookie}\r\n" <>
          "X-CSRF-Token: #{token}\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert answered_by_phoenix(port, request) == 404
      assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
    end

    for target <- ["/imports/769103", "/imports/769103/edit"] do
      request = "GET #{target} HTTP/1.1\r\nHost: a\r\nCookie: _dawarich_session=#{cookie}\r\n\r\n"
      assert answered_by_phoenix(port, request) == 200
    end

    assert [["private-owner.gpx", 2], ["unsupported", 2], ["own.geojson", 2]] ==
             Dawarich.Repo.query!("SELECT name,status FROM imports ORDER BY id", [], log: false).rows
  end

  test "imports source override preserves reads but cannot revive retired writes", ctx do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    alias Dawarich.Test.{RailsUser, ImportsExportsSeeds}
    RailsUser.insert!(%{id: 7693, email: "tcp-handback@example.test"})
    ImportsExportsSeeds.import!(%{id: 769_301, user_id: 7693, name: "handback.gpx"})
    session = RailsUser.session(7693)
    cookie = "Cookie: _dawarich_session=#{RailsUser.cookie(session)}\r\n"
    token = "X-CSRF-Token: #{DawarichWeb.RailsCsrf.masked_token(session)}\r\n"
    port = serve()

    assert answered_by_phoenix(port, "GET /imports/769301 HTTP/1.1\r\nHost: a\r\n#{cookie}\r\n") ==
             200

    Application.put_env(:dawarich, :rails_routes, ["imports"])
    body = "import%5Bname%5D=renamed.gpx"

    for {method, target} <- [
          {"GET", "/imports"},
          {"GET", "/imports/new"},
          {"GET", "/imports/769301"},
          {"GET", "/imports/769301/edit"},
          {"GET", "/imports/769301/download"},
          {"POST", "/imports"},
          {"POST", "/imports/769301"},
          {"PATCH", "/imports/769301"},
          {"DELETE", "/imports/769301"},
          {"POST", "/imports/769301/extraction"},
          {"DELETE", "/imports/769301/extraction"}
        ] do
      request =
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\n#{cookie}#{token}" <>
          "Content-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert_write_transport(port, ctx.upstream, request, method, target)
    end

    assert [["handback.gpx", 2]] ==
             Dawarich.Repo.query!("SELECT name,status FROM imports", [], log: false).rows
  end

  @tag :tmp_dir
  test "a crashed listener comes back on its port while its old socket lingers, and leaves Puma running",
       %{tmp_dir: tmp_dir} do
    pidfile = Path.join(tmp_dir, "puma.pid")
    {:ok, probe} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(probe)
    :ok = :gen_tcp.close(probe)
    puma_argv = ["sh", "-c", "echo $$ > #{pidfile}; exec sleep 60"]
    plan = {:proxy, %{public: {{127, 0, 0, 1}, port}, upstream: 1, puma_argv: puma_argv}}

    :ok = Supervisor.terminate_child(Dawarich.Supervisor, DawarichWeb.Endpoint)

    on_exit(fn ->
      {:ok, _} = Supervisor.restart_child(Dawarich.Supervisor, DawarichWeb.Endpoint)
    end)

    start_supervised!(
      %{
        id: :front,
        type: :supervisor,
        start:
          {Supervisor, :start_link, [Dawarich.Front.children(plan), [strategy: :one_for_one]]}
      },
      restart: :temporary
    )

    puma = wait_for_file(pidfile)
    bandit = listener()
    lingering = hold_listen_socket(bandit)
    Process.exit(bandit, :kill)

    assert restarted_soon?(bandit)
    :ok = :socket.close(lingering)
    assert accepting_soon?(port)
    assert File.read!(pidfile) == puma
    assert {_, 0} = System.cmd("kill", ["-0", String.trim(puma)])
  end

  test "Phoenix answers the stats and digest pages itself" do
    port = serve()

    for target <-
          ~w(/stats /stats/2024 /stats/2024/3 /stats/2024/03 /stats/2024/12 /digests /digests/2024) do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302, target
    end
  end

  test "native stats and digest refusals preserve the native month and write owners",
       _ctx do
    port = serve()

    for target <-
          ~w(/stats/2024/0 /stats/2024/00 /stats/2024/13 /stats/2024/1a),
        do: assert(answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302)

    for target <-
          ~w(/stats/abcd /stats/202 /stats/20245 /stats/update_all /digests/new /digests/24) do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302
    end

    assert answered_by_phoenix(port, "GET /stats/2024.json HTTP/1.1\r\nHost: a\r\n\r\n") == 406

    for {method, target} <- [
          {"PUT", "/stats/update_all"},
          {"PUT", "/stats/2024/3/update"},
          {"PUT", "/stats/2024/all/update"},
          {"PATCH", "/stats/2024/3/sharing"},
          {"POST", "/digests?year=2023"},
          {"DELETE", "/digests/2023"},
          {"PATCH", "/digests/2023/sharing"}
        ] do
      body = "authenticity_token=x"

      request =
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert answered_by_phoenix(port, request) ==
               if(String.contains?(target, "/sharing"), do: 404, else: 302)
    end
  end

  test "independent native stats and digests ignore rollback including the activated month host",
       _ctx do
    Application.put_env(:dawarich, :rails_routes, ["stats", "digests"])
    port = serve()

    for target <- ~w(/stats/2024/3),
        do: assert(answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302)

    for target <- ~w(/stats /digests/2024),
        do: assert(answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302)
  end

  test "Phoenix answers the trips list for a signed-out visitor with Rails' sign-in redirect" do
    port = serve()

    for target <- ~w(/trips /trips?page=2) do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302, target
    end
  end

  test "native stats query admission stays owned while native trip query admission remains",
       _ctx do
    port = serve()

    for target <- ~w(/trips?page /trips?view) do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302
    end

    assert answered_by_phoenix(port, "GET /stats?year HTTP/1.1\r\nHost: a\r\n\r\n") == 302
    assert answered_by_phoenix(port, "GET /trips?page=2 HTTP/1.1\r\nHost: a\r\n\r\n") == 302
  end

  test "native trip forms refuse formats while retained writes preserve their owners", ctx do
    port = serve()

    for target <-
          ~w(/trips/new?format=json /trips/5/edit?format=json) do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 406
    end

    for {target, status} <- [
          {"/trips/abc", 302},
          {"/trips/12abc", 302},
          {"/trips/1234567890123456789", 302},
          {"/trips/5.json", 422},
          {"/trips.json", 422},
          {"/trips?format=json", 422}
        ] do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == status
      assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
    end

    assert answered_by_phoenix(port, "GET /trips/5/share_link/new HTTP/1.1\r\nHost: a\r\n\r\n") ==
             302

    for {method, target} <- [
          {"POST", "/trips"},
          {"PATCH", "/trips/5"},
          {"PUT", "/trips/5"},
          {"DELETE", "/trips/5"},
          {"POST", "/trips/5/recalculate"},
          {"POST", "/trips/5/export?file_format=gpx"},
          {"POST", "/trips/5/notes"},
          {"PATCH", "/trips/5/notes/7"},
          {"DELETE", "/trips/5/notes/7"},
          {"POST", "/trips/5/share_link"},
          {"DELETE", "/trips/5/share_link"},
          {"PATCH", "/trips/5/share_link/revoke"},
          {"POST", "/trips/5/share_link/regenerate"},
          {"POST", "/trips/5/share_link/regenerate_phrase"}
        ] do
      body = "_method=delete&authenticity_token=x"

      request =
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert_write_transport(port, ctx.upstream, request, method, target)
    end
  end

  test "native trip pages keep query admission despite obsolete ownership markers", _ctx do
    Application.put_env(:dawarich, :rails_routes, ["trips"])
    port = serve()

    for target <- ~w(/trips /trips?page=2 /trips/5) do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302
    end
  end

  test "DAWARICH_RAILS_ROUTES=sharing cannot hand native public pages and unlock back" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    Dawarich.Test.SharingSeeds.load!()
    Dawarich.FixtureCleanup.delete!(Dawarich.ScratchRepo, ~w(phoenix.counters))
    port = serve()
    id = "a9500000-0000-4000-8000-000000000001"
    page = "GET /s/#{id}?locale=de HTTP/1.1\r\nHost: a\r\n\r\n"

    unlock =
      "POST /s/#{id}/unlock HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
        "Content-Length: 8\r\n\r\nphrase=x"

    assert answered_by_phoenix(port, page) == 200
    assert answered_by_phoenix(port, unlock) == 401

    Application.put_env(:dawarich, :rails_routes, ["sharing"])
    on_exit(fn -> Application.delete_env(:dawarich, :rails_routes) end)

    assert answered_by_phoenix(port, page) == 200
    assert answered_by_phoenix(port, unlock) == 401
    assert Dawarich.Test.SharingSeeds.view_count(id) == 2
  end

  test "Phoenix answers the settings, account and insights pages itself" do
    port = serve()

    for target <-
          ~w(/settings/general /settings/visits /settings/integrations /settings/integrations?service=trek /settings/trek_sources/1/select_trips /users/edit /insights /insights?year=all&month=3 /insights/details?year=2024) do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302, target
    end
  end

  test "Phoenix answers both map paths itself", ctx do
    port = serve()

    for target <- ~w(/map /map/v2 /map/v2?date=2026-09-29&panel=timeline),
        do: assert(answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302)

    for target <- ~w(/maps/v2 /map/v1),
        do: assert(answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 301)

    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
  end

  test "native Places list ignores legacy ownership with the integrated map host", ctx do
    Application.put_env(:dawarich, :rails_routes, ["places"])
    on_exit(fn -> Application.delete_env(:dawarich, :rails_routes) end)
    port = serve()

    for target <- ~w(/places /places?page=2),
        do: assert(answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302)

    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
  end

  test "consumed map frames refuse while independent residency keeps HTTP admission", ctx do
    port = serve()
    accept = "Accept: text/html, application/xhtml+xml\r\n"

    for target <- [
          "/map/timeline_feeds/5/track_info",
          "/map/timeline_feeds?start_at=2026-09-27T00:00:00&end_at=2026-09-27T23:59:59",
          "/map/timeline_feeds/calendar?month=2026-09",
          "/map/timeline_feeds/calendar",
          "/map/residency?year=2026",
          "/map/residency",
          "/map/timeline_feeds/5/track_info?locale=de",
          "/map/timeline_feeds/5/track_info?client=ios",
          "/map/timeline_feeds/5/track_info?aff=a6s2",
          "/map/timeline_feeds/calendar?month=2026-09&via=a6s2",
          "/map/timeline_feeds?date=2026-09-29",
          "/map/timeline_feeds?start_at=&end_at=2026-09-27T23:59:59",
          "/map/timeline_feeds?start_at=Oct%2015%202025&end_at=2026-09-27T23:59:59",
          "/map/timeline_feeds?start_at[]=1&end_at=2",
          "/map/timeline_feeds?start_at=1&end_at=2&locale=de",
          "/map/timeline_feeds/calendar?month=2026-9",
          "/map/residency?year=abc",
          "/map/residency?year=",
          "/map/residency?year=2040",
          "/tracks/5/segments"
        ],
        do:
          assert(
            answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n#{accept}\r\n") ==
              if(String.starts_with?(target, "/map/residency"), do: 302, else: 410)
          )

    assert answered_by_phoenix(
             port,
             "GET /map/timeline_feeds/5/track_info HTTP/1.1\r\nHost: a\r\nX-Dawarich-Client: ios\r\n\r\n"
           ) == 410

    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
  end

  test "native map pages ignore coexistence switches and preserve their query", ctx do
    Application.put_env(:dawarich, :rails_routes, ["map"])
    on_exit(fn -> Application.delete_env(:dawarich, :rails_routes) end)
    port = serve()

    for target <- ~w(/map /map/v2?panel=timeline&date=2026-09-29),
        do: assert(answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302)

    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
    assert answered_by_phoenix(port, "GET /notifications HTTP/1.1\r\nHost: a\r\n\r\n") == 302
  end

  test "native timeline and unsupported map envelopes never reach Rails", ctx do
    port = serve()
    get = fn target, headers -> "GET #{target} HTTP/1.1\r\nHost: a\r\n#{headers}\r\n" end

    client = connect(port)
    send_raw(client, get.("/api/v1/timeline?start_at=1&end_at=2", ""))
    assert {401, headers, ""} = read_response(client)
    assert values(headers, "x-dawarich-response") == ["Hey, I'm alive!"]
    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)

    for {target, headers, status} <- [
          {"/map/v2", "Accept: application/json\r\n", 422},
          {"/map/v2?format=json", "", 422},
          {"/map/v2", "X-Requested-With: XMLHttpRequest\r\n", 422}
        ],
        do: assert(answered_by_phoenix(port, get.(target, headers)) == status)

    body = "authenticity_token=x"

    for method <- ~w(POST PATCH DELETE) do
      request =
        "#{method} /map/v2 HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert answered_by_phoenix(port, request) == 405
      assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
    end
  end

  test "retired frame malformed IDs formats and XHR requests never reach Rails", ctx do
    port = serve()
    frame = "Accept: text/html, application/xhtml+xml\r\n"
    get = fn target, headers -> "GET #{target} HTTP/1.1\r\nHost: a\r\n#{headers}\r\n" end

    for {target, headers} <- [
          {"/map/timeline_feeds/abc/track_info", frame},
          {"/map/timeline_feeds/1234567890123456789/track_info", frame},
          {"/map/timeline_feeds/5/track_info", "Accept: application/json\r\n"},
          {"/map/timeline_feeds/5/track_info", frame <> "X-Requested-With: XMLHttpRequest\r\n"},
          {"/map/timeline_feeds/5/track_info?format=json", frame},
          {"/tracks/5/segments?locale=de", frame}
        ],
        do: assert(answered_by_phoenix(port, get.(target, headers)) == 410)

    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
  end

  test "A10 native GETs and action refusals preserve admission without forwarding", ctx do
    cookie = a10_actor!()
    port = serve()

    for {target, view} <- [
          {"/admin/settings", DawarichWeb.AdminLive.Instance},
          {"/settings/users", DawarichWeb.SettingsLive.UsersIndex},
          {"/settings/users/10001", DawarichWeb.SettingsLive.UserShow},
          {"/settings/users/10001/edit", DawarichWeb.SettingsLive.UserEdit},
          {"/settings/background_jobs", DawarichWeb.SettingsLive.BackgroundJobs}
        ] do
      route = Phoenix.Router.route_info(DawarichWeb.Router, "GET", target, "a")
      assert match?(%{phoenix_live_view: {^view, _, _, _}}, route), target

      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n#{cookie}\r\n") ==
               200,
             target
    end

    for {path, status} <- [
          {"/sidekiq", 302},
          {"/admin/flipper", 404},
          {"/settings/users/99999", 302}
        ] do
      assert answered_by_phoenix(port, "GET #{path} HTTP/1.1\r\nHost: a\r\n#{cookie}\r\n") ==
               status
    end

    body = "user%5Bemail%5D=a10%40example.invalid&literal=%00%26"

    for {method, target, headers} <- [
          {"POST", "/admin/settings?section=photon", ""},
          {"PATCH", "/admin/settings", ""},
          {"PUT", "/admin/settings", ""},
          {"POST", "/admin/settings/test_geocoding", ""},
          {"POST", "/settings/users", ""},
          {"PUT", "/settings/users/10001", ""},
          {"PATCH", "/settings/users/10001", ""},
          {"DELETE", "/settings/users/10001", ""},
          {"POST", "/settings/users/10001/send_password_reset", ""},
          {"POST", "/settings/users/10001/regenerate_api_key", ""},
          {"POST", "/settings/users/import", ""},
          {"PATCH", "/settings/users/update_registration_settings", ""},
          {"GET", "/settings/users/export?kind=all", ""},
          {"GET", "/trial/welcome?token=synthetic-invalid", ""},
          {"GET", "/settings/users/export/edit", ""},
          {"GET", "/settings/users/10001.json", ""},
          {"GET", "/settings/users", "Accept: application/json\r\n"},
          {"PATCH", "/settings/background_jobs", ""},
          {"POST", "/settings/background_jobs?job_name=start_immich_import", ""}
        ] do
      client = connect(port)

      send_raw(
        client,
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\n#{cookie}#{headers}Content-Type: application/x-www-form-urlencoded\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}"
      )

      {status, _, _} = read_response(client)
      assert status in [200, 302, 303, 404, 406, 422]
      assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
    end

    assert [[0]] == Dawarich.Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows
  end

  test "native notifications handle JSON XHR and format refusals locally", ctx do
    port = serve()
    get = fn target, headers -> "GET #{target} HTTP/1.1\r\nHost: a\r\n#{headers}\r\n" end

    for {target, headers} <- [
          {"/notifications", "Accept: application/json\r\n"},
          {"/notifications", "Accept: text/html, application/json\r\n"},
          {"/notifications", "Accept: text/plain\r\n"},
          {"/notifications", "Accept: application/xhtml+xml\r\n"},
          {"/notifications", "X-Requested-With: XMLHttpRequest\r\n"},
          {"/notifications/5.json", ""},
          {"/notifications?format=json", ""},
          {"/notifications?page=2&form%61t=json", ""}
        ],
        do: assert(answered_locally(port, ctx.upstream, get.(target, headers)) in [302, 406])

    for {target, headers} <- [
          {"/notifications", ""},
          {"/notifications", "Accept: */*\r\n"},
          {"/notifications", "Accept: application/json, */*;q=0.1\r\n"},
          {"/notifications",
           "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n"},
          {"/notifications",
           "Accept: text/vnd.turbo-stream.html, text/html, application/xhtml+xml\r\n"},
          {"/notifications/5", "Accept: text/html\r\n"}
        ],
        do: assert(answered_by_phoenix(port, get.(target, headers)) == 302, target <> headers)
  end

  test "native import documents refuse signed-out actors while independent methods retain their adapters",
       ctx do
    port = serve()

    for target <- ~w(/imports/5 /imports/5/edit),
        do: assert(answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302)

    for target <-
          ~w(/imports/5/extraction /imports.json /exports.json /imports?format=json /imports/5?format=json /imports/5/download?format=json /exports/5) do
      assert answered_locally(port, ctx.upstream, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") in [
               200,
               302,
               303,
               404,
               406,
               422
             ]
    end

    assert answered_by_phoenix(port, "GET /imports/5/download HTTP/1.1\r\nHost: a\r\n\r\n") == 302
    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)

    for {method, target} <- [
          {"PUT", "/imports/5"},
          {"PUT", "/imports"},
          {"PATCH", "/imports/5/extraction"},
          {"DELETE", "/imports"},
          {"POST", "/imports/5/download"},
          {"POST", "/imports/direct_uploads"},
          {"PUT", "/imports/uploads/token"},
          {"POST", "/exports"},
          {"POST", "/exports/5"},
          {"DELETE", "/exports/5"},
          {"POST", "/settings/background_jobs?job_name=start_immich_import"}
        ] do
      body = "_method=delete&authenticity_token=x"

      request =
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert_write_transport(port, ctx.upstream, request, method, target)
    end
  end

  test "guest achievements use native sign-in and format refusal while external writes remain owned",
       ctx do
    port = serve()

    for target <-
          ~w(/achievements /achievements/country_de /achievements/unknown /achievements?unexpected=value /achievements?q[a]=value) do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 302
    end

    for target <- ~w(/achievements.json /achievements/country_de.json /achievements?format=json) do
      assert answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") == 406
    end

    for target <-
          ~w(/achievements/unlocks/next /achievements/unlocks/123/seen /achievements/unlocks/dismiss) do
      body = "authenticity_token=x"

      request =
        "POST #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert answered_locally(port, ctx.upstream, request) in [200, 302, 303, 404, 406, 422]
    end
  end

  test "native settings account and insights refuse unsupported requests locally",
       ctx do
    port = serve()

    assert answered_by_phoenix(port, "GET /settings/users HTTP/1.1\r\nHost: a\r\n\r\n") == 302

    for target <-
          ~w(/settings /settings/theme?theme=light /settings/two_factor /settings/background_jobs /users/sign_in /users/sign_up /users/edit.json /settings/general.json),
        do:
          assert(
            answered_locally(port, ctx.upstream, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") in [
              200,
              302,
              303,
              404,
              406,
              422
            ]
          )

    assert answered_by_phoenix(port, "GET /insights.json HTTP/1.1\r\nHost: a\r\n\r\n") == 406

    for {method, target} <- [
          {"PATCH", "/settings/general"},
          {"POST", "/settings/general/verify_supporter"},
          {"POST", "/settings/general/test_email"},
          {"PATCH", "/settings/integrations"},
          {"POST", "/settings/trek_sources"},
          {"DELETE", "/settings/trek_sources/1"},
          {"POST", "/settings/background_jobs?job_name=start_airtrail_import"},
          {"PATCH", "/settings/changelog_consent"},
          {"POST", "/settings/generate_api_key"},
          {"POST", "/settings/users/export"},
          {"POST", "/settings/users/import"},
          {"PUT", "/users"},
          {"DELETE", "/users"}
        ] do
      body = "authenticity_token=x"

      request =
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"

      assert_write_transport(port, ctx.upstream, request, method, target)
    end
  end

  test "endpoint account admission and malformed payloads stay local", ctx do
    alias Dawarich.{RailsCookies, Repo}
    alias Dawarich.Auth.SessionCookie
    alias Dawarich.Test.RailsUser
    alias DawarichWeb.RailsCsrf
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Map.new(~w(SELF_HOSTED APPLICATION_PROTOCOL RAILS_ENV), &{&1, System.get_env(&1)})
    flows = Application.fetch_env(:dawarich, :phoenix_auth)
    System.put_env("SELF_HOSTED", "true")
    System.put_env("APPLICATION_PROTOCOL", "http")
    System.put_env("RAILS_ENV", "test")

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end

      case flows do
        {:ok, value} -> Application.put_env(:dawarich, :phoenix_auth, value)
        :error -> Application.delete_env(:dawarich, :phoenix_auth)
      end
    end)

    hash = Bcrypt.hash_pwd_salt("a11rest-endpoint-password", log_rounds: 4)

    RailsUser.insert!(%{
      id: 74004,
      email: "a11rest-endpoint@dawarich.test",
      encrypted_password: hash,
      api_key: "A11REST_ENDPOINT_KEY",
      settings: %{}
    })

    secret = Application.fetch_env!(:dawarich, :rails_secret)
    {session, _} = SessionCookie.for_form(%{"retained" => true}, secret)
    session = Map.put(session, "warden.user.user.key", [[74004], binary_part(hash, 0, 29)])
    cookie = RailsCookies.encrypt(session, "_dawarich_session", secret)
    token = RailsCsrf.masked_token(session)

    body =
      URI.encode_query(%{
        "user[current_password]" => "a11rest-endpoint-password",
        "user[email]" => "a11rest-endpoint-updated@dawarich.test",
        "authenticity_token" => token
      })

    port = serve()

    request = fn method, path, body ->
      "#{method} #{path} HTTP/1.1\r\nHost: www.example.com\r\nAccept: text/html\r\n" <>
        "Cookie: _dawarich_session=#{cookie}\r\nContent-Type: application/x-www-form-urlencoded\r\n" <>
        "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"
    end

    snapshot = fn ->
      [[row]] =
        Repo.query!("SELECT to_jsonb(users) FROM users WHERE id=74004", [], log: false).rows

      row
    end

    Application.put_env(:dawarich, :phoenix_auth, ~w(account api_keys))

    for {method, path, raw, status, owner, fields} <- [
          {"PUT", "/users", body, 303, "native-account",
           ~w(email updated_at reset_password_token reset_password_sent_at)},
          {"POST", "/users", body <> "&_method=patch", 303, "native-account",
           ~w(email updated_at reset_password_token reset_password_sent_at)}
        ] do
      before = snapshot.()
      client = connect(port)
      send_raw(client, request.(method, path, raw))
      assert {^status, headers, _} = read_response(client)
      assert values(headers, "x-dawarich-auth-owner") == [owner]
      assert Map.drop(snapshot.(), fields) == Map.drop(before, fields)

      assert snapshot.()["email"] == "a11rest-endpoint-updated@dawarich.test"

      :gen_tcp.close(client)
    end

    assert {:error, :timeout} == :gen_tcp.accept(ctx.upstream.listen, 0)
  end

  test "native pages retired frames and residency resist obsolete ownership switches", ctx do
    Application.put_env(:dawarich, :rails_routes, ["map"])
    on_exit(fn -> Application.delete_env(:dawarich, :rails_routes) end)
    port = serve()

    for target <- [
          "/map/v2",
          "/map/timeline_feeds/5/track_info",
          "/map/timeline_feeds?start_at=2026-09-27T00:00:00&end_at=2026-09-27T23:59:59",
          "/map/timeline_feeds/calendar?month=2026-09"
        ],
        do:
          assert(
            answered_by_phoenix(port, "GET #{target} HTTP/1.1\r\nHost: a\r\n\r\n") ==
              if(target == "/map/v2", do: 302, else: 410)
          )

    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)

    assert answered_locally(
             port,
             ctx.upstream,
             "GET /map/residency?year=2026 HTTP/1.1\r\nHost: a\r\n\r\n"
           ) == 302

    drawer =
      "GET /places/5 HTTP/1.1\r\nHost: a\r\nAccept: text/html, application/xhtml+xml\r\n" <>
        "Turbo-Frame: place-drawer\r\n\r\n"

    assert answered_by_phoenix(port, drawer) == 302
  end

  defp hold_listen_socket(bandit) do
    {:listener, listener, _, _} = List.keyfind(Supervisor.which_children(bandit), :listener, 0)
    socket = Enum.find(Port.list(), &(Port.info(&1, :connected) == {:connected, listener}))
    {:ok, fd} = :inet.getfd(socket)
    {:ok, held} = :socket.open(fd, %{domain: :inet})
    held
  end

  defp wait_for_file(path, attempts \\ 200) do
    case File.read(path) do
      {:ok, content} when content != "" ->
        content

      _ when attempts > 0 ->
        Process.sleep(10)
        wait_for_file(path, attempts - 1)
    end
  end

  defp listener do
    Enum.find_value(Supervisor.which_children(DawarichWeb.Endpoint), fn
      {_, pid, :supervisor, [Bandit]} when is_pid(pid) -> pid
      _ -> nil
    end)
  end

  defp restarted_soon?(old, attempts \\ 200) do
    case listener() do
      pid when is_pid(pid) and pid != old ->
        true

      _ when attempts > 0 ->
        Process.sleep(10)
        restarted_soon?(old, attempts - 1)

      _ ->
        false
    end
  end

  defp accepting_soon?(port, attempts \\ 200) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 100) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} when attempts > 0 ->
        Process.sleep(10)
        accepting_soon?(port, attempts - 1)

      _ ->
        false
    end
  end

  defp endpoint_bandit do
    {:ok, bandit} = Bandit.PhoenixAdapter.bandit_pid(DawarichWeb.Endpoint)
    bandit
  end

  defp acceptor_connection_count(bandit) do
    bandit
    |> ThousandIsland.Server.acceptor_pool_supervisor_pid()
    |> ThousandIsland.AcceptorPoolSupervisor.acceptor_supervisor_pids()
    |> Enum.count(fn acceptor ->
      acceptor
      |> ThousandIsland.AcceptorSupervisor.connection_sup_pid()
      |> DynamicSupervisor.count_children()
      |> Map.fetch!(:active)
      |> Kernel.>(0)
    end)
  end

  defp refused(port) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 100) do
      {:error, _reason} ->
        true

      {:ok, socket} ->
        try do
          case :gen_tcp.send(socket, "GET /slow HTTP/1.1\r\nHost: a\r\n\r\n") do
            :ok ->
              case :gen_tcp.recv(socket, 0, 1_000) do
                {:error, reason} -> reason in [:closed, :econnreset]
                {:ok, _data} -> false
              end

            {:error, reason} ->
              reason in [:closed, :econnreset]
          end
        after
          :gen_tcp.close(socket)
        end
    end
  end

  defp refused_soon?(port, attempts \\ 200) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 100) do
      {:error, :econnrefused} ->
        true

      _ when attempts <= 0 ->
        false

      {:ok, socket} ->
        :gen_tcp.close(socket)
        Process.sleep(10)
        refused_soon?(port, attempts - 1)

      {:error, _other} ->
        Process.sleep(10)
        refused_soon?(port, attempts - 1)
    end
  end

  defp answered_locally(port, upstream, request) do
    status = answered_by_phoenix(port, request)
    assert status in [200, 301, 302, 303, 404, 406, 422]
    assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 0)
    status
  end

  test "stopping the listener lets an in-flight request finish and refuses new connections",
       _ctx do
    {:ok, sup} =
      Supervisor.start_link(
        [
          {Bandit,
           [plug: {Dawarich.Test.NativeDrainPlug, owner: self()}] ++
             Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
        ],
        strategy: :one_for_one
      )

    [{_, bandit, _, _}] = Supervisor.which_children(sup)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    client = connect(port)
    send_raw(client, "GET /slow HTTP/1.1\r\nHost: a\r\n\r\n")
    assert_receive {:request_waiting, handler}, 1_000

    started = System.monotonic_time(:millisecond)
    stopping = Task.async(fn -> Supervisor.stop(sup) end)
    assert refused_soon?(port)

    send(handler, :finish)
    assert {200, _headers, "done"} = read_response(client)
    assert Task.await(stopping, 10_000) == :ok
    assert System.monotonic_time(:millisecond) - started < 5_000
  end

  test "stopping the production listener drains every acceptor within one shutdown budget", ctx do
    cookie = a10_actor!() |> String.trim() |> String.replace_prefix("Cookie: ", "")

    plan =
      {:proxy,
       %{
         public: {{127, 0, 0, 1}, 0},
         upstream: ctx.upstream.port,
         puma_argv: ~w(bundle exec puma)
       }}

    :ok = Supervisor.terminate_child(Dawarich.Supervisor, DawarichWeb.Endpoint)

    on_exit(fn ->
      {:ok, _} = Supervisor.restart_child(Dawarich.Supervisor, DawarichWeb.Endpoint)
    end)

    sup =
      start_supervised!(
        %{
          id: :production_listener,
          start:
            {Supervisor, :start_link,
             [Enum.drop(Dawarich.Front.children(plan), 1), [strategy: :one_for_one]]},
          type: :supervisor
        },
        restart: :temporary
      )

    on_exit(fn ->
      if Process.alive?(sup), do: Supervisor.stop(sup, :shutdown, 0)
    end)

    bandit = endpoint_bandit()
    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)

    clients =
      for _ <- 1..3 do
        client =
          ws_request(port, "/cable", [{"Origin", "http://127.0.0.1:#{port}"}, {"Cookie", cookie}])

        assert {101, _, _} = read_response_head(client)
        client
      end

    assert acceptor_connection_count(bandit) == 3

    listener = ThousandIsland.Server.listener_pid(bandit)
    listener_ref = Process.monitor(listener)
    live_socket = Process.whereis(DawarichWeb.Endpoint.DawarichWeb.LiveSocket)
    live_socket_ref = Process.monitor(live_socket)
    started = System.monotonic_time(:millisecond)
    stopping = Task.async(fn -> Supervisor.stop(sup) end)

    assert_receive {:DOWN, ^listener_ref, :process, ^listener, _reason}, 1_000
    assert refused(port)
    assert Task.yield(stopping, 6_500) == {:ok, :ok}
    assert_receive {:DOWN, ^live_socket_ref, :process, ^live_socket, _reason}, 1_000
    assert System.monotonic_time(:millisecond) - started < 6_500

    Enum.each(clients, &:gen_tcp.close/1)
  end

  test "stopping the production listener closes a native cable connection normally", ctx do
    Application.put_env(:dawarich, :rails_routes, ["cable"])

    cookie = a10_actor!() |> String.trim() |> String.replace_prefix("Cookie: ", "")

    plan =
      {:proxy,
       %{
         public: {{127, 0, 0, 1}, 0},
         upstream: ctx.upstream.port,
         puma_argv: ~w(bundle exec puma)
       }}

    :ok = Supervisor.terminate_child(Dawarich.Supervisor, DawarichWeb.Endpoint)

    on_exit(fn ->
      {:ok, _} = Supervisor.restart_child(Dawarich.Supervisor, DawarichWeb.Endpoint)
    end)

    sup =
      start_supervised!(
        %{
          id: :production_listener,
          start:
            {Supervisor, :start_link,
             [Enum.drop(Dawarich.Front.children(plan), 1), [strategy: :one_for_one]]},
          type: :supervisor
        },
        restart: :temporary
      )

    on_exit(fn ->
      if Process.alive?(sup), do: Supervisor.stop(sup, :shutdown, 0)
    end)

    bandit = endpoint_bandit()
    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)

    client =
      ws_request(port, "/cable", [{"Origin", "http://127.0.0.1:#{port}"}, {"Cookie", cookie}])

    {101, _headers, rest} = read_response_head(client)
    live_socket = Process.whereis(DawarichWeb.Endpoint.DawarichWeb.LiveSocket)
    live_socket_ref = Process.monitor(live_socket)
    stopping = Task.async(fn -> Supervisor.stop(sup) end)

    assert {{:text, welcome}, rest} = ws_recv(client, rest)
    assert welcome =~ "welcome"
    assert {{:close, <<1000::16>>}, _rest} = ws_recv(client, rest)
    assert Task.await(stopping, 6_500) == :ok
    assert_receive {:DOWN, ^live_socket_ref, :process, ^live_socket, _reason}, 1_000
  end
end

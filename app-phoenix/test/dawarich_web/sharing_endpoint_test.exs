defmodule DawarichWeb.SharingEndpointTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP

  alias Dawarich.Test.{RailsUser, SharingSeeds, TripsSeeds}
  alias Dawarich.State
  alias DawarichWeb.RateLimit.Rules

  @live "a9500000-0000-4000-8000-000000000001"
  @protected "a9500000-0000-4000-8000-000000000002"
  @timeline "a9500000-0000-4000-8000-000000000003"
  @gone_trip "a9500000-0000-4000-8000-000000000007"
  @throttle SharingSeeds.fixture("throttle.json")

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
    SharingSeeds.load!()
    %{upstream: upstream}
  end

  defmodule UnreachableRepo do
    def query!(_sql, _params, _opts), do: raise(DBConnection.ConnectionError, "unreachable")
  end

  defp counter_store!(repo) do
    Application.put_env(:dawarich, :jobs_repo, repo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, ScratchRepo) end)
  end

  defp unlock_key(ip, id, now), do: Rules.key(now, 300, "shared_links/unlock", "#{ip}:#{id}")

  defp counter(key),
    do: "#{hd(hd(rows("SELECT value FROM phoenix.counters WHERE key = $1", [key])))}"

  defp ttl(key) do
    [[expires]] =
      rows(
        "SELECT floor(extract(epoch FROM expires_at))::bigint FROM phoenix.counters WHERE key = $1",
        [key]
      )

    expires - System.os_time(:second)
  end

  defp serve do
    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    port
  end

  defp get(target, headers \\ ""), do: "GET #{target} HTTP/1.1\r\nHost: a\r\n#{headers}\r\n"

  defp post(target, body, type \\ "application/x-www-form-urlencoded", headers \\ ""),
    do:
      "POST #{target} HTTP/1.1\r\nHost: a\r\nContent-Type: #{type}\r\n" <>
        "Content-Length: #{byte_size(body)}\r\n#{headers}\r\n#{body}"

  defp puma(port, upstream, request) do
    client = connect(port)
    send_raw(client, request)
    puma = accept(upstream)
    {head, rest} = read_head(puma)
    length = head |> header("content-length") |> List.first("0") |> String.to_integer()
    body = read_at_least(puma, rest, length)
    method = head |> String.split(" ") |> hd()
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
    expected = if method == "HEAD", do: "", else: "puma"
    assert {200, _headers, ^expected} = read_response(client, method: method)
    {request_line(head), body}
  end

  defp phoenix(port, request) do
    client = connect(port)
    send_raw(client, request)
    read_response(client)
  end

  defp counters,
    do: List.flatten(rows("SELECT key FROM phoenix.counters WHERE value <> 0 ORDER BY key"))

  test "requests Phoenix cannot answer as Rails would go to Puma before the view is counted",
       ctx do
    TripsSeeds.trip!(%{id: 990_001, user_id: 9901})
    port = serve()
    signed_in = "Cookie: _dawarich_session=#{RailsUser.cookie(RailsUser.session(9901))}\r\n"
    flash = %{"flash" => %{"discard" => [], "flashes" => %{"notice" => "Hi"}}}
    flashed = "Cookie: _dawarich_session=#{RailsUser.cookie(flash)}\r\n"
    stale = "Cookie: _dawarich_session=#{RailsUser.cookie(RailsUser.session(9999))}\r\n"

    RailsUser.insert!(%{
      id: 9902,
      email: "a9s-9902@dawarich.test",
      locked_at: NaiveDateTime.utc_now()
    })

    locked = "Cookie: _dawarich_session=#{RailsUser.cookie(RailsUser.session(9902))}\r\n"

    for request <- [
          "HEAD /s/#{@live} HTTP/1.1\r\nHost: a\r\n\r\n",
          get("/s/#{@live}", signed_in),
          get("/s/#{@live}", "Cookie: remember_user_token=x\r\n"),
          get("/s/#{@live}", flashed),
          get("/s/#{@gone_trip}"),
          get("/s/#{String.upcase(@live)}"),
          get("/s/#{@live}?client=ios"),
          get("/s/#{@live}", "X-Dawarich-Client: ios\r\n"),
          get("/s/#{@live}", stale),
          get("/s/#{@live}", locked),
          get("/s/#{@live}?format=json"),
          get("/s/#{@live}", "X-Requested-With: XMLHttpRequest\r\n"),
          get("/s/#{@live}", "Accept: application/json\r\n"),
          get(
            "/s/#{@live}",
            "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: 9\r\n"
          ) <>
            "locale=de"
        ] do
      {line, _body} = puma(port, ctx.upstream, request)
      assert line =~ ~r{\A(GET|HEAD) /s/}i
    end

    assert SharingSeeds.view_count(@live) == 0
    assert SharingSeeds.view_count(@gone_trip) == 0
  end

  test "Cloud hands the shared-link page and its unlock to Puma", ctx do
    System.put_env("SELF_HOSTED", "false")
    on_exit(fn -> System.delete_env("SELF_HOSTED") end)
    port = serve()

    assert {"GET /s/#{@live} HTTP/1.1", ""} == puma(port, ctx.upstream, get("/s/#{@live}"))

    assert {"POST /s/#{@live}/unlock HTTP/1.1", "phrase=x"} ==
             puma(port, ctx.upstream, post("/s/#{@live}/unlock", "phrase=x"))
  end

  test "unlocks Phoenix cannot count or read as Rails would go to Puma with their body, uncounted",
       ctx do
    port = serve()

    for {body, type, headers} <- [
          {"phrase=x", "application/x-www-form-urlencoded", "X-Forwarded-For: 203.0.113.9\r\n"},
          {"phrase=x", "application/x-www-form-urlencoded", "Forwarded: for=203.0.113.9\r\n"},
          {"phrase%5B%5D=x", "application/x-www-form-urlencoded", ""},
          {~s({"phrase":"x"}), "application/json", ""},
          {"phrase=x&locale=de", "application/x-www-form-urlencoded", ""},
          {"phrase=x&client=ios", "application/x-www-form-urlencoded", ""},
          {"phrase=x&_method=patch", "application/x-www-form-urlencoded", ""},
          {"phrase=x&format=json", "application/x-www-form-urlencoded", ""},
          {"phrase=x", "application/x-www-form-urlencoded", "X-HTTP-Method-Override: PATCH\r\n"},
          {"phrase=x", "application/x-www-form-urlencoded",
           "X-Requested-With: XMLHttpRequest\r\n"}
        ] do
      assert {"POST /s/#{@protected}/unlock HTTP/1.1", ^body} =
               puma(port, ctx.upstream, post("/s/#{@protected}/unlock", body, type, headers))
    end

    assert counters() == []
  end

  test "the sixth wrong phrase within five minutes answers 429 as Rack::Attack does" do
    port = serve()
    before = System.os_time(:second)

    statuses =
      for _ <- 1..6,
          do: port |> phoenix(post("/s/#{@protected}/unlock", "phrase=falsch")) |> elem(0)

    {status, headers, body} = phoenix(port, post("/s/#{@protected}/unlock", "phrase=falsch"))
    later = System.os_time(:second)

    assert statuses == @throttle["statuses"]
    assert status == 429
    assert body == @throttle["throttled"]["body"]

    wire = ~w(cache-control content-type retry-after)

    assert for({name, value} <- headers, name in wire, do: {name, name == "retry-after" || value}) ==
             for(
               [name, value] <- @throttle["raw"]["headers"],
               (name = String.downcase(name)) in wire,
               do: {name, name == "retry-after" || value}
             )

    assert hd(values(headers, "retry-after")) in Enum.map(
             [before, later],
             &"#{300 - rem(&1, 300)}"
           )

    assert [key] = counters()
    assert key in Enum.map([before, later], &unlock_key("127.0.0.1", @protected, &1))
    assert counter(key) == "7"
    ["rack", "", "attack", window | _] = String.split(key, ":")
    ttl = ttl(key)
    assert abs(System.os_time(:second) + ttl - (300 * (String.to_integer(window) + 1) + 1)) <= 1
  end

  test "Phoenix writes the counter key Rails reads, and reads the one Rails wrote" do
    {:ok, anchor, 0} = DateTime.from_iso8601(@throttle["now"])
    epoch = DateTime.to_unix(anchor)

    assert [%{"key" => written}] = @throttle["keys"]
    assert unlock_key("127.0.0.1", @protected, epoch) == written
    assert unlock_key("198.51.100.4", @protected, epoch) == @throttle["seeded"]["key"]
    assert @throttle["redis_db"] == 3

    port = serve()
    now = System.os_time(:second)

    for at <- [now, now + 5],
        do:
          State.increment(
            ScratchRepo,
            unlock_key("127.0.0.1", @protected, at),
            @throttle["seeded"]["count"],
            300
          )

    assert {429, _headers, _body} =
             phoenix(port, post("/s/#{@protected}/unlock", "phrase=blau-tiger-berg"))

    assert @throttle["seeded"]["status"] == 429
  end

  test "an unlock goes to Puma with its body, uncounted, when the Rack::Attack connection is not running",
       ctx do
    counter_store!(Dawarich.NotStartedRepo)
    port = serve()

    assert {"POST /s/#{@protected}/unlock HTTP/1.1", "phrase=falsch"} ==
             puma(port, ctx.upstream, post("/s/#{@protected}/unlock", "phrase=falsch"))
  end

  test "an unlock goes to Puma with its body when the Rack::Attack store cannot be reached",
       ctx do
    counter_store!(UnreachableRepo)
    port = serve()

    assert {"POST /s/#{@protected}/unlock HTTP/1.1", "phrase=falsch"} ==
             puma(port, ctx.upstream, post("/s/#{@protected}/unlock", "phrase=falsch"))
  end

  test "a page that stops being native after the gate reaches Puma without Phoenix's session cookie",
       ctx do
    Dawarich.Repo.query!(
      "UPDATE shared_links SET settings = $2 WHERE id = $1::text::uuid",
      [@timeline, %{"start_date" => "9 May 2026", "end_date" => "2026-05-12"}]
    )

    rails =
      Task.async(fn ->
        puma = accept(ctx.upstream)
        read_head(puma)

        reply(
          puma,
          "HTTP/1.1 200 OK\r\nSet-Cookie: _dawarich_session=rails\r\nContent-Length: 4\r\n\r\npuma"
        )
      end)

    conn =
      Phoenix.ConnTest.build_conn(:get, "/s/#{@timeline}")
      |> DawarichWeb.Router.call(DawarichWeb.Router.init([]))

    Task.await(rails)

    assert for({"set-cookie", value} <- conn.resp_headers, do: value) == [
             "_dawarich_session=rails"
           ]

    assert SharingSeeds.view_count(@timeline) == 0
  end

  test "a Turbo visit gets the reload stub and does not count the view" do
    port = serve()
    {status, _headers, body} = phoenix(port, get("/s/#{@live}", "X-Turbo-Request-Id: 1\r\n"))

    assert status == 200
    assert body =~ ~s(<meta name="turbo-visit-control" content="reload">)
    assert SharingSeeds.view_count(@live) == 0
  end
end

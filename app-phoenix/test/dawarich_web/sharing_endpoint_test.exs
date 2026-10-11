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

  defp phoenix(port, request) do
    client = connect(port)
    send_raw(client, request)

    read_response(client,
      method: if(String.starts_with?(request, "HEAD "), do: "HEAD", else: "GET")
    )
  end

  defp counters,
    do: List.flatten(rows("SELECT key FROM phoenix.counters WHERE value <> 0 ORDER BY key"))

  test "public native envelopes answer locally and refuse unsupported inputs before counting" do
    TripsSeeds.trip!(%{id: 990_001, user_id: 9901})
    port = serve()

    for headers <- [
          "",
          "Cookie: _dawarich_session=#{RailsUser.cookie(RailsUser.session(9901))}\r\n",
          "Cookie: remember_user_token=x\r\n",
          "Cookie: _dawarich_session=#{RailsUser.cookie(%{"flash" => %{"flashes" => %{"notice" => "Hi"}}})}\r\n"
        ] do
      {200, _, body} = phoenix(port, get("/s/#{@live}", headers))
      assert String.contains?(body, "native-public-map")
      assert String.contains?(body, "/native/app")
      refute body =~ "importmap"
    end

    RailsUser.insert!(%{
      id: 9902,
      email: "locked-public@example.invalid",
      locked_at: NaiveDateTime.utc_now()
    })

    for id <- [9902, 9999] do
      assert {200, _, _} =
               phoenix(
                 port,
                 get(
                   "/s/#{@live}",
                   "Cookie: _dawarich_session=#{RailsUser.cookie(RailsUser.session(id))}\r\n"
                 )
               )
    end

    assert {200, _, _} =
             phoenix(
               port,
               get(
                 "/s/#{@live}",
                 "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: 9\r\n"
               ) <> "locale=de"
             )

    assert SharingSeeds.view_count(@live) == 7
    assert {200, _, ""} = phoenix(port, "HEAD /s/#{@live} HTTP/1.1\r\nHost: a\r\n\r\n")
    assert SharingSeeds.view_count(@live) == 7

    for {path, headers, status} <- [
          {"/s/#{String.upcase(@live)}", "", 200},
          {"/s/#{@live}?client=ios", "", 200},
          {"/s/#{@live}", "X-Dawarich-Client: ios\r\n", 200},
          {"/s/#{@live}?format=json", "", 422},
          {"/s/#{@live}", "Accept: application/json\r\n", 422}
        ] do
      assert elem(phoenix(port, get(path, headers)), 0) == status, path
    end

    assert SharingSeeds.view_count(@live) == 10
    assert {200, _, body} = phoenix(port, get("/s/#{@gone_trip}"))
    assert String.contains?(body, "role=\"status\"")
    assert SharingSeeds.view_count(@gone_trip) == 1
  end

  test "Cloud public documents and wrong phrase unlock stay native" do
    saved = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")

    on_exit(fn ->
      if saved, do: System.put_env("SELF_HOSTED", saved), else: System.delete_env("SELF_HOSTED")
    end)

    port = serve()
    assert {200, _, body} = phoenix(port, get("/s/#{@live}"))
    assert String.contains?(body, "/native/app")
    assert {401, _, _} = phoenix(port, post("/s/#{@protected}/unlock", "phrase=wrong"))
  end

  test "unsupported native unlock bodies refuse locally without incrementing counters" do
    port = serve()

    for {body, type, headers} <- [
          {"phrase%5B%5D=x", "application/x-www-form-urlencoded", ""},
          {~s({"phrase":"x"}), "application/json", ""},
          {"phrase=x&locale=de", "application/x-www-form-urlencoded", ""},
          {"phrase=x&client=ios", "application/x-www-form-urlencoded", ""},
          {"phrase=x&_method=patch", "application/x-www-form-urlencoded", ""},
          {"phrase=x&format=json", "application/x-www-form-urlencoded", ""},
          {"phrase=x", "application/x-www-form-urlencoded", "X-HTTP-Method-Override: PATCH\r\n"}
        ] do
      {status, _, _} = phoenix(port, post("/s/#{@protected}/unlock", body, type, headers))
      assert status in [404, 422]
    end

    assert counters() == []
  end

  test "forwarded and XHR native unlocks keep the scalar phrase contract" do
    port = serve()

    for headers <- [
          "X-Forwarded-For: 203.0.113.9\r\n",
          "Forwarded: for=203.0.113.9\r\n"
        ] do
      assert {401, _, _} =
               phoenix(
                 port,
                 post(
                   "/s/#{@protected}/unlock",
                   "phrase=x",
                   "application/x-www-form-urlencoded",
                   headers
                 )
               )
    end

    assert SharingSeeds.view_count(@protected) == 0
    keys = counters()
    assert length(keys) == 2
    assert Enum.sort(Enum.map(keys, &counter/1)) == ["1", "1"]
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

  test "native unlock refuses when the Rack Attack connection is not running" do
    counter_store!(Dawarich.NotStartedRepo)
    assert {500, _, _} = phoenix(serve(), post("/s/#{@protected}/unlock", "phrase=wrong"))
    assert counters() == []
  end

  test "native unlock refuses when the Rack Attack store cannot be reached" do
    counter_store!(UnreachableRepo)
    assert {500, _, _} = phoenix(serve(), post("/s/#{@protected}/unlock", "phrase=wrong"))
    assert counters() == []
  end

  test "malformed public dates refuse before view count without a Rails response" do
    Dawarich.Repo.query!("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [
      @timeline,
      %{"start_date" => "9 May 2026", "end_date" => "2026-05-12"}
    ])

    assert {404, _, body} = phoenix(serve(), get("/s/#{@timeline}"))
    assert String.contains?(body, "role=\"status\"")
    assert SharingSeeds.view_count(@timeline) == 0
  end

  test "a Turbo visit reads the native document and counts one HTTP view" do
    {200, _, body} = phoenix(serve(), get("/s/#{@live}", "X-Turbo-Request-Id: 1\r\n"))
    assert String.contains?(body, "native-public-map")
    refute body =~ "turbo-visit-control"
    assert SharingSeeds.view_count(@live) == 1
  end
end

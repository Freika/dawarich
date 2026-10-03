defmodule DawarichWeb.RateLimitTest do
  use Dawarich.JobsCase

  import Plug.Conn

  alias Dawarich.{Repo, State, TtlCache}
  alias Dawarich.Test.{RailsUser, RateLimitCorpus, RawHTTP}
  alias DawarichWeb.RateLimit
  alias DawarichWeb.RateLimit.Rules

  defp corpus, do: RateLimitCorpus.corpus()
  defp plans, do: Map.new(corpus()["plans"], &{&1["value"], &1["effective_plan"]})

  defp opts(self_hosted, now \\ 1_790_942_417),
    do: %{now: now, plan: &Map.get(plans(), &1), repo: ScratchRepo, self_hosted: self_hosted}

  defp replay(_scenario, %{"seed" => seed, "at" => at}) do
    key = "rack::attack:#{div(at, seed["period"])}:#{seed["throttle"]}:#{seed["discriminator"]}"
    State.increment(ScratchRepo, key, seed["value"], seed["period"])
  end

  defp replay(scenario, %{"request" => r, "at" => at} = step) do
    outcome =
      RateLimit.decide(
        RateLimitCorpus.request_conn(r),
        opts(scenario["mode"] == "self_hosted", at)
      )

    expected = Enum.map(step["increments"], &{RateLimitCorpus.key(&1), &1["ttl"]})
    label = "#{scenario["name"]} #{r["method"]} #{r["path"]}?#{r["query"]}"

    case {step["phoenix"], outcome} do
      {"defer", {:defer, _conn, [], _reason}} ->
        Enum.each(expected, fn {key, ttl} -> State.increment(ScratchRepo, key, 1, ttl) end)

      {nil, {:pass, _conn, counted, token}} ->
        assert step["response"] == %{"status" => "passed"}, label
        assert counted == expected, label
        assert to_token(token) == step["token"], label

      {nil, {:throttled, conn, counted, data}} ->
        assert counted == expected, label

        same_response(
          RateLimit.throttled(conn, data, at, scenario["manager_url"]),
          step["response"],
          r,
          label
        )

      {nil, {:blocked, conn}} ->
        assert expected == [], label
        same_response(RateLimit.blocked(conn), step["response"], r, label)

      other ->
        flunk("#{label}: #{inspect(other, limit: 4)}")
    end
  end

  defp same_response(conn, rails, request, label) do
    assert conn.status == rails["status"], label

    for {name, values} <- rails["headers"],
        do: assert(get_resp_header(conn, name) == values, "#{label} #{name}")

    names = for {name, _} <- conn.resp_headers, do: name

    assert Enum.sort(names) == rails["header_names"] -- ~w(x-request-id x-runtime set-cookie),
           label

    if request["method"] != "HEAD", do: assert(conn.resp_body == rails["body"], label)
  end

  test "replays every recorded scenario step: same increments, api/token data, outcome and response" do
    for scenario <- corpus()["scenarios"] do
      reset!(ScratchRepo)
      Enum.each(scenario["steps"], &replay(scenario, &1))
    end

    recorded =
      for s <- corpus()["scenarios"],
          step <- s["steps"],
          i <- step["increments"] || [],
          into: MapSet.new(),
          do: i["throttle"]

    assert MapSet.new(Rules.throttles(), &elem(&1, 0)) == recorded
  end

  test "slash variants of the unlock path count under the key Rails counts them with" do
    for scenario <- corpus()["scenarios"], String.starts_with?(scenario["name"], "unlock") do
      reset!(ScratchRepo)
      steps = Enum.filter(scenario["steps"], &(&1["request"]["remote_addr"] == "203.0.113.151"))

      assert Enum.map(steps, & &1["request"]["path"]) ==
               ~w(/s/abc/unlock/ //s/abc/unlock /s/abc//unlock)

      for step <- steps do
        assert {:pass, _conn, counted, nil} =
                 RateLimit.decide(
                   RateLimitCorpus.request_conn(step["request"]),
                   opts(scenario["mode"] == "self_hosted", step["at"])
                 )

        assert counted == Enum.map(step["increments"], &{RateLimitCorpus.key(&1), &1["ttl"]})
        assert [{"rack::attack:" <> key, _ttl}] = counted
        assert String.ends_with?(key, ":shared_links/unlock:203.0.113.151:abc")
      end
    end
  end

  test "the plan lookup is Rails' effective_plan for every recorded user and is cached for two minutes" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    for {entry, n} <- Enum.with_index(corpus()["plans"]), entry["handle"] != "unknown" do
      seed_user(entry, 5_700 + n * 2)
    end

    for entry <- corpus()["plans"] do
      TtlCache.delete({RateLimit, entry["value"]})
      assert RateLimit.plan(entry["value"]) == entry["effective_plan"], entry["handle"]
    end

    lite = Enum.find(corpus()["plans"], &(&1["handle"] == "lite"))
    Repo.query!("UPDATE users SET plan = 1 WHERE api_key = $1", [lite["value"]])
    assert RateLimit.plan(lite["value"]) == "lite"
  end

  test "unknown API keys do not cache misses or evict other features' cached entries" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    expires_at = System.monotonic_time(:millisecond) + 120_000
    keys = for n <- 1..10_000, do: {:a13c_cache_spray_guard, n}
    :ets.insert(TtlCache, Enum.map(keys, &{&1, :kept, expires_at}))
    on_exit(fn -> Enum.each(keys, &TtlCache.delete/1) end)

    for key <- ["a13cunknownspray1", "a13cunknownspray2"] do
      assert RateLimit.plan(key) == nil
      assert :ets.lookup(TtlCache, {RateLimit, key}) == []
    end

    assert TtlCache.fetch(hd(keys), 120_000, fn -> flunk("shared cache was flushed") end) == :kept
  end

  test "every Rack CORS pending-imports path defers to Rails before counting or reading" do
    body = ~s({"api_key":"a13cunknown"})

    for path <- [
          "/api/v1/imports/pending",
          "/api/v1/imports/pending/",
          "//api/v1/imports/pending",
          "/api/v1/imports/%70ending",
          "/api/v1/imports/other/../pending"
        ],
        method <- [:get, :post],
        self_hosted <- [false, true] do
      conn =
        %{Plug.Test.conn(method, "/", body) | request_path: path}
        |> put_req_header("content-type", "application/json")
        |> put_req_header("content-length", Integer.to_string(byte_size(body)))
        |> put_req_header("origin", "https://example.invalid")

      assert {:defer, deferred, [], "Rack CORS resource"} =
               RateLimit.decide(conn, opts(self_hosted))

      refute Map.has_key?(deferred.private, :dawarich_raw_body)
    end

    assert rows("SELECT count(*) FROM phoenix.counters") == [[0]]
  end

  test "nothing is read, counted or deferred for a request no rule covers" do
    body = "export%5Bname%5D=x"

    conn =
      Plug.Test.conn(:post, "/exports", body)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(body)))

    assert {:pass, conn, [], nil} = RateLimit.decide(conn, opts(false))
    refute Map.has_key?(conn.private, :dawarich_raw_body)

    for {method, path, self_hosted} <- [
          {"GET", "/stats", false},
          {"POST", "/api/v1/points", true},
          {"GET", "/api/v1/stats", true}
        ],
        do:
          assert(
            {:pass, _, [], nil} =
              RateLimit.decide(Plug.Test.conn(method, path), opts(self_hosted))
          )

    assert rows("SELECT count(*) FROM phoenix.counters") == [[0]]
  end

  defmodule BrokenRepo do
    def query!(_sql, _params, _opts), do: raise(DBConnection.ConnectionError, "down")
  end

  test "a counter-store error hands the request to Puma uncounted" do
    conn = %{Plug.Test.conn(:post, "/s/abc/unlock") | remote_ip: {203, 0, 113, 41}}

    assert {:defer, _conn, [], "counter store: DBConnection.ConnectionError"} =
             RateLimit.decide(conn, %{opts(true) | repo: BrokenRepo})
  end

  defp seed_user(entry, id) do
    RailsUser.insert!(%{
      id: id,
      email: "a13c-#{id}@dawarich.test",
      api_key: entry["value"],
      plan: entry["plan"],
      active_until: naive(entry["active_until"]),
      deleted_at: if(entry["deleted"], do: ~N[2026-01-01 00:00:00])
    })

    if family = entry["family"] do
      RailsUser.insert!(%{
        id: id + 1,
        email: "a13c-#{id + 1}@dawarich.test",
        api_key: "a13cowner#{id}qqqqqqqqqqqq",
        plan: family["owner_plan"],
        active_until: naive(family["owner_active_until"])
      })

      stamp = NaiveDateTime.utc_now(:second)

      {1, [%{id: family_id}]} =
        Repo.insert_all(
          "families",
          [
            %{
              name: "F",
              creator_id: id + 1,
              access_until: naive(family["access_until"]),
              created_at: stamp,
              updated_at: stamp
            }
          ],
          returning: [:id]
        )

      Repo.insert_all("family_memberships", [
        %{family_id: family_id, user_id: id, role: 1, created_at: stamp, updated_at: stamp}
      ])
    end
  end

  defp to_token(nil), do: nil
  defp to_token(token), do: Map.new(token, fn {k, v} -> {Atom.to_string(k), v} end)

  defp naive(nil), do: nil
  defp naive(iso), do: iso |> NaiveDateTime.from_iso8601!() |> NaiveDateTime.truncate(:second)

  test "a request Phoenix counted and then hands to Puma is released, so Rails counts it once" do
    upstream = RawHTTP.listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, nil)

      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    body = ~s({"email":"a@example.invalid"})

    puma =
      Task.async(fn ->
        socket = RawHTTP.accept(upstream)
        {_head, rest} = RawHTTP.read_head(socket)
        received = RawHTTP.read_at_least(socket, rest, byte_size(body))

        RawHTTP.reply(
          socket,
          "HTTP/1.1 401 Unauthorized\r\ncontent-length: 0\r\nconnection: close\r\n\r\n"
        )

        :gen_tcp.close(socket)
        received
      end)

    conn =
      %{Plug.Test.conn(:post, "/api/v1/auth/login", body) | remote_ip: {203, 0, 113, 40}}
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-length", Integer.to_string(byte_size(body)))
      |> RateLimit.call([])

    assert [_, _] = conn.private.dawarich_rate_limit
    assert rows("SELECT value FROM phoenix.counters ORDER BY key") == [[1], [1]]

    conn = conn |> assign(:api_tag, "api") |> DawarichWeb.Api.Body.replay("test")

    assert Task.await(puma) == body
    assert conn.status == 401
    assert rows("SELECT value FROM phoenix.counters ORDER BY key") == [[0], [0]]
  end

  test "every routed request runs the limiter right after ForceSSL" do
    source = File.read!(Path.expand("../../lib/dawarich_web/router.ex", __DIR__))

    guarded =
      source
      |> then(&Regex.scan(~r/  pipeline :(\w+) do\n(.*?)\n  end/s, &1, capture: :all_but_first))
      |> Enum.filter(fn [_name, body] ->
        body =~ ~r/plug DawarichWeb\.ForceSSL\n\s+plug DawarichWeb\.RateLimit\n/
      end)
      |> MapSet.new(fn [name, _body] -> String.to_existing_atom(name) end)

    for route <- DawarichWeb.Router.__routes__() do
      info =
        Phoenix.Router.route_info(
          DawarichWeb.Router,
          String.upcase(to_string(route.verb)),
          route.path,
          "localhost"
        )

      assert is_map(info), "#{route.verb} #{route.path} does not resolve"

      assert Enum.any?(info.pipe_through, &MapSet.member?(guarded, &1)),
             "#{route.verb} #{route.path} has no guarded pipeline: #{inspect(info.pipe_through)}"
    end
  end
end

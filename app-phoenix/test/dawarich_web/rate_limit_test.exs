defmodule DawarichWeb.RateLimitTest do
  use Dawarich.JobsCase

  import Plug.Conn

  alias Dawarich.{Repo, State, TtlCache}
  alias Dawarich.Test.{RailsUser, RateLimitCorpus}
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
end

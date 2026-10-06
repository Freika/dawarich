defmodule DawarichWeb.HealthEndpointTest do
  use Dawarich.IngestCase, async: false

  setup do
    saved = Map.new(~w(SELF_HOSTED DAWARICH_RAILS_SLICES), &{&1, System.get_env(&1)})
    routes = Application.get_env(:dawarich, :rails_routes)
    Application.put_env(:dawarich, :rails_routes, [])
    System.delete_env("DAWARICH_RAILS_SLICES")
    Dawarich.Jobs.Health.reset()

    on_exit(fn ->
      Dawarich.Jobs.Health.reset()
      Application.put_env(:dawarich, :rails_routes, routes)

      Enum.each(saved, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)
  end

  test "health is native on self hosted and Cloud without private API authentication" do
    route =
      Phoenix.Router.route_info(
        DawarichWeb.Router,
        "GET",
        "/api/v1/health",
        "staging.dawarich.app"
      )

    assert route.rails_key == "health"
    refute Map.has_key?(route, :slice)

    for mode <- ~w(true false) do
      System.put_env("SELF_HOSTED", mode)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("x-forwarded-proto", "https")
        |> Phoenix.ConnTest.dispatch(DawarichWeb.Endpoint, :get, "/api/v1/health")

      assert conn.status == 200

      assert Jason.decode!(conn.resp_body) == %{
               "status" => "ok",
               "phoenix" => %{"status" => "unknown", "alarm" => false}
             }

      assert Plug.Conn.get_resp_header(conn, "x-dawarich-response") == ["Hey, I'm alive!"]
    end
  end

  test "both readiness URLs return 503 on unavailable and skip payment and API key gates" do
    user!(%{id: 10_102, api_key: "a10-synthetic-key-10102", status: 3})
    user!(%{id: 10_101, api_key: "a10-synthetic-key-10101", status: 1, plan: 0})
    jobs_repo = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Repo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, jobs_repo) end)
    corpus = Jason.decode!(File.read!("test/fixtures/admin_pages/api_health.json"))
    now = elem(DateTime.from_iso8601(corpus["now"]), 1)

    for path <- ~w(/api/v1/ready /ready) do
      assert Phoenix.Router.route_info(DawarichWeb.Router, "GET", path, "staging.dawarich.app").rails_key ==
               "ready"

      for kase <- corpus["cases"], String.starts_with?(kase["name"], "ready_") do
        Repo.query!("DELETE FROM phoenix.counters", [], log: false)
        System.put_env("SELF_HOSTED", to_string(kase["self_hosted"]))
        key = kase["query_key"]

        opts = [
          release: fn _ -> :ready end,
          database: fn -> {:ok, %{rows: [[1]]}} end,
          redis: fn -> {:ok, "PONG"} end
        ]

        opts =
          case kase["name"] do
            "ready_database_error" ->
              Keyword.put(opts, :database, fn -> {:error, :connection} end)

            name when name in ["ready_redis_error", "ready_self_hosted_error"] ->
              Keyword.put(opts, :redis, fn -> {:error, :connection} end)

            _ ->
              opts
          end

        target = if key, do: path <> "?api_key=" <> key, else: path

        if kase["limit_count"] > 0 and path == "/api/v1/ready" do
          counter = DawarichWeb.RateLimit.Rules.key(DateTime.to_unix(now), 3600, "api/token", key)
          Dawarich.State.increment(Repo, counter, kase["limit_count"], 3600)
        end

        conn =
          Phoenix.ConnTest.build_conn()
          |> Plug.Conn.assign(:api_now, now)
          |> Plug.Conn.assign(:readiness_opts, opts)
          |> Plug.Conn.put_req_header("x-forwarded-proto", "https")
          |> Phoenix.ConnTest.dispatch(DawarichWeb.Endpoint, :get, target)

        expected =
          if path == "/ready" and kase["status"] == 429,
            do: Enum.find(corpus["cases"], &(&1["name"] == "ready_cloud_key")),
            else: kase

        assert conn.status == expected["status"]
        assert conn.resp_body == expected["raw_body"]

        for {header, value} <- expected["headers"],
            do: assert(Plug.Conn.get_resp_header(conn, header) == value)

        assert Plug.Conn.get_resp_header(conn, "x-ratelimit-limit") == []
        assert Plug.Conn.get_resp_header(conn, "x-ratelimit-remaining") == []
        assert Plug.Conn.get_resp_header(conn, "x-ratelimit-reset") == []
      end

      for key <- [nil, "a12f-invalid", "a10-synthetic-key-10102"], mode <- ~w(true false) do
        System.put_env("SELF_HOSTED", mode)
        opts = [release: fn _ -> :schemas_behind end]
        target = if key, do: path <> "?api_key=" <> key, else: path

        conn =
          Phoenix.ConnTest.build_conn()
          |> Plug.Conn.assign(:readiness_opts, opts)
          |> Phoenix.ConnTest.dispatch(DawarichWeb.Endpoint, :get, target)

        assert conn.status == 503
        assert conn.resp_body == ~s({"status":"unavailable"})
      end
    end
  end
end

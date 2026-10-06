defmodule DawarichWeb.HealthGoldenTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Jobs.Health

  test "health replies match the Rails health corpus" do
    corpus = Jason.decode!(File.read!("test/fixtures/admin_pages/api_health.json"))
    assert corpus["version"] == Dawarich.AppVersion.current()
    cases = corpus["cases"]
    assert length(cases) >= 20

    for name <- ~w(unknown absent stale ok alarm) do
      reply = Enum.find(cases, &(&1["name"] == name))
      assert reply["status"] == 200
      assert reply["body"]["status"] == "ok"
      assert Map.keys(reply["body"]["phoenix"]) |> Enum.sort() == ~w(alarm status)
    end

    for name <-
          ~w(query_valid query_invalid bearer_valid bearer_invalid query_precedence pending cloud_ok cloud_throttled ready_ok ready_database_error ready_redis_error ready_pending) do
      assert Enum.any?(cases, &(&1["name"] == name))
    end
  end

  setup do
    Health.reset()
    jobs_repo = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Dawarich.Repo)
    env = Map.new(~w(SELF_HOSTED JWT_SECRET_KEY MANAGER_URL), &{&1, System.get_env(&1)})
    System.put_env("JWT_SECRET_KEY", "a12f-synthetic-checkout-secret")
    System.delete_env("MANAGER_URL")

    user!(%{
      id: 10_101,
      api_key: "a10-synthetic-key-10101",
      email: "a10-10101@example.invalid",
      plan: 0
    })

    user!(%{
      id: 10_102,
      api_key: "a10-synthetic-key-10102",
      email: "a10-10102@example.invalid",
      status: 3
    })

    on_exit(fn ->
      Health.reset()
      Application.put_env(:dawarich, :jobs_repo, jobs_repo)

      Enum.each(env, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)
  end

  test "credential free anonymous health answers ok and cached summary without SQL" do
    for name <- ~w(unknown absent stale ok alarm), do: compare(name, true)
  end

  test "health optional keys preserve source headers and precedence" do
    for name <-
          ~w(query_valid query_invalid bearer_valid bearer_invalid query_precedence query_empty),
        do: compare(name)
  end

  test "health pending payment returns the source 402 reply" do
    for name <- ~w(pending cloud_pending), do: compare(name)
  end

  test "Cloud health preserves throttle replies and rate headers" do
    for name <- ~w(cloud_anonymous cloud_ok cloud_invalid cloud_throttled),
        do: compare(name, name == "cloud_anonymous")
  end

  defp compare(name, no_sql \\ false) do
    corpus = corpus()
    kase = Enum.find(corpus["cases"], &(&1["name"] == name))
    System.put_env("SELF_HOSTED", to_string(kase["self_hosted"]))

    if kase["summary"]["status"] == "unknown",
      do: Health.reset(),
      else: Health.refresh(compute: fn -> kase["summary"] end)

    Repo.query!("DELETE FROM phoenix.counters", [], log: false)
    Dawarich.TtlCache.delete({DawarichWeb.RateLimit, "a10-synthetic-key-10101"})
    Dawarich.TtlCache.delete({DawarichWeb.RateLimit, "a10-synthetic-key-10102"})
    parent = self()
    id = {__MODULE__, make_ref()}

    :telemetry.attach(
      id,
      [:dawarich, :repo, :query],
      fn _, _, _, _ -> send(parent, :health_sql) end,
      nil
    )

    try do
      conn =
        Enum.reduce(0..kase["limit_count"], nil, fn _, _ ->
          health_request(kase, corpus["now"])
        end)

      if no_sql, do: refute_received(:health_sql)
      assert conn.status == kase["status"], name
      raw = normalize_checkout(conn.resp_body)
      assert raw == kase["raw_body"], name

      for {header, value} <- kase["headers"],
          header != "content-length",
          do: assert(Plug.Conn.get_resp_header(conn, header) == value, "#{name}: #{header}")

      assert Enum.sort(
               Enum.map(conn.resp_headers, &elem(&1, 0)) -- ~w(x-runtime x-request-id etag)
             ) ==
               Enum.sort(
                 Enum.flat_map(kase["headers"], fn {key, values} ->
                   List.duplicate(key, length(values))
                 end) -- ~w(content-length)
               )
    after
      :telemetry.detach(id)
    end
  end

  defp health_request(kase, time) do
    path =
      if kase["query_key"],
        do: kase["path"] <> "?api_key=" <> URI.encode_www_form(kase["query_key"]),
        else: kase["path"]

    conn = Plug.Test.conn(:get, "http://staging.dawarich.app" <> path)

    conn =
      if kase["bearer"],
        do: Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> kase["bearer"]),
        else: conn

    conn =
      conn
      |> Plug.Conn.assign(:api_tag, "health")
      |> Plug.Conn.assign(:api_now, elem(DateTime.from_iso8601(time), 1))
      |> DawarichWeb.RateLimit.call([])

    if conn.halted,
      do: conn,
      else: conn |> DawarichWeb.Api.Body.call([]) |> DawarichWeb.Api.HealthController.call(:index)
  end

  defp normalize_checkout(raw) do
    case Jason.decode!(raw) do
      %{"resume_url" => url} when is_binary(url) ->
        assert [token] = Regex.run(~r/token=(.*)\z/, url, capture: :all_but_first)
        [header, payload, signature] = String.split(token, ".")

        expected =
          :crypto.mac(:hmac, :sha256, "a12f-synthetic-checkout-secret", header <> "." <> payload)
          |> Base.url_encode64(padding: false)

        assert signature == expected
        decoded = Jason.decode!(Base.url_decode64!(payload, padding: false))

        assert Map.take(decoded, ~w(user_id email purpose exp)) == %{
                 "user_id" => 10_102,
                 "email" => "a10-10102@example.invalid",
                 "purpose" => "checkout",
                 "exp" => DateTime.to_unix(elem(DateTime.from_iso8601(corpus()["now"]), 1)) + 1800
               }

        String.replace(raw, token, "SUBSCRIPTION_TOKEN")

      _ ->
        raw
    end
  end

  defp corpus, do: Jason.decode!(File.read!("test/fixtures/admin_pages/api_health.json"))
end

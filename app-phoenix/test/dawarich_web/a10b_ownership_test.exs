defmodule DawarichWeb.A10bOwnershipTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.{Repo, Redis}
  alias Dawarich.Test.{RailsUser, RawHTTP}
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    for spec <- Redis.child_specs() ++ Redis.cache_child_specs(), do: start_supervised!(spec)
    Repo.query!("DELETE FROM instance_settings", [], log: false)
    Dawarich.State.put_registration_enabled(Repo, true)

    saved =
      for key <- ~w(SELF_HOSTED JWT_SECRET_KEY STORE_GEODATA TIME_ZONE),
          into: %{},
          do: {key, System.get_env(key)}

    System.put_env("SELF_HOSTED", "true")
    System.put_env("JWT_SECRET_KEY", "test-test-test-test")
    System.delete_env("STORE_GEODATA")
    original = Application.get_env(:dawarich, :rails_routes, [])
    upstream = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_routes, [])
    server = RawHTTP.listen()
    owner = self()
    start_supervised!({Task, fn -> upstream_loop(server, owner) end})
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, server.port})

    on_exit(fn ->
      :gen_tcp.close(server.listen)
      Application.put_env(:dawarich, :rails_routes, original)
      Application.put_env(:dawarich, :rails_upstream, upstream)

      Enum.each(saved, fn {k, v} -> if v, do: System.put_env(k, v), else: System.delete_env(k) end)
    end)

    for {id, admin} <- [{15801, true}, {15802, false}],
        do:
          RailsUser.insert!(%{
            id: id,
            email: "a10b-ownership-#{id}@example.invalid",
            admin: admin,
            settings: %{"timezone" => "UTC", "locale" => "en", "onboarding_completed" => true}
          })

    :ok
  end

  test "welcome, guest home and the shared background POST are owned with exact rollback keys" do
    for name <- ~w(background_override) do
      row = fixture("admin_setting_writes", name)
      method = "POST"

      conn =
        request(method, "/settings/background_jobs?" <> (row["query"] || ""), row["body"], 15802)

      assert conn.status == 302
      expected = row["after"]["visits_suggestions_enabled"]

      assert Repo.query!(
               "SELECT settings->'visits_suggestions_enabled' FROM users WHERE id=15802",
               [],
               log: false
             ).rows == [[expected]]
    end

    assert dispatch(build_conn(), @endpoint, :get, "/", nil).status == 200
    welcome = welcome_path()
    conn = dispatch(build_conn(), @endpoint, :get, welcome, nil)
    assert conn.status == 302
    assert get_resp_header(conn, "x-dawarich-trial-owner") == ["native-welcome"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    root = Phoenix.Router.route_info(DawarichWeb.Router, "GET", "/", "www.example.com")
    assert root.plug == DawarichWeb.HomeDispatch

    assert Phoenix.Router.route_info(
             DawarichWeb.Router,
             "GET",
             "/trial/upgrade",
             "www.example.com"
           ).plug == DawarichWeb.TrialUpgrade

    for {key, method, path, body, actor} <- [
          {"trial", "GET", welcome, "", nil},
          {"home", "GET", "/", "", nil}
        ] do
      Application.put_env(:dawarich, :rails_routes, [key])
      handoff!(method, path, body, actor)
    end
  end

  test "trial settings home hand-back reaches Rails before native effects and shared state remains PG" do
    Dawarich.State.put_registration_enabled(Repo, false)
    before = snapshot()

    claims =
      Repo.query!("SELECT key, expires_at FROM phoenix.once_claims ORDER BY key", [], log: false).rows

    large =
      Enum.map_join(1..128, fn index ->
        Base.encode16(:crypto.hash(:sha256, Integer.to_string(index)), case: :lower)
      end)

    for {key, method, path, body, actor} <- [
          {"trial", "GET", welcome_path(), "", nil},
          {"trial", "GET", welcome_path(large), "", nil},
          {"home", "GET", "/", "", nil}
        ] do
      Application.put_env(:dawarich, :rails_routes, [key])
      handoff!(method, path, body, actor)
      assert snapshot() == before
      assert {:ok, false} = Dawarich.Auth.RegistrationSetting.fetch()

      assert Repo.query!("SELECT key, expires_at FROM phoenix.once_claims ORDER BY key", [],
               log: false
             ).rows == claims
    end
  end

  test "retained mounts producers frames and unsupported requests reach Rails byte identical" do
    before = snapshot()
    assert request("GET", "/sidekiq", "", 15801).status == 302
    assert request("GET", "/admin/flipper", "", 15801).status == 404
    refute_received {:upstream, _, _, _}
    assert snapshot() == before

    before = snapshot()

    Application.put_env(:dawarich, :rails_routes, ["user_data"])

    for {method, path, body} <- [
          {"GET", "/settings/users/export", ""},
          {"POST", "/settings/users/import", "synthetic=body"}
        ] do
      handoff!(method, path, body, 15801)
    end

    Application.put_env(:dawarich, :rails_routes, [])

    for {method, path, body} <- [
          {"DELETE", "/settings/users/15802", ""},
          {"POST", "/settings/users/15802", "_method=delete"},
          {"POST", "/settings/background_jobs", "job=synthetic"},
          {"POST", "/admin/settings/test_geocoding", "provider=synthetic"},
          {"PATCH", "/settings/users/015802", "user%5Bemail%5D=changed"},
          {"PATCH", "/settings/users/15999", "user%5Bemail%5D=changed"},
          {"PATCH", "/settings/users/15802", "user%5Badmin%5D=1&user%5Badmin%5D=0"},
          {"PATCH", "/settings/users/15802",
           "user%5Badmin%5D=0&user%5Badmin%5D=1&user%5Badmin%5D=1"},
          {"PATCH", "/settings/users/15802", "user%5Bemail%5D=one&user%5Bemail%5D=two"},
          {"PATCH",
           "/settings/background_jobs?settings%5Bvisits_suggestions_enabled%5D=true&settings%5Bvisits_suggestions_enabled%5D=true",
           ""},
          {"PATCH",
           "/settings/background_jobs?settings%5Bvisits_suggestions_enabled%5D=true&extra=x", ""},
          {"PATCH", "/settings/background_jobs?settings%5Bvisits_suggestions_enabled%5D=true",
           "settings%5Bvisits_suggestions_enabled%5D=false"},
          {"PATCH", "/settings/background_jobs?settings%5Bvisits_suggestions_enabled%5D=true",
           "settings%5Bvisits_suggestions_enabled%5D=true"}
        ] do
      handoff!(method, path, body, 15801)
    end

    for actor <- [nil, 15802],
        do: handoff!("POST", "/settings/users", "user%5Bemail%5D=refused", actor)

    System.put_env("SELF_HOSTED", "false")
    handoff!("POST", "/settings/users", "user%5Bemail%5D=refused", 15801)
    System.put_env("SELF_HOSTED", "true")

    for headers <- [
          [{"turbo-frame", "frame"}],
          [{"content-type", "application/json"}],
          [{"accept", "application/json"}],
          [{"x-http-method-override", "patch"}]
        ] do
      handoff!("PATCH", "/settings/users/15802", "user%5Bemail%5D=refused", 15801, headers)
    end

    same = snapshot() == before
    assert same, "retained requests changed users"
  end

  test "timezone callback hands background update back before rows or jobs change" do
    System.put_env("TIME_ZONE", "UTC")
    oracle = fixture("admin_setting_writes", "background_timezone_callback")
    assert oracle["before_timezone"] == nil and oracle["stat_version"] == 0
    assert oracle["job"]["class"] == "Stats::CalculatingJob"
    Repo.query!("UPDATE users SET settings=$1 WHERE id=15802", [%{"locale" => "en"}], log: false)

    Repo.query!(
      "INSERT INTO stats (user_id,year,month,distance,calculation_version,created_at,updated_at) VALUES (15802,2026,9,1000,7,'2026-10-03','2026-10-03')",
      [],
      log: false
    )

    before = callback_snapshot()
    handoff!("PATCH", "/settings/background_jobs", oracle["body"], 15802)
    assert callback_snapshot() == before
  end

  test "missing required groups reach Rails with original bytes and no native effects" do
    before = callback_snapshot()

    for {dir, name, method, path} <- [
          {"admin_mutations", "missing_user_create", "POST", "/settings/users"},
          {"admin_mutations", "missing_user_update", "PATCH", "/settings/users/15802"},
          {"admin_setting_writes", "missing_background_settings", "POST",
           "/settings/background_jobs"}
        ] do
      oracle = fixture(dir, name)
      assert oracle["status"] == 400 and oracle["unchanged"]
      assert oracle["error"] == "ActionController::ParameterMissing"
      handoff!(method, path, oracle["body"], 15801)
      assert callback_snapshot() == before
    end
  end

  defp callback_snapshot do
    for table <- ~w(users stats job_outbox oban.oban_jobs) do
      Repo.query!("SELECT to_jsonb(t) FROM #{table} t ORDER BY to_jsonb(t)::text", [], log: false).rows
    end
  end

  defp actor_session(actor),
    do:
      RailsUser.session(actor, %{"_csrf_token" => Base.url_encode64(<<0::256>>, padding: false)})

  defp request(method, path, raw, actor, headers \\ []) do
    session = if actor, do: actor_session(actor), else: %{}

    conn =
      build_conn()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", to_string(byte_size(raw)))
      |> put_req_header("accept", "text/html")
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))

    effective =
      if method == "POST" and raw =~ "_method=",
        do: URI.decode_query(raw)["_method"] |> String.upcase(),
        else: method

    token = RailsCsrf.masked_form_token(session, URI.parse(path).path, effective)

    conn =
      if is_binary(token) and not String.contains?(raw, "authenticity_token="),
        do: put_req_header(conn, "x-csrf-token", token),
        else: conn

    conn = Enum.reduce(headers, conn, fn {k, v}, c -> put_req_header(c, k, v) end)
    dispatch(conn, @endpoint, method, path, raw)
  end

  defp handoff!(method, path, raw, actor, headers \\ []) do
    conn = request(method, path, raw, actor, headers)
    assert conn.status == 218 and conn.resp_body == "Rails"
    assert_receive {:upstream, line, length, body}
    same_line = line == method <> " " <> path <> " HTTP/1.1"
    assert same_line, "upstream request line changed"
    assert length == byte_size(raw)
    same_body = body == raw
    assert same_body, "upstream body bytes changed"
  end

  defp upstream_loop(server, owner) do
    socket = RawHTTP.accept(server)
    {head, rest} = RawHTTP.read_head(socket)

    length =
      case RawHTTP.header(head, "content-length") do
        [] -> 0
        [n] -> String.to_integer(n)
      end

    body = binary_part(RawHTTP.read_at_least(socket, rest, length), 0, length)
    send(owner, {:upstream, RawHTTP.request_line(head), length, body})
    RawHTTP.reply(socket, "HTTP/1.1 218 Rails\r\ncontent-length: 5\r\n\r\nRails")
    :gen_tcp.close(socket)
    upstream_loop(server, owner)
  end

  defp fixture(dir, name), do: File.read!("test/fixtures/#{dir}/#{name}.json") |> Jason.decode!()

  defp snapshot,
    do:
      Repo.query!(
        "SELECT id,email,admin,status,deleted_at,reset_password_token,sign_in_count FROM users ORDER BY id",
        [],
        log: false
      ).rows

  defp welcome_path(jti \\ "a10b-ownership-welcome") do
    payload = %{
      "purpose" => "trial_welcome",
      "user_id" => 15802,
      "jti" => jti,
      "exp" => System.system_time(:second) + 1800
    }

    input =
      Base.url_encode64(~s({"alg":"HS256"}), padding: false) <>
        "." <> Base.url_encode64(Jason.encode!(payload), padding: false)

    token =
      input <>
        "." <>
        Base.url_encode64(:crypto.mac(:hmac, :sha256, System.fetch_env!("JWT_SECRET_KEY"), input),
          padding: false
        )

    "/trial/welcome?" <> URI.encode_query(%{"token" => token})
  end
end

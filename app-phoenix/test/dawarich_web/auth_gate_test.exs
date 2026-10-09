defmodule DawarichWeb.AuthGateTest do
  use ExUnit.Case, async: false

  alias DawarichWeb.AuthGate
  import Plug.Conn
  import Dawarich.Test.RawHTTP
  alias Dawarich.{RailsCookies, Repo}
  alias Dawarich.Auth.{RegistrationSetting, SessionCookie}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf

  @credentials [
    {:get, "/users/sign_in"},
    {:post, "/users/sign_in"},
    {:post, "/users/sign_out"},
    {:delete, "/users/sign_out"}
  ]
  @recovery [
    {:get, "/users/password/new"},
    {:get, "/users/password/edit"},
    {:post, "/users/password"},
    {:put, "/users/password"},
    {:get, "/users/unlock/new"},
    {:get, "/users/unlock"},
    {:post, "/users/unlock"}
  ]
  @elsewhere [
    {:head, "/users/sign_in"},
    {:get, "/users/sign_in/"},
    {:get, "/users/edit"},
    {:post, "/users"},
    {:get, "/users/sign_up"}
  ]

  @account_link [{:get, "/auth/account_link/challenge"}, {:post, "/auth/account_link/challenge"}]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Dawarich.State.put_registration_enabled(Repo, false)
    Application.delete_env(:dawarich, :phoenix_auth)
    cloud_config = Map.new(~w(MANAGER_URL JWT_SECRET_KEY), &{&1, System.get_env(&1)})
    System.put_env("MANAGER_URL", "https://manager.example.invalid")
    System.put_env("JWT_SECRET_KEY", "synthetic-auth-gate-key")
    previous = System.get_env("SELF_HOSTED")
    previous_flows = System.get_env("DAWARICH_PHOENIX_AUTH")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      Application.delete_env(:dawarich, :phoenix_auth)

      for {key, value} <- cloud_config do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end

      if previous_flows,
        do: System.put_env("DAWARICH_PHOENIX_AUTH", previous_flows),
        else: System.delete_env("DAWARICH_PHOENIX_AUTH")

      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)
  end

  defp request({method, path}) do
    body = "authenticity_token=x&user%5Bemail%5D=a%40dawarich.test"

    Plug.Test.conn(method, path, body)
    |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
    |> Plug.Conn.put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> Plug.Conn.put_req_header("cookie", "_dawarich_session=opaque")
  end

  defp untouched(routes) do
    for route <- routes do
      conn = request(route)
      assert AuthGate.call(conn, []) == conn, inspect(route)
    end
  end

  test "api_auth is independently off by default and owns both endpoints only when selected" do
    previous = Application.get_env(:dawarich, :api_auth_context)

    env =
      Jason.decode!(File.read!("test/fixtures/active_record_encryption.json"))["environments"]
      |> Enum.find(&(&1["name"] == "explicit keys"))
      |> Map.fetch!("env")

    context = %{
      self_hosted: true,
      oidc: false,
      env:
        Map.put(
          env,
          "JWT_SECRET_KEY",
          Dawarich.Auth.TwoFactor.Totp.generate_secret("a11f signing fixture")
        ),
      timezone: "Etc/UTC"
    }

    Application.put_env(:dawarich, :api_auth_context, context)
    on_exit(fn -> Application.put_env(:dawarich, :api_auth_context, previous) end)

    hash =
      Jason.decode!(File.read!("test/fixtures/auth/requests.json"))["login"]["user"][
        "encrypted_password"
      ]

    RailsUser.insert!(%{
      id: 75_1110,
      email: "a11f-gate@example.invalid",
      encrypted_password: hash,
      api_key: "synthetic fixture words",
      settings: %{},
      subscription_source: 0,
      active_until: nil
    })

    raw = ~s({"email":"a11f-gate@example.invalid","password":"safepassword12"})

    conn =
      Plug.Test.conn("POST", "/api/v1/auth/login", raw)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
      |> put_req_header("accept", "application/json")

    otp = %{conn | request_path: "/api/v1/auth/otp_challenge"}

    for flows <- [nil, [], ~w(credentials recovery account api_keys two_factor otp account_link)] do
      if flows,
        do: Application.put_env(:dawarich, :phoenix_auth, flows),
        else: Application.delete_env(:dawarich, :phoenix_auth)

      assert AuthGate.call(conn, []) == conn
      assert AuthGate.call(otp, []) == otp
    end

    for flows <- [
          ["api_auth"],
          ~w(credentials recovery account api_keys two_factor otp account_link api_auth)
        ] do
      Application.put_env(:dawarich, :phoenix_auth, flows)
      result = AuthGate.call(conn, [])
      assert result.status == 200
      assert get_resp_header(result, "x-dawarich-auth-owner") == ["native-api-auth"]
    end

    {:ok, cipher} =
      Dawarich.Auth.TwoFactor.Secret.encrypt("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", env)

    Repo.query!(
      "UPDATE users SET otp_required_for_login=true,otp_secret=$2 WHERE id=$1",
      [75_1110, cipher],
      log: false
    )

    assert AuthGate.call(conn, []).status == 202

    for path <- [
          "/api/v1/auth/register",
          "/api/v1/auth/apple",
          "/api/v1/auth/google",
          "/api/v1/auth/login/",
          "/api/v1/users/me"
        ] do
      elsewhere = %{conn | request_path: path}
      assert AuthGate.call(elsewhere, []) == elsewhere
    end

    System.put_env("SELF_HOSTED", "false")
    assert AuthGate.call(conn, []) == conn
    assert AuthGate.call(otp, []) == otp
  end

  test "with no flow named, every auth request passes through untouched" do
    untouched(@credentials ++ @recovery ++ @elsewhere ++ @account_link)
  end

  test "reserved and unknown flow names change nothing" do
    Application.put_env(
      :dawarich,
      :phoenix_auth,
      ~w(registration two_factor remember oauth bogus)
    )

    untouched(@credentials ++ @recovery ++ @elsewhere ++ @account_link)
  end

  test "credentials claims only its own four routes" do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    untouched(@recovery ++ @elsewhere ++ @account_link)
  end

  test "recovery claims only its own seven routes" do
    Application.put_env(:dawarich, :phoenix_auth, ["recovery"])
    untouched(@credentials ++ @elsewhere ++ @account_link)
  end

  test "credentials and recovery on, an instance that is not self-hosted: even their own routes pass untouched" do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials", "recovery"])

    for value <- [nil, "false", "TRUE", ""] do
      if value, do: System.put_env("SELF_HOSTED", value), else: System.delete_env("SELF_HOSTED")
      untouched(@credentials ++ @recovery)
    end
  end

  test "new auth keys opt in independently, the retired api_keys key owns nothing, and OFF requests stay identical" do
    account = [{:put, "/users"}, {:patch, "/users"}, {:post, "/users"}]
    keys = [{:post, "/settings/generate_api_key"}]

    for flows <- [nil, [], ["bogus"]] do
      if flows,
        do: Application.put_env(:dawarich, :phoenix_auth, flows),
        else: Application.delete_env(:dawarich, :phoenix_auth)

      untouched(account ++ keys ++ @credentials ++ @recovery)
    end

    {session, previous_secret} = account_actor()
    on_exit(fn -> Application.put_env(:dawarich, :rails_secret, previous_secret) end)

    for flows <- [["account"], ["api_keys"], ~w(account api_keys credentials recovery)] do
      Application.put_env(:dawarich, :phoenix_auth, flows)

      if "account" in flows do
        body =
          URI.encode_query(%{
            "_method" => "put",
            "user[current_password]" => "a11rest-gate-password",
            "authenticity_token" => RailsCsrf.masked_token(session)
          })

        conn = AuthGate.call(authenticated(session, "/users", body), [])
        assert conn.status == 303
        assert get_resp_header(conn, "x-dawarich-auth-owner") == ["native-account"]
      else
        untouched(account)
      end

      untouched(keys)

      if "credentials" not in flows, do: untouched(@credentials)
      if "recovery" not in flows, do: untouched(@recovery)

      untouched([
        {:get, "/users/edit"},
        {:delete, "/users"},
        {:post, "/settings/users/74002/regenerate_api_key"}
      ])
    end

    for value <- [nil, "false", "TRUE", ""] do
      if value, do: System.put_env("SELF_HOSTED", value), else: System.delete_env("SELF_HOSTED")
      untouched(account ++ keys ++ @credentials ++ @recovery)
    end

    System.put_env("DAWARICH_PHOENIX_AUTH", " Account, API_KEYS, credentials, recovery, unknown ")
    config = Config.Reader.read!(Path.expand("../../config/runtime.exs", __DIR__), env: :prod)
    assert config[:dawarich][:phoenix_auth] == ~w(account api_keys credentials recovery unknown)
    System.delete_env("DAWARICH_PHOENIX_AUTH")
  end

  test "account writes do not require registration state availability" do
    {session, previous_secret} = account_actor()
    cache = Process.whereis(Dawarich.Redis.Cache)
    if cache, do: Process.unregister(Dawarich.Redis.Cache)

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_secret, previous_secret)
      if cache && Process.alive?(cache), do: Process.register(cache, Dawarich.Redis.Cache)
    end)

    Repo.query!("DELETE FROM phoenix.registration_setting", [], log: false)
    assert RegistrationSetting.fetch() == :error
    Application.put_env(:dawarich, :phoenix_auth, ~w(account api_keys credentials recovery))
    owner = self()
    tracer = spawn(fn -> trace_calls(owner) end)
    :erlang.trace_pattern({RegistrationSetting, :fetch, 0}, true, [:local])
    :erlang.trace(self(), true, [:call, {:tracer, tracer}])

    on_exit(fn ->
      :erlang.trace_pattern({RegistrationSetting, :fetch, 0}, false, [:local])
      Process.exit(tracer, :kill)
    end)

    body =
      URI.encode_query(%{
        "user[current_password]" => "a11rest-gate-password",
        "authenticity_token" => RailsCsrf.masked_token(session)
      })

    conn = authenticated(session, "/users", body)
    conn = %{conn | method: "PATCH"}
    assert AuthGate.call(conn, []).status == 303

    barrier = :erlang.trace_delivered(self())
    assert_receive {:trace_delivered, _, ^barrier}
    send(tracer, {:barrier, barrier})
    assert_receive {:barrier, ^barrier}
    refute_received :registration_fetch
    :erlang.trace(self(), false, [:call])

    upstream = listen()
    old = Application.fetch_env!(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, old)
      :gen_tcp.close(upstream.listen)
    end)

    for route <- [{:get, "/users/sign_in"}, {:get, "/users/password/new"}] do
      task =
        Task.async(fn ->
          socket = accept(upstream)
          {head, _} = read_head(socket)
          reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
          :gen_tcp.close(socket)
          request_line(head)
        end)

      result = AuthGate.call(request(route), [])
      assert result.halted and result.resp_body == "puma"
      assert Task.await(task) =~ elem(route, 1)
    end
  end

  defp trace_calls(owner) do
    receive do
      {:trace, _, :call, {RegistrationSetting, :fetch, []}} ->
        send(owner, :registration_fetch)
        trace_calls(owner)

      {:barrier, ref} ->
        send(owner, {:barrier, ref})
        trace_calls(owner)
    end
  end

  test "two_factor opts in independently without registration state" do
    routes = [
      {:get, "/settings/two_factor"},
      {:post, "/settings/two_factor"},
      {:post, "/settings/two_factor/verify"},
      {:delete, "/settings/two_factor"}
    ]

    for flows <- [nil, [], ["unknown"], ~w(credentials recovery account api_keys)] do
      if flows,
        do: Application.put_env(:dawarich, :phoenix_auth, flows),
        else: Application.delete_env(:dawarich, :phoenix_auth)

      untouched(routes)
    end

    {session, previous_secret} = account_actor()
    cache = Process.whereis(Dawarich.Redis.Cache)
    if cache, do: Process.unregister(Dawarich.Redis.Cache)

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_secret, previous_secret)
      if cache && Process.alive?(cache), do: Process.register(cache, Dawarich.Redis.Cache)
    end)

    Repo.query!("DELETE FROM phoenix.registration_setting", [], log: false)
    assert RegistrationSetting.fetch() == :error
    owner = self()
    tracer = spawn(fn -> trace_calls(owner) end)
    :erlang.trace_pattern({RegistrationSetting, :fetch, 0}, true, [:local])
    :erlang.trace(self(), true, [:call, {:tracer, tracer}])

    on_exit(fn ->
      :erlang.trace_pattern({RegistrationSetting, :fetch, 0}, false, [:local])
      Process.exit(tracer, :kill)
    end)

    for flows <- [["two_factor"], ~w(credentials recovery account api_keys two_factor)] do
      Application.put_env(:dawarich, :phoenix_auth, flows)
      conn = authenticated(session, "/settings/two_factor", "")
      result = %{conn | method: "GET"} |> AuthGate.call([])
      assert get_resp_header(result, "x-dawarich-auth-owner") == ["native-two-factor"]
      assert result.status in [200, 302]
      if flows == ["two_factor"], do: untouched(@credentials ++ @recovery)
    end

    barrier = :erlang.trace_delivered(self())
    assert_receive {:trace_delivered, _, ^barrier}
    send(tracer, {:barrier, barrier})
    assert_receive {:barrier, ^barrier}
    refute_received :registration_fetch
    :erlang.trace(self(), false, [:call])

    for value <- [nil, "false", "TRUE", ""] do
      if value, do: System.put_env("SELF_HOSTED", value), else: System.delete_env("SELF_HOSTED")
      untouched(routes)
    end

    System.put_env("DAWARICH_PHOENIX_AUTH", " Two_Factor, credentials, Unknown ")
    config = Config.Reader.read!(Path.expand("../../config/runtime.exs", __DIR__), env: :prod)
    assert config[:dawarich][:phoenix_auth] == ~w(two_factor credentials unknown)
  end

  test "OTP opt-in is independent and respects existing credentials and management keys" do
    otp = [{:post, "/users/otp_challenge"}]

    for flows <- [nil, [], ["unknown"], ~w(credentials two_factor)] do
      if flows,
        do: Application.put_env(:dawarich, :phoenix_auth, flows),
        else: Application.delete_env(:dawarich, :phoenix_auth)

      untouched(otp)
    end

    cache = Process.whereis(Dawarich.Redis.Cache)
    if cache, do: Process.unregister(Dawarich.Redis.Cache)

    on_exit(fn ->
      if cache && Process.alive?(cache), do: Process.register(cache, Dawarich.Redis.Cache)
    end)

    Repo.query!("DELETE FROM phoenix.registration_setting", [], log: false)
    assert RegistrationSetting.fetch() == :error
    {session, _} = SessionCookie.for_form(%{}, Application.fetch_env!(:dawarich, :rails_secret))

    body =
      URI.encode_query(%{
        "authenticity_token" =>
          RailsCsrf.masked_form_token(session, "/users/otp_challenge", "POST"),
        "otp_attempt" => "unused"
      })

    for flows <- [["otp"], ~w(otp credentials two_factor)] do
      Application.put_env(:dawarich, :phoenix_auth, flows)
      conn = AuthGate.call(authenticated(session, "/users/otp_challenge", body), [])
      assert conn.status == 302
      assert get_resp_header(conn, "x-dawarich-auth-owner") == ["native-otp"]
      if flows == ["otp"], do: untouched(@credentials ++ [{:get, "/settings/two_factor"}])
    end

    for value <- [nil, "false", "TRUE", ""] do
      if value, do: System.put_env("SELF_HOSTED", value), else: System.delete_env("SELF_HOSTED")
      untouched(otp)
    end

    System.put_env("DAWARICH_PHOENIX_AUTH", " OTP, credentials, Two_Factor, unknown ")
    config = Config.Reader.read!(Path.expand("../../config/runtime.exs", __DIR__), env: :prod)
    assert config[:dawarich][:phoenix_auth] == ~w(otp credentials two_factor unknown)
  end

  defp account_actor do
    secret = Application.fetch_env!(:dawarich, :rails_secret)
    hash = Bcrypt.hash_pwd_salt("a11rest-gate-password", log_rounds: 4)

    RailsUser.insert!(%{
      id: 74002,
      email: "a11rest-gate@dawarich.test",
      encrypted_password: hash,
      api_key: "A11REST_GATE_KEY",
      settings: %{}
    })

    {session, _} = SessionCookie.for_form(%{}, secret)
    {Map.put(session, "warden.user.user.key", [[74002], binary_part(hash, 0, 29)]), secret}
  end

  defp authenticated(session, path, body) do
    Plug.Test.conn("POST", "http://www.example.com" <> path, body)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("accept", "text/html")
    |> Plug.Test.put_req_cookie(
      "_dawarich_session",
      RailsCookies.encrypt(
        session,
        "_dawarich_session",
        Application.fetch_env!(:dawarich, :rails_secret)
      )
    )
  end
end

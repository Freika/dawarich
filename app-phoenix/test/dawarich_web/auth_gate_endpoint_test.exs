defmodule DawarichWeb.AuthGateEndpointTest do
  use Dawarich.IngestCase, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP

  alias Dawarich.{RailsCookies, RailsSecret}
  alias DawarichWeb.RailsCsrf

  @hash Jason.decode!(File.read!(Path.expand("../fixtures/auth/requests.json", __DIR__)))[
          "user_before"
        ]["encrypted_password"]
  @env ~w(SELF_HOSTED DAWARICH_RAILS_SLICES APPLICATION_PROTOCOL RAILS_ENV RACK_ENV OIDC_CLIENT_ID OIDC_CLIENT_SECRET
          OIDC_PKCE_ENABLED GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET)

  setup do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    Dawarich.State.put_registration_enabled(Repo, false)
    previous = Map.new(@env, &{&1, System.get_env(&1)})
    Enum.each(@env, &System.delete_env/1)
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, nil)
      Application.delete_env(:dawarich, :phoenix_auth)

      for {name, value} <- previous,
          do: if(value, do: System.put_env(name, value), else: System.delete_env(name))
    end)

    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    %{port: port, upstream: upstream}
  end

  defp registration(name),
    do:
      Dawarich.State.put_registration_enabled(
        Repo,
        %{"true" => true, "false" => false, "nil" => nil}[name]
      )

  defp guest do
    session = %{"session_id" => "a11a-guest", "_csrf_token" => RailsCsrf.new_token()}

    {session,
     "_dawarich_session=" <>
       RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())}
  end

  defp get(path), do: "GET #{path} HTTP/1.1\r\nHost: a\r\n\r\n"

  defp form(method, path, cookie, body, extra \\ "") do
    "#{method} #{path} HTTP/1.1\r\nHost: a\r\nCookie: #{cookie}\r\n#{extra}" <>
      "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}"
  end

  defp exchange(ctx, request) do
    client = connect(ctx.port)
    send_raw(client, request)
    read_response(client)
  end

  defp to_puma(ctx, request) do
    client = connect(ctx.port)
    send_raw(client, request)
    puma = accept(ctx.upstream)
    {head, rest} = read_head(puma)
    length = head |> header("content-length") |> List.first("0") |> String.to_integer()
    body = binary_part(read_at_least(puma, rest, length), 0, length)
    reply(puma, "HTTP/1.1 200 OK\r\nSet-Cookie: rails=1; path=/\r\nContent-Length: 4\r\n\r\npuma")
    {status, headers, answer} = read_response(client)

    %{
      line: request_line(head),
      cookie: header(head, "cookie"),
      body: body,
      response:
        {status, values(headers, "set-cookie"), values(headers, "x-dawarich-auth-owner"), answer}
    }
  end

  defp no_puma(ctx), do: assert({:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 200))

  test "real endpoint supports native and Rails OTP phases without duplicate effects", ctx do
    names =
      ~w(OTP_ENCRYPTION_PRIMARY_KEY OTP_ENCRYPTION_DETERMINISTIC_KEY OTP_ENCRYPTION_KEY_DERIVATION_SALT)

    old = Map.new(names, &{&1, System.get_env(&1)})
    Enum.each(names, &System.put_env(&1, "a11d-endpoint-synthetic"))

    on_exit(fn ->
      for {k, v} <- old, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
    end)

    otp = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    {:ok, cipher} = Dawarich.Auth.TwoFactor.Secret.encrypt(otp)
    id = user!(%{email: "a11d-endpoint@dawarich.test", encrypted_password: @hash, settings: %{}})

    Repo.query!(
      "UPDATE users SET otp_required_for_login=true,otp_secret=$2 WHERE id=$1",
      [id, cipher],
      log: false
    )

    {session, cookie} = guest()

    login =
      URI.encode_query(%{
        "authenticity_token" => RailsCsrf.masked_token(session),
        "user[email]" => "a11d-endpoint@dawarich.test",
        "user[password]" => "safepassword12"
      })

    Application.put_env(:dawarich, :phoenix_auth, ~w(credentials otp))
    registration("false")

    peer =
      Task.async(fn ->
        case :gen_tcp.accept(ctx.upstream.listen, 200) do
          {:error, :timeout} ->
            :none

          {:ok, socket} ->
            read_head(socket)
            reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
            :puma
        end
      end)

    response =
      exchange(ctx, form("POST", "/users/sign_in", cookie, login, "Accept: text/html\r\n"))

    assert Task.await(peer) == :none
    assert {422, headers, _} = response
    assert values(headers, "x-dawarich-auth-owner") == ["native-otp"]

    pending_cookie =
      Enum.find(values(headers, "set-cookie"), &String.starts_with?(&1, "_dawarich_session="))
      |> String.split(";")
      |> hd()

    [_, value] = String.split(pending_cookie, "=", parts: 2)

    {:ok, pending} =
      RailsCookies.decrypt(value, "_dawarich_session", RailsSecret.fetch(), DateTime.utc_now())

    assert pending["otp_user_id"] == id and pending["warden.user.user.key"] == nil

    attempt =
      URI.encode_query(%{
        "authenticity_token" =>
          RailsCsrf.masked_form_token(pending, "/users/otp_challenge", "POST"),
        "otp_attempt" => "invalid"
      })

    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    seen = to_puma(ctx, form("POST", "/users/otp_challenge", pending_cookie, attempt))
    assert seen.body == attempt
    Application.put_env(:dawarich, :phoenix_auth, ["otp"])

    parsed =
      Plug.Test.conn("POST", "http://www.example.com/users/otp_challenge", attempt)
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> Plug.Conn.put_req_header("content-length", Integer.to_string(byte_size(attempt)))
      |> Plug.Test.put_req_cookie("_dawarich_session", value)

    DawarichWeb.AuthOtp.Http.call(parsed,
      enabled: true,
      fallback: fn conn ->
        preserved = conn.private[:dawarich_raw_body] == attempt
        assert preserved
        conn
      end
    )

    seen = to_puma(ctx, form("POST", "/users/otp_challenge", pending_cookie, attempt))
    assert seen.body == attempt and seen.response == {200, ["rails=1; path=/"], [], "puma"}

    assert Repo.query!(
             "SELECT sign_in_count,consumed_timestep,failed_otp_attempts FROM users WHERE id=$1",
             [id],
             log: false
           ).rows == [[0, nil, 0]]

    now = DateTime.utc_now() |> DateTime.to_unix()

    source_pending =
      Map.merge(session, %{
        "otp_user_id" => id,
        "otp_challenge_at" => now,
        "otp_remember_me" => false
      })

    source_cookie =
      "_dawarich_session=" <>
        RailsCookies.encrypt(source_pending, "_dawarich_session", RailsSecret.fetch())

    good =
      URI.encode_query(%{
        "authenticity_token" => RailsCsrf.masked_token(source_pending),
        "otp_attempt" => Dawarich.Auth.TwoFactor.Totp.at(otp, now)
      })

    Repo.query!("DELETE FROM phoenix.registration_setting", [], log: false)

    assert {302, headers, ""} =
             exchange(ctx, form("POST", "/users/otp_challenge", source_cookie, good))

    assert values(headers, "x-dawarich-auth-owner") == ["native-otp"]
    assert Repo.query!("SELECT sign_in_count FROM users WHERE id=$1", [id]).rows == [[1]]
    assert to_puma(ctx, form("POST", "/users/otp_challenge", source_cookie, good)).body == good

    for path <- ~w(/users/password /api/v1/auth/otp_challenge /users/auth/github /users/sign_in) do
      assert to_puma(ctx, form("POST", path, cookie, attempt)).body == attempt
    end

    no_puma(ctx)
  end

  test "endpoint management ownership and OTP login handback remain independent", ctx do
    names =
      ~w(OTP_ENCRYPTION_PRIMARY_KEY OTP_ENCRYPTION_DETERMINISTIC_KEY OTP_ENCRYPTION_KEY_DERIVATION_SALT)

    previous = Map.new(names, &{&1, System.get_env(&1)})
    Enum.each(names, &System.put_env(&1, "a11c-endpoint-synthetic-not-for-production"))

    on_exit(fn ->
      for {name, value} <- previous,
          do: if(value, do: System.put_env(name, value), else: System.delete_env(name))
    end)

    id = user!(%{email: "a11c-endpoint@dawarich.test", encrypted_password: @hash, settings: %{}})

    {session, _} =
      Dawarich.Auth.SessionCookie.for_form(%{"user_return_to" => "/stats"}, RailsSecret.fetch())

    session = Map.put(session, "warden.user.user.key", [[id], binary_part(@hash, 0, 29)])

    cookie =
      "_dawarich_session=" <>
        RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())

    path = "/settings/two_factor"
    token = RailsCsrf.masked_token(session)
    body = URI.encode_query(%{"authenticity_token" => token})

    for {method, target} <- [
          {"GET", path},
          {"POST", path},
          {"POST", path <> "/verify"},
          {"DELETE", path}
        ] do
      seen = to_puma(ctx, form(method, target, cookie, body))
      assert seen.body == body and seen.line == "#{method} #{target} HTTP/1.1"
      assert seen.response == {200, ["rails=1; path=/"], [], "puma"}
    end

    Application.put_env(:dawarich, :phoenix_auth, ["two_factor"])

    peer =
      Task.async(fn ->
        case :gen_tcp.accept(ctx.upstream.listen, 200) do
          {:error, :timeout} ->
            :none

          {:ok, socket} ->
            read_head(socket)
            reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
            :puma
        end
      end)

    assert {200, headers, _} = exchange(ctx, form("GET", path, cookie, ""))
    assert Task.await(peer) == :none
    assert values(headers, "x-dawarich-auth-owner") == ["native-two-factor"]
    assert {200, headers, _} = exchange(ctx, form("POST", path, cookie, body))
    assert values(headers, "x-dawarich-auth-owner") == ["native-two-factor"]
    assert [[ciphertext]] = Repo.query!("SELECT otp_secret FROM users WHERE id=$1", [id]).rows
    {:ok, secret} = Dawarich.Auth.TwoFactor.Secret.decrypt(ciphertext)
    now = DateTime.utc_now() |> DateTime.to_unix()

    verify =
      URI.encode_query(%{
        "authenticity_token" => token,
        "otp_attempt" => Dawarich.Auth.TwoFactor.Totp.at(secret, now)
      })

    assert {200, headers, _} = exchange(ctx, form("POST", path <> "/verify", cookie, verify))
    assert values(headers, "x-dawarich-auth-owner") == ["native-two-factor"]

    assert Repo.query!("SELECT otp_required_for_login,sign_in_count FROM users WHERE id=$1", [id]).rows ==
             [[true, 0]]

    no_puma(ctx)
    Application.put_env(:dawarich, :phoenix_auth, ~w(two_factor credentials))
    registration("false")

    login =
      URI.encode_query(%{
        "authenticity_token" => token,
        "user[email]" => "a11c-endpoint@dawarich.test",
        "user[password]" => "safepassword12"
      })

    assert to_puma(ctx, form("POST", "/users/sign_in", cookie, login)).body == login
    unsupported = body <> "&_method=patch"
    seen = to_puma(ctx, form("POST", path, cookie, unsupported))
    assert seen.body == unsupported and seen.line == "POST #{path} HTTP/1.1"
    assert seen.response == {200, ["rails=1; path=/"], [], "puma"}

    for target <- ~w(/users/otp_challenge /api/v1/auth/otp_challenge) do
      assert to_puma(ctx, form("POST", target, cookie, body)).body == body
    end

    System.put_env("DAWARICH_RAILS_SLICES", "api_account")

    for target <-
          ~w(/api/v1/users/me/two_factor/setup /api/v1/users/me/two_factor/confirm /api/v1/users/me/two_factor/backup_codes) do
      assert to_puma(ctx, form("POST", target, cookie, body)).body == body
    end

    assert to_puma(ctx, form("DELETE", "/api/v1/users/me/two_factor", cookie, body)).body == body
    System.delete_env("DAWARICH_RAILS_SLICES")

    disable =
      URI.encode_query(%{
        "authenticity_token" => token,
        "_method" => "delete",
        "password" => "safepassword12",
        "otp_attempt" => Dawarich.Auth.TwoFactor.Totp.at(secret, now + 30)
      })

    assert {302, headers, ""} = exchange(ctx, form("POST", path, cookie, disable))
    assert values(headers, "x-dawarich-auth-owner") == ["native-two-factor"]

    assert Repo.query!(
             "SELECT otp_required_for_login,otp_secret,otp_backup_codes,sign_in_count FROM users WHERE id=$1",
             [id]
           ).rows == [[false, nil, nil, 0]]

    no_puma(ctx)
  end

  test "every flow is off by default: auth requests reach Puma byte for byte", ctx do
    {_session, cookie} = guest()
    body = "authenticity_token=x&user%5Bemail%5D=a%40dawarich.test&user%5Bpassword%5D=p"

    for {method, path} <- [
          {"POST", "/users/sign_in"},
          {"POST", "/users/sign_out"},
          {"POST", "/users/password"},
          {"PUT", "/users/password"},
          {"POST", "/users/unlock"}
        ] do
      seen = to_puma(ctx, form(method, path, cookie, body))
      assert seen.line == "#{method} #{path} HTTP/1.1"
      assert seen.cookie == [cookie]
      assert seen.body == body
      assert seen.response == {200, ["rails=1; path=/"], [], "puma"}
    end

    for path <-
          ~w(/users/sign_in /users/password/new /users/password/edit /users/unlock/new /users/unlock),
        do: assert(to_puma(ctx, get(path)).line == "GET #{path} HTTP/1.1")
  end

  test "credentials on: Phoenix answers the sign-in form with Rails' sign-up link rule", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    registration("false")

    assert {200, headers, body} = exchange(ctx, get("/users/sign_in"))
    assert values(headers, "x-dawarich-auth-owner") == ["native-credentials"]
    assert body =~ ~s(action="/users/sign_in")
    refute body =~ ~s(href="/users/sign_up")
    no_puma(ctx)

    registration("true")
    assert {200, _headers, body} = exchange(ctx, get("/users/sign_in"))
    assert body =~ ~s(href="/users/sign_up")
  end

  test "credentials on: a correct password signs in through Phoenix", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    registration("false")
    email = "a11a-#{System.unique_integer([:positive])}@dawarich.test"
    id = user!(%{email: email, encrypted_password: @hash})
    {session, cookie} = guest()

    body =
      URI.encode_query([
        {"authenticity_token", RailsCsrf.masked_token(session)},
        {"user[email]", email},
        {"user[password]", "safepassword12"},
        {"user[remember_me]", "0"}
      ])

    assert {303, headers, ""} = exchange(ctx, form("POST", "/users/sign_in", cookie, body))
    assert values(headers, "x-dawarich-auth-owner") == ["native-credentials"]
    assert values(headers, "location") == ["http://a/"]

    assert Enum.any?(
             values(headers, "set-cookie"),
             &String.starts_with?(&1, "_dawarich_session=")
           )

    assert Repo.query!("SELECT sign_in_count FROM users WHERE id = $1", [id]).rows == [[1]]
    no_puma(ctx)
  end

  test "nil or failed registration read retains each auth reader admission boundary", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ~w(credentials recovery))
    registration("nil")

    for path <- ["/users/sign_in", "/users/password/new"] do
      assert to_puma(ctx, get(path)).line == "GET #{path} HTTP/1.1"
    end

    Repo.query!(
      "ALTER TABLE phoenix.registration_setting RENAME COLUMN enabled TO unavailable",
      [],
      log: false
    )

    for path <- ["/users/sign_in", "/users/password/new"] do
      assert to_puma(ctx, get(path)).line == "GET #{path} HTTP/1.1"
    end
  end

  test "credentials on: what Phoenix cannot serve reaches Puma with the request intact", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    registration("false")
    {_session, cookie} = guest()

    body =
      "authenticity_token=forged&user%5Bemail%5D=a%40dawarich.test&user%5Bpassword%5D=p&user%5Bremember_me%5D=0"

    for extra <- ["", "X-Forwarded-For: 192.0.2.1\r\n"] do
      seen = to_puma(ctx, form("POST", "/users/sign_in", cookie, body, extra))
      assert seen.line == "POST /users/sign_in HTTP/1.1"
      assert seen.cookie == [cookie]
      assert seen.body == body
      assert seen.response == {200, ["rails=1; path=/"], [], "puma"}
    end

    registration("nil")
    assert to_puma(ctx, get("/users/sign_in")).line == "GET /users/sign_in HTTP/1.1"

    registration("false")
    System.put_env("SELF_HOSTED", "false")
    assert to_puma(ctx, get("/users/sign_in")).line == "GET /users/sign_in HTTP/1.1"
  end

  test "credentials on, not self-hosted: Puma answers before Phoenix's own SSL check can", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    registration("false")
    System.put_env("SELF_HOSTED", "false")
    System.put_env("APPLICATION_PROTOCOL", "https")
    System.put_env("RAILS_ENV", "production")

    seen = to_puma(ctx, get("/users/sign_in"))
    assert seen.line == "GET /users/sign_in HTTP/1.1"
    assert seen.response == {200, ["rails=1; path=/"], [], "puma"}
  end

  test "credentials on: the invitation variant of the sign-in page stays with Rails", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    registration("false")

    path = "/users/sign_in?invitation_token=abc"
    assert to_puma(ctx, get(path)).line == "GET #{path} HTTP/1.1"

    {session, _cookie} = guest()
    session = Map.put(session, "invitation_token", "abc")

    cookie =
      "_dawarich_session=" <>
        RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())

    request = "GET /users/sign_in HTTP/1.1\r\nHost: a\r\nCookie: #{cookie}\r\n\r\n"
    assert to_puma(ctx, request).line == "GET /users/sign_in HTTP/1.1"
  end

  describe "recovery" do
    setup do
      names = ~w(SMTP_FROM SMTP_SERVER E2E_SMTP_PORT DOMAIN SMTP_AUTHENTICATION)
      saved = for name <- names, value = System.get_env(name), do: {name, value}
      Enum.each(names, &System.delete_env/1)

      on_exit(fn ->
        Enum.each(names, &System.delete_env/1)
        Enum.each(saved, fn {name, value} -> System.put_env(name, value) end)
      end)

      registration("false")
      :ok
    end

    defp mail_setup do
      System.put_env("RAILS_ENV", "production")
      System.put_env("SMTP_FROM", "Dawarich <a11a@dawarich.test>")
      System.put_env("SMTP_SERVER", "smtp.example.test")
      System.put_env("DOMAIN", "dawarich.example.test")
    end

    defp recovery_post(email) do
      {session, cookie} = guest()

      body =
        URI.encode_query([
          {"authenticity_token", RailsCsrf.masked_token(session)},
          {"user[email]", email}
        ])

      {form("POST", "/users/password", cookie, body), body}
    end

    defp digest_of(id),
      do: Repo.query!("SELECT reset_password_token FROM users WHERE id = $1", [id]).rows

    test "recovery on: Phoenix answers the recovery forms; credentials alone leaves them to Puma",
         ctx do
      Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
      assert to_puma(ctx, get("/users/password/new")).line == "GET /users/password/new HTTP/1.1"

      Application.put_env(:dawarich, :phoenix_auth, ["recovery"])
      assert {200, headers, body} = exchange(ctx, get("/users/password/new"))
      assert values(headers, "x-dawarich-auth-owner") == ["native-recovery"]
      assert body =~ ~s(action="/users/password")
      no_puma(ctx)
      assert to_puma(ctx, get("/users/sign_in")).line == "GET /users/sign_in HTTP/1.1"
    end

    test "recovery on with a mail setup: Phoenix writes the digest and one mailers job, Puma never sees the post",
         ctx do
      Application.put_env(:dawarich, :phoenix_auth, ["recovery"])
      mail_setup()
      email = "a11a-#{System.unique_integer([:positive])}@dawarich.test"
      id = user!(%{email: email})
      {request, _body} = recovery_post(email)

      assert {303, headers, ""} = exchange(ctx, request)
      assert values(headers, "x-dawarich-auth-owner") == ["native-recovery"]
      assert values(headers, "location") == ["http://a/users/sign_in"]
      no_puma(ctx)

      assert [[digest]] = digest_of(id)
      assert is_binary(digest)

      assert Repo.query!("SELECT worker, args->>'digest' FROM oban.oban_jobs").rows == [
               ["Dawarich.Auth.Recovery.MailWorker", digest]
             ]
    end

    test "recovery on without a mail setup: the post reaches Puma with its body, nothing written",
         ctx do
      Application.put_env(:dawarich, :phoenix_auth, ["recovery"])
      email = "a11a-#{System.unique_integer([:positive])}@dawarich.test"
      id = user!(%{email: email})
      {request, body} = recovery_post(email)

      seen = to_puma(ctx, request)
      assert seen.body == body
      assert seen.response == {200, ["rails=1; path=/"], [], "puma"}
      assert digest_of(id) == [[nil]]
      assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[0]]
    end

    test "recovery on where Phoenix cannot mail as Rails does (development or unset RAILS_ENV, an SMTP authentication only Rails speaks): the post reaches Puma, nothing written",
         ctx do
      Application.put_env(:dawarich, :phoenix_auth, ["recovery"])
      email = "a11a-#{System.unique_integer([:positive])}@dawarich.test"
      id = user!(%{email: email})

      for {name, value} <- [
            {"RAILS_ENV", nil},
            {"RAILS_ENV", "development"},
            {"SMTP_AUTHENTICATION", "xoauth2"}
          ] do
        mail_setup()
        if value, do: System.put_env(name, value), else: System.delete_env(name)
        {request, body} = recovery_post(email)

        seen = to_puma(ctx, request)
        assert seen.body == body, "#{name}=#{inspect(value)}"
        assert seen.response == {200, ["rails=1; path=/"], [], "puma"}
      end

      assert digest_of(id) == [[nil]]
      assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[0]]
    end

    test "OIDC configured: neither the recovery forms nor the sign-in reach the native flows",
         ctx do
      Application.put_env(:dawarich, :phoenix_auth, ["credentials", "recovery"])
      mail_setup()
      System.put_env("OIDC_CLIENT_ID", "synthetic")
      System.put_env("OIDC_CLIENT_SECRET", "synthetic")

      assert to_puma(ctx, get("/users/password/new")).line == "GET /users/password/new HTTP/1.1"
      assert to_puma(ctx, get("/users/sign_in")).line == "GET /users/sign_in HTTP/1.1"

      {session, cookie} = guest()

      body =
        URI.encode_query([
          {"authenticity_token", RailsCsrf.masked_token(session)},
          {"user[email]", "oidc@dawarich.test"},
          {"user[password]", "synthetic-password"}
        ])

      assert to_puma(ctx, form("POST", "/users/sign_in", cookie, body)).body == body
    end
  end
end

defmodule DawarichWeb.StandaloneCredentialsOtpTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.{Repo, State}
  alias Dawarich.Auth.Account
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint
  @password "safepassword12"
  @otp_secret "JBSWY3DPEHPK3PXP"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    crypto = Jason.decode!(File.read!("test/fixtures/active_record_encryption.json"))
    env = Enum.find(crypto["environments"], &(&1["name"] == "explicit keys"))["env"]

    names =
      Map.keys(env) ++
        ~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL OIDC_CLIENT_ID OIDC_CLIENT_SECRET OIDC_PKCE_ENABLED GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET ALLOW_EMAIL_PASSWORD_LOGIN)

    previous = Map.new(names, &{&1, System.get_env(&1)})
    keys = [:jobs_repo, :phoenix_auth, :rails_routes, :rails_upstream]
    config = Map.new(keys, &{&1, Application.fetch_env(:dawarich, &1)})
    System.put_env(env)
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("FORCE_SSL", "false")
    System.put_env("ALLOW_EMAIL_PASSWORD_LOGIN", "true")

    for name <-
          ~w(OIDC_CLIENT_ID OIDC_CLIENT_SECRET OIDC_PKCE_ENABLED GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET),
        do: System.delete_env(name)

    Application.put_env(:dawarich, :jobs_repo, Repo)
    Application.put_env(:dawarich, :phoenix_auth, ["credentials", "otp"])
    Application.put_env(:dawarich, :rails_routes, [])
    :ok = State.put_registration_enabled(Repo, true)

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end

      for {key, value} <- config do
        case value do
          {:ok, previous} -> Application.put_env(:dawarich, key, previous)
          :error -> Application.delete_env(:dawarich, key)
        end
      end
    end)

    {:ok, encrypted} = Dawarich.Auth.TwoFactor.Secret.encrypt(@otp_secret, env)
    hash = Bcrypt.hash_pwd_salt(@password, log_rounds: 4)
    id = System.unique_integer([:positive])

    user =
      RailsUser.insert!(%{
        id: id,
        email: "standalone-otp-#{id}@dawarich.test",
        encrypted_password: hash,
        otp_required_for_login: true,
        otp_secret: encrypted
      })

    guest = %{"session_id" => Ecto.UUID.generate(), "_csrf_token" => RailsCsrf.new_token()}
    %{user: user, guest: guest}
  end

  @tag :standalone_s1_password
  test "S1 Endpoint accounts for wrong blank normalized and locked OTP passwords", c do
    for mode <- ["true", "false"] do
      System.put_env("SELF_HOSTED", mode)

      Repo.query!("UPDATE users SET failed_attempts=0,locked_at=NULL WHERE id=$1", [c.user.id],
        log: false
      )

      for {email, password, count} <- [
            {c.user.email, "wrong", 2},
            {c.user.email, "", 4},
            {String.upcase(c.user.email), "wrong", 6}
          ] do
        response = password_request(c.guest, email, password)
        assert Repo.get!(Account, c.user.id).failed_attempts == count
        assert response.status == 422
        assert response.resp_body =~ "Invalid email or password"
      end

      Repo.query!("UPDATE users SET failed_attempts=10,locked_at=now() WHERE id=$1", [c.user.id],
        log: false
      )

      for {password, count} <- [{"wrong", 12}, {@password, 14}] do
        response = password_request(c.guest, c.user.email, password)
        assert Repo.get!(Account, c.user.id).failed_attempts == count
        assert response.status == 422
        assert response.resp_body =~ "Invalid email or password"
        refute response.resp_body =~ "otp_attempt"
      end

      guard(c.guest, "/users/sign_in", password_params(c.guest, c.user.email, "wrong"))
      assert Repo.get!(Account, c.user.id).failed_attempts == 14
    end
  end

  @tag :standalone_s1_enrollment
  test "S1 Endpoint renders the same ordinary failure form for OTP ordinary and unknown accounts",
       c do
    ordinary =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "ordinary-#{c.user.id}@dawarich.test",
        encrypted_password: c.user.encrypted_password
      })

    for mode <- ["true", "false"] do
      System.put_env("SELF_HOSTED", mode)

      responses =
        for email <- ["unknown-#{c.user.id}@dawarich.test", ordinary.email, c.user.email] do
          response = password_request(c.guest, email, "wrong")
          assert response.status == 422
          assert response.resp_body =~ "Invalid email or password"
          assert response.resp_body =~ ~s(action="/users/sign_in")
          refute response.resp_body =~ "otp_attempt"
          refute response.resp_body =~ "rails_proxy"

          {response.status, get_resp_header(response, "content-type"),
           get_resp_header(response, "x-dawarich-auth-owner")}
        end

      assert length(Enum.uniq(responses)) == 1
      guard(c.guest, "/users/sign_in", password_params(c.guest, c.user.email, "wrong"))
    end
  end

  @tag :standalone_s1_otp
  test "S1 Endpoint completes proxied OTP in self hosted Cloud OIDC and default modes with admission intact",
       c do
    for {mode, oidc} <- [{"true", false}, {"false", false}, {"false", true}, {nil, false}] do
      if mode, do: System.put_env("SELF_HOSTED", mode), else: System.delete_env("SELF_HOSTED")

      if oidc do
        System.put_env("OIDC_CLIENT_ID", "synthetic-client")
        System.put_env("OIDC_PKCE_ENABLED", "true")
      else
        System.delete_env("OIDC_CLIENT_ID")
        System.delete_env("OIDC_PKCE_ENABLED")
      end

      id = System.unique_integer([:positive])
      user = RailsUser.insert!(%{c.user | id: id, email: "mode-#{id}@dawarich.test"})
      assert Dawarich.Auth.Admission.oidc?() == oidc
      Repo.query!("UPDATE users SET consumed_timestep=NULL WHERE id=$1", [user.id], log: false)
      guest = Map.put(c.guest, "session_id", Ecto.UUID.generate())
      now = DateTime.utc_now()
      pending = Dawarich.Auth.Otp.Pending.start(guest, user.id, nil, DateTime.to_unix(now))
      invalid_params = csrf(%{"otp_attempt" => "invalid-code"}, pending)
      before = Repo.get!(Account, user.id).failed_otp_attempts

      for opts <- [[duplicate_forwarded: true], [duplicate_cookie: true], [bad_csrf: true]] do
        refused = web(pending, "/users/otp_challenge", invalid_params, opts)
        assert refused.status == 422
        refute refused.resp_cookies["_dawarich_session"]
        assert Repo.get!(Account, user.id).failed_otp_attempts == before
        assert Repo.get!(Account, user.id).sign_in_count == 0
      end

      failed = web(pending, "/users/otp_challenge", invalid_params)
      assert failed.status == 422
      assert failed.resp_cookies["_dawarich_session"]
      assert failed.resp_body =~ "otp_attempt"
      assert Repo.get!(Account, user.id).failed_otp_attempts == before + 1
      pending = RailsFormRequests.rails_session(failed)
      code = Dawarich.Auth.TwoFactor.Totp.at(@otp_secret, DateTime.to_unix(now))
      params = csrf(%{"otp_attempt" => code}, pending)
      successful = web(pending, "/users/otp_challenge", params)
      assert successful.status == 302
      signed = RailsFormRequests.rails_session(successful)
      assert [[id], _] = signed["warden.user.user.key"]
      assert id == user.id
      assert signed["session_id"] != pending["session_id"]
      refute signed["otp_user_id"]
      account = Repo.get!(Account, user.id)
      assert account.current_sign_in_ip == proxy_ip()
      assert account.failed_otp_attempts == 0
      assert account.consumed_timestep
      guard(pending, "/users/otp_challenge", params)

      Repo.query!("UPDATE users SET sign_in_count=0 WHERE id=$1", [user.id], log: false)

      started =
        web(guest, "/users/sign_in", password_params(guest, user.email, @password),
          forwarded: true
        )

      assert started.status == 422
      assert started.resp_body =~ "otp_attempt"
      assert RailsFormRequests.rails_session(started)["otp_user_id"] == user.id
    end
  end

  @tag :standalone_s1_otp_completion
  test "S1 Endpoint authenticates a valid proxied OTP directly in self hosted and Cloud modes",
       c do
    for mode <- ["true", "false"] do
      System.put_env("SELF_HOSTED", mode)
      id = System.unique_integer([:positive])
      user = RailsUser.insert!(%{c.user | id: id, email: "completion-#{id}@dawarich.test"})
      guest = Map.put(c.guest, "session_id", Ecto.UUID.generate())
      now = DateTime.to_unix(DateTime.utc_now())
      pending = Dawarich.Auth.Otp.Pending.start(guest, user.id, nil, now)
      code = Dawarich.Auth.TwoFactor.Totp.at(@otp_secret, now)
      params = csrf(%{"otp_attempt" => code}, pending)
      response = web(pending, "/users/otp_challenge", params)

      assert response.status == 302
      assert response.resp_cookies["_dawarich_session"]
      signed = RailsFormRequests.rails_session(response)
      assert [[^id], _] = signed["warden.user.user.key"]
      assert signed["session_id"] != pending["session_id"]
      refute signed["otp_user_id"]
      account = Repo.get!(Account, id)
      assert account.sign_in_count == 1
      assert account.current_sign_in_ip == proxy_ip()
      assert account.consumed_timestep
      guard(pending, "/users/otp_challenge", params)
      assert Repo.get!(Account, id).sign_in_count == 1
    end
  end

  defp password_request(session, email, password),
    do: web(session, "/users/sign_in", password_params(session, email, password))

  defp password_params(session, email, password),
    do: csrf(%{"user[email]" => email, "user[password]" => password}, session)

  defp csrf(params, session),
    do: Map.put(params, "authenticity_token", RailsCsrf.masked_token(session))

  defp web(session, path, params, opts \\ []) do
    params =
      if opts[:bad_csrf], do: Map.put(params, "authenticity_token", "invalid"), else: params

    body = URI.encode_query(params)
    cookie = "_dawarich_session=" <> RailsUser.cookie(session)

    cookie =
      if opts[:duplicate_cookie], do: cookie <> "; _dawarich_session=malformed", else: cookie

    conn =
      %{build_conn() | remote_ip: {10, 18, 2, rem(:erlang.phash2(session["session_id"]), 250)}}
      |> put_req_header("cookie", cookie)
      |> put_req_header("accept", "text/html")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", to_string(byte_size(body)))

    conn =
      if path == "/users/otp_challenge" or opts[:forwarded],
        do: put_req_header(conn, "x-forwarded-for", proxy_ip()),
        else: conn

    conn =
      if opts[:duplicate_forwarded],
        do: %{conn | req_headers: [{"x-forwarded-for", "192.0.2.21"} | conn.req_headers]},
        else: conn

    dispatch(conn, @endpoint, :post, path, body)
  end

  defp proxy_ip do
    cond do
      Dawarich.Auth.Admission.oidc?() -> "192.0.2.22"
      System.get_env("SELF_HOSTED") == "false" -> "192.0.2.21"
      is_nil(System.get_env("SELF_HOSTED")) -> "192.0.2.23"
      true -> "192.0.2.20"
    end
  end

  defp guard(session, path, params) do
    System.delete_env("DAWARICH_RAILS")
    upstream = RailsFormRequests.upstream!()

    {{line, body}, response} =
      RailsFormRequests.forwarded(upstream, fn -> web(session, path, params) end)

    assert response.status == 204
    assert String.starts_with?(line, "POST " <> path <> " ")
    assert body == URI.encode_query(params)
    System.put_env("DAWARICH_RAILS", "off")
  end
end

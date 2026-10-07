defmodule DawarichWeb.ReferralSignupEndpointsTest do
  use Dawarich.JobsCase
  import Plug.Conn
  alias Dawarich.{RailsCookies, RailsSecret}
  alias Dawarich.Jobs.Ownership
  @now ~U[2026-10-07 12:00:00.000000Z]
  @base "http://www.example.com"
  @env %{
    "SELF_HOSTED" => "false",
    "TIME_ZONE" => "Europe/Berlin",
    "MANAGER_URL" => "https://manager.example.invalid",
    "JWT_SECRET_KEY" => "synthetic-l1-registration"
  }

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    previous = Map.new(@env, fn {k, _} -> {k, System.get_env(k)} end)
    System.put_env(@env)

    for type <-
          ~w(users.creation_webhook partnero.customer_signup mail.user.welcome users.explore_features_mail mail.family_lapse),
        do: Ownership.put!(ScratchRepo, "command:" <> type, :oban)

    for spec <- Dawarich.Redis.cache_child_specs(),
        Process.whereis(Dawarich.Redis.Cache) == nil,
        do: start_supervised!(spec)

    on_exit(fn ->
      for {k, v} <- previous, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
    end)

    %{
      context: %{
        repo: ScratchRepo,
        self_hosted: false,
        registration_enabled: true,
        env: @env,
        clock: fn -> @now end,
        log_rounds: 4,
        locale: "en"
      }
    }
  end

  test "R1 browser failure retains referral and success spends it before second-account signup",
       c do
    initial = %{"_csrf_token" => Base.encode64(String.duplicate("x", 32))}

    form =
      request(
        :get,
        "/users/sign_up?" <>
          URI.encode_query(%{"aff" => referral_input(), "via" => "losing-key"}),
        initial
      )
      |> DawarichWeb.AuthRegistration.Http.call(enabled: true, context: c.context)

    assert form.status == 200
    referral_session = session(form)
    assert referral_session["partnero_referral"] == referral_expected()
    assert String.valid?(referral_session["partnero_referral"])

    invalid =
      browser("invalid@example.invalid", referral_session, c.context, %{
        "user[password_confirmation]" => "mismatch"
      })

    assert invalid.status == 422
    retained = session(invalid)
    assert retained["partnero_referral"] == referral_expected()

    assert rows(
             "SELECT count(*) FROM public.job_outbox WHERE command_type='partnero.customer_signup'"
           ) == [[0]]

    result = browser("first@example.invalid", retained, c.context)
    assert result.status == 302
    spent = session(result)

    assert rows(
             "SELECT payload->>'partner_key' FROM public.job_outbox WHERE command_type='partnero.customer_signup'"
           ) == [[referral_expected()]]

    second = browser("second@example.invalid", spent, c.context)
    assert second.status == 302

    assert rows(
             "SELECT count(*) FROM public.job_outbox WHERE command_type='partnero.customer_signup'"
           ) == [[1]]

    refute spent["partnero_referral"]
  end

  test "R1 GitHub consumes browser-captured referral once through default callbacks", c do
    ordinary_oauth(c, "github")
  end

  test "R1 Google consumes browser-captured referral once through default callbacks", c do
    ordinary_oauth(c, "google_oauth2")
  end

  defp ordinary_oauth(c, provider) do
    {private, key} = signing_key()

    ctx = provider_context(c.context, provider, private, key)
    initial = %{"omniauth.state" => "synthetic-state"}

    form =
      request(
        :get,
        "/users/sign_up?" <>
          URI.encode_query(%{"aff" => referral_input(), "via" => "losing-key"}),
        initial
      )
      |> DawarichWeb.AuthRegistration.Http.call(enabled: true, context: c.context)

    assert form.status == 200
    assert session(form)["partnero_referral"] == referral_expected()
    result = provider_request(provider, ctx, private, session(form))
    assert result.status == 302
    spent = session(result)
    refute spent["partnero_referral"]
    [[id]] = rows("SELECT id FROM users WHERE provider=$1", [provider])

    assert rows(
             "SELECT payload->>'partner_key' FROM public.job_outbox WHERE aggregate_id=$1 AND command_type='partnero.customer_signup'",
             [id]
           ) == [[referral_expected()]]

    replay =
      provider_request(
        provider,
        ctx,
        private,
        Map.put(spent, "omniauth.state", "synthetic-state")
      )

    assert replay.status == 302

    assert rows(
             "SELECT count(*) FROM public.job_outbox WHERE aggregate_id=$1 AND command_type='partnero.customer_signup'",
             [id]
           ) == [[1]]
  end

  test "R1 Apple creates a Cloud account and creation intent with no Partnero attribution", c do
    {private, key} = signing_key()
    ctx = provider_context(c.context, "apple", private, key)

    referral_session = %{
      "omniauth.state" => "synthetic-state",
      "partnero_referral" => referral_expected()
    }

    result = provider_request("apple", ctx, private, referral_session)
    assert result.status == 302
    [[id]] = rows("SELECT id FROM users WHERE provider='apple'")

    assert rows(
             "SELECT count(*) FROM public.job_outbox WHERE aggregate_id=$1 AND command_type='users.creation_webhook'",
             [id]
           ) == [[1]]

    assert rows(
             "SELECT count(*) FROM public.job_outbox WHERE aggregate_id=$1 AND command_type='partnero.customer_signup'",
             [id]
           ) == [[0]]
  end

  test "R1 mobile signup ignores decomposed browser and JSON referrals like Rails", c do
    initial = %{"_csrf_token" => Base.encode64(String.duplicate("x", 32))}

    form =
      request(
        :get,
        "/users/sign_up?" <>
          URI.encode_query(%{"aff" => referral_input(), "via" => "losing-key"}),
        initial
      )
      |> DawarichWeb.AuthRegistration.Http.call(enabled: true, context: c.context)

    assert form.status == 200
    assert session(form)["partnero_referral"] == referral_expected()

    body =
      Jason.encode!(%{
        "email" => "mobile@example.invalid",
        "password" => "synthetic-password",
        "password_confirmation" => "synthetic-password",
        "aff" => referral_input(),
        "via" => "losing-key"
      })

    cookie =
      "_dawarich_session=" <>
        RailsCookies.encrypt(session(form), "_dawarich_session", RailsSecret.fetch())

    result =
      Plug.Test.conn(:post, @base <> "/api/v1/auth/register", body)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-length", to_string(byte_size(body)))
      |> put_req_header("cookie", cookie)
      |> DawarichWeb.AuthMobile.Http.call(enabled: true, context: c.context)

    assert result.status == 201
    payload = Jason.decode!(result.resp_body)
    assert payload["status"] == "pending_payment"

    assert rows(
             "SELECT count(*) FROM public.job_outbox WHERE aggregate_id=$1 AND command_type='users.creation_webhook'",
             [payload["user_id"]]
           ) == [[1]]

    assert rows(
             "SELECT count(*) FROM public.job_outbox WHERE command_type='partnero.customer_signup'"
           ) == [[0]]
  end

  defp referral_input, do: String.duplicate("e\u0301", 255)
  defp referral_expected, do: String.duplicate("e\u0301", 127) <> "e"

  defp browser(email, session, ctx, attribution \\ %{}) do
    params = %{
      "user[email]" => email,
      "user[password]" => "synthetic-password",
      "user[password_confirmation]" => "synthetic-password",
      "authenticity_token" => DawarichWeb.RailsCsrf.masked_token(session)
    }

    params = Map.merge(params, attribution)

    request(:post, "/users", session, params)
    |> DawarichWeb.AuthRegistration.Http.call(enabled: true, context: ctx)
  end

  defp request(method, path, session, params \\ %{}) do
    raw = URI.encode_query(params)
    conn = Plug.Test.conn(method, @base <> path, raw)

    conn =
      if method == :get,
        do: conn,
        else:
          conn
          |> put_req_header("content-type", "application/x-www-form-urlencoded")
          |> put_req_header("content-length", to_string(byte_size(raw)))

    conn
    |> put_req_header("origin", @base)
    |> put_req_header(
      "cookie",
      "_dawarich_session=" <>
        RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())
    )
  end

  defp session(conn) do
    {:ok, value} =
      RailsCookies.decrypt(
        conn.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        RailsSecret.fetch(),
        DateTime.utc_now()
      )

    value
  end

  defp signing_key do
    private = :public_key.generate_key({:rsa, 2048, 65537})

    key = %{
      "kty" => "RSA",
      "kid" => "synthetic-l1-key",
      "alg" => "RS256",
      "n" => Base.url_encode64(:binary.encode_unsigned(elem(private, 2)), padding: false),
      "e" => Base.url_encode64(:binary.encode_unsigned(elem(private, 3)), padding: false)
    }

    {private, key}
  end

  defp signed(private, provider) do
    issuer =
      if provider == "apple", do: "https://appleid.apple.com", else: "https://accounts.google.com"

    claims = %{
      "iss" => issuer,
      "aud" => "synthetic-client",
      "exp" => DateTime.to_unix(@now) + 300,
      "iat" => DateTime.to_unix(@now),
      "sub" => provider,
      "email" => provider <> "@example.invalid",
      "email_verified" => true
    }

    claims =
      if provider == "apple",
        do:
          Map.put(
            claims,
            "nonce",
            Base.encode16(:crypto.hash(:sha256, "synthetic-nonce"), case: :lower)
          ),
        else: claims

    input =
      Base.url_encode64(Jason.encode!(%{"alg" => "RS256", "kid" => "synthetic-l1-key"}),
        padding: false
      ) <> "." <> Base.url_encode64(Jason.encode!(claims), padding: false)

    input <> "." <> Base.url_encode64(:public_key.sign(input, :sha256, private), padding: false)
  end

  defp provider_context(ctx, provider, private, key) do
    env =
      Map.merge(ctx.env, %{
        "APPLE_WEB_SERVICES_ID" => "synthetic-client",
        "APPLE_WEB_TEAM_ID" => "synthetic-team",
        "APPLE_WEB_KEY_ID" => "synthetic-key",
        "APPLE_WEB_P8_BASE64" => "synthetic-config",
        "APPLE_WEB_REDIRECT_URI" => @base <> "/users/auth/apple/callback"
      })

    config = %{
      client_id: "synthetic-client",
      client_secret: "synthetic-secret",
      redirect_uri: @base <> "/users/auth/" <> provider <> "/callback",
      token_endpoint: "https://provider.example.invalid/token",
      userinfo_endpoint: "https://provider.example.invalid/user",
      emails_endpoint: "https://provider.example.invalid/emails",
      jwks_uri: "https://#{provider}-#{System.unique_integer([:positive])}.example.invalid/keys"
    }

    http = fn _, url, _, _ ->
      result =
        case URI.parse(url).path do
          "/keys" ->
            %{"keys" => [key]}

          "/token" ->
            %{"access_token" => "synthetic-access", "id_token" => signed(private, provider)}

          "/user" when provider == "github" ->
            %{"id" => 42, "name" => "Ada Lovelace"}

          "/user" ->
            %{
              "sub" => provider,
              "email" => provider <> "@example.invalid",
              "email_verified" => true
            }

          "/emails" ->
            [%{"email" => provider <> "@example.invalid", "primary" => true, "verified" => true}]
        end

      {:ok, result}
    end

    Map.merge(ctx, %{
      env: env,
      http: http,
      jwks_uri: config.jwks_uri,
      providers: %{provider => config}
    })
  end

  defp provider_request("apple", ctx, private, session) do
    conn =
      request(:post, "/users/auth/apple/callback", session, %{
        "state" => "synthetic-state",
        "id_token" => signed(private, "apple")
      })

    cookies =
      for {key, value} <- [
            {"apple_oauth_state", "synthetic-state"},
            {"apple_oauth_nonce", "synthetic-nonce"}
          ],
          do:
            key <>
              "=" <>
              RailsCookies.encrypt(value, key, RailsSecret.fetch(), DateTime.add(@now, 600))

    [existing] = get_req_header(conn, "cookie")

    conn
    |> put_req_header("cookie", Enum.join([existing | cookies], "; "))
    |> DawarichWeb.AuthApple.Http.call(enabled: true, context: ctx)
  end

  defp provider_request(provider, ctx, _private, session) do
    request(
      :get,
      "/users/auth/" <>
        provider <>
        "/callback?" <>
        URI.encode_query(%{"state" => "synthetic-state", "code" => "synthetic-code"}),
      session
    )
    |> DawarichWeb.AuthProvider.Http.call(enabled: true, context: ctx)
  end
end

defmodule DawarichWeb.A12f2HClosureTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Repo, Redis, Test.RailsUser}
  alias Dawarich.Auth.{Account}
  alias Dawarich.Auth.TwoFactor.{Secret, Totp}
  @now ~U[2026-10-06 12:00:00.000000Z]
  @hash Jason.decode!(File.read!("test/fixtures/auth/requests.json"))["login"]["user"][
          "encrypted_password"
        ]
  @crypto Jason.decode!(File.read!("test/fixtures/active_record_encryption.json"))
  @env Enum.find(@crypto["environments"], &(&1["name"] == "explicit keys"))["env"]
  @otp "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
  @oracle Jason.decode!(File.read!("test/fixtures/auth/a12f2h/closure.json"))

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    for spec <- Redis.cache_child_specs(),
        Process.whereis(Dawarich.Redis.Cache) == nil,
        do: start_supervised!(spec)

    jti = Ecto.UUID.generate()
    id = System.unique_integer([:positive]) + 8_000_000
    Redis.cache_command(["DEL", "oauth_account_link:rate_limit:#{id}"])
    {:ok, cipher} = Secret.encrypt(@otp, @env)

    RailsUser.insert!(%{
      id: id,
      email: "h-#{id}@example.invalid",
      encrypted_password: @hash,
      api_key: "synthetic-h-#{id}",
      otp_secret: cipher,
      otp_backup_codes: [@hash],
      subscription_source: 0,
      active_until: nil,
      failed_otp_attempts: 0,
      settings: %{}
    })

    context = %{
      self_hosted: true,
      oidc: false,
      timezone: "Etc/UTC",
      clock: fn -> @now end,
      env: Map.put(@env, "JWT_SECRET_KEY", "synthetic-h-otp-secret"),
      jti: fn -> jti end,
      log_rounds: 4
    }

    on_exit(fn ->
      {:ok, conn} = Redix.start_link(Application.fetch_env!(:dawarich, :redis)[:url], database: 0)

      Redix.command(conn, [
        "DEL",
        "otp_challenge:consumed:" <> jti,
        "oauth_account_link:rate_limit:#{id}",
        "manager_callback:last_seen_ms:#{id}"
      ])

      GenServer.stop(conn)
    end)

    %{id: id, email: "h-#{id}@example.invalid", context: context}
  end

  @tag :a12f2_h_05
  test "Mobile login and OTP retain source invalid credentials lockouts cache JWT consumption and stateless responses",
       c do
    invalid = response("login", %{"email" => c.email, "password" => "wrong"}, c.context)
    assert invalid.status == 401

    assert Jason.decode!(invalid.resp_body) ==
             Enum.find(@oracle, &(&1["name"] == "login-invalid"))["body"]

    assert response(
             "login",
             %{"email" => "absent@example.invalid", "password" => "wrong"},
             c.context
           ).status == 401

    login =
      response(
        "login",
        %{"email" => "  " <> String.upcase(c.email), "password" => "safepassword12"},
        c.context
      )

    assert login.status == 200
    assert Jason.decode!(login.resp_body)["user_id"] == c.id
    assert login.resp_cookies == %{}
    assert Repo.get!(Account, c.id).sign_in_count == 0

    disabled =
      c.context
      |> Map.put(:oidc, true)
      |> Map.put(:env, Map.put(c.context.env, "ALLOW_EMAIL_PASSWORD_LOGIN", "false"))

    assert response("login", %{"email" => c.email, "password" => "safepassword12"}, disabled).status ==
             403

    Repo.get!(Account, c.id)
    |> Ecto.Changeset.change(otp_required_for_login: true)
    |> Repo.update!()

    login = response("login", %{"email" => c.email, "password" => "safepassword12"}, c.context)
    assert login.status == 202
    challenge = Jason.decode!(login.resp_body)
    refute Map.has_key?(challenge, "api_key")
    assert challenge["ttl"] == 300

    assert response(
             "otp_challenge",
             %{"challenge_token" => "invalid", "otp_code" => "012345"},
             c.context
           ).status == 401

    params = %{"challenge_token" => challenge["challenge_token"], "otp_code" => "wrong"}
    assert response("otp_challenge", params, c.context).status == 401
    assert Repo.get!(Account, c.id).failed_otp_attempts == 1
    params = Map.put(params, "otp_code", Totp.at(@otp, DateTime.to_unix(@now)))
    assert response("otp_challenge", params, c.context).status == 200
    assert response("otp_challenge", params, c.context).status == 401
    assert Repo.get!(Account, c.id).failed_otp_attempts == 0
    assert Repo.get!(Account, c.id).sign_in_count == 0
  end

  @tag :a12f2_h_06
  test "Mobile Google Apple exchanges preserve token verification identity linkage account status and source responses",
       c do
    {private, key} = signing_key()

    context =
      Map.merge(c.context, %{
        audiences: ["synthetic-client"],
        client_id: "synthetic-client",
        jwks_uri: "http://localhost/keys/" <> Ecto.UUID.generate(),
        http: fn :get, _, _, _ -> {:ok, %{"keys" => [key]}} end,
        nonce: "synthetic-nonce",
        enqueue_link: fn _ -> :ok end,
        base_url: "http://www.example.com"
      })

    for provider <- ["apple", "google"] do
      blank = response(provider, %{"id_token" => ""}, context)
      assert blank.status == 401

      assert Jason.decode!(blank.resp_body) ==
               Enum.find(@oracle, &(&1["name"] == provider <> "-blank"))["body"]

      assert response(provider, %{"id_token" => "invalid"}, context).status == 401

      issuer =
        if provider == "apple",
          do: "https://appleid.apple.com",
          else: "https://accounts.google.com"

      nonce =
        if provider == "apple",
          do: Base.encode16(:crypto.hash(:sha256, context.nonce), case: :lower),
          else: context.nonce

      claims = %{
        "iss" => issuer,
        "aud" => "synthetic-client",
        "exp" => DateTime.to_unix(@now) + 300,
        "iat" => DateTime.to_unix(@now),
        "sub" => "synthetic-" <> provider <> Integer.to_string(c.id),
        "email" => provider <> c.email,
        "email_verified" => "true",
        "nonce" => nonce
      }

      for changes <- [
            %{"iss" => "wrong"},
            %{"aud" => "wrong"},
            %{"exp" => DateTime.to_unix(@now)},
            %{"nbf" => DateTime.to_unix(@now) + 300},
            %{"nonce" => "wrong"}
          ] do
        assert response(
                 provider,
                 %{
                   "id_token" => signed(private, Map.merge(claims, changes)),
                   "nonce" => context.nonce
                 },
                 context
               ).status == 401
      end

      result =
        response(
          provider,
          %{"id_token" => signed(private, claims), "nonce" => context.nonce},
          context
        )

      assert result.status == 201
      payload = Jason.decode!(result.resp_body)
      assert payload["status"] == "active" and payload["email"] == provider <> c.email
      assert is_binary(payload["api_key"]) and result.resp_cookies == %{}
      assert Repo.get!(Account, payload["user_id"]).sign_in_count == 0
      returning = Map.delete(claims, "email")

      assert response(provider, %{"id_token" => signed(private, returning)}, context).status ==
               200

      collision = Map.merge(claims, %{"sub" => "collision-" <> provider, "email" => c.email})
      result = response(provider, %{"id_token" => signed(private, collision)}, context)
      assert result.status in [202, 429]
      refute Map.has_key?(Jason.decode!(result.resp_body), "api_key")

      cloud =
        Map.merge(context, %{
          self_hosted: false,
          callbacks: %{
            webhook: fn id ->
              send(self(), {:webhook, id})
              :ok
            end
          }
        })

      cloud_claims =
        Map.merge(claims, %{
          "sub" => "cloud-" <> provider <> Integer.to_string(c.id),
          "email" => "cloud-" <> provider <> c.email
        })

      cloud_response = response(provider, %{"id_token" => signed(private, cloud_claims)}, cloud)
      assert cloud_response.status == 201
      cloud_user = Jason.decode!(cloud_response.resp_body)["user_id"]
      assert Jason.decode!(cloud_response.resp_body)["status"] == "pending_payment"

      receive do
        {:webhook, ^cloud_user} -> :ok
      after
        0 -> flunk("Cloud provider signup omitted webhook")
      end

      unverified = Map.put(collision, "email_verified", false)

      assert response(provider, %{"id_token" => signed(private, unverified)}, context).status ==
               403
    end
  end

  @tag :a12f2_h_04
  test "Mobile registration preserves registration policy invitations pending payment status source errors and callbacks",
       c do
    params = %{
      "email" => "new-" <> c.email,
      "password" => "safepassword12",
      "password_confirmation" => "safepassword12"
    }

    enabled = Map.put(c.context, :registration_enabled, true)

    assert response("register", params, Map.put(enabled, :registration_enabled, false)).status ==
             403

    assert response("register", Map.put(params, "password", "short"), enabled).status == 422
    result = response("register", params, enabled)
    assert result.status == 201
    assert Jason.decode!(result.resp_body)["status"] == "active"
    assert result.resp_cookies == %{}
    cloud = Map.merge(enabled, %{self_hosted: false, callbacks: %{webhook: fn _ -> :ok end}})
    result = response("register", Map.put(params, "email", "cloud-" <> c.email), cloud)
    assert result.status == 201
    payload = Jason.decode!(result.resp_body)
    assert payload["status"] == "pending_payment"
    assert Repo.get!(Account, payload["user_id"]).sign_in_count == 0
  end

  @tag :a12f2_h_02
  test "Apple initiation retains enabled configuration nonce state expiry cookie flags and cross site ticket bridge",
       c do
    context = apple_context(c.context)

    conn =
      Plug.Test.conn(:get, "/users/auth/apple")
      |> assign(:rails_session, %{"pending_import_ticket" => "synthetic-ticket"})

    response = apple(conn, context)
    assert response.status == 302
    [location] = get_resp_header(response, "location")
    query = URI.decode_query(URI.parse(location).query)
    assert query["client_id"] == "synthetic-client" and query["response_mode"] == "form_post"
    assert query["scope"] == "name email" and query["response_type"] == "code id_token"

    for key <- ~w(apple_oauth_nonce apple_oauth_state apple_pending_import_ticket) do
      cookie = response.resp_cookies[key]
      assert cookie.same_site == "None" and cookie.secure and cookie.http_only
      assert cookie.max_age == 600

      assert {:ok, _} =
               Dawarich.RailsCookies.decrypt(
                 cookie.value,
                 key,
                 Dawarich.RailsSecret.fetch(),
                 @now
               )

      assert :error ==
               Dawarich.RailsCookies.decrypt(
                 cookie.value,
                 key,
                 Dawarich.RailsSecret.fetch(),
                 DateTime.add(@now, 601)
               )
    end

    nonce = response.resp_cookies["apple_oauth_nonce"].value

    {:ok, raw} =
      Dawarich.RailsCookies.decrypt(
        nonce,
        "apple_oauth_nonce",
        Dawarich.RailsSecret.fetch(),
        @now
      )

    assert query["nonce"] == Base.encode16(:crypto.hash(:sha256, raw), case: :lower)
    assert apple(conn, Map.put(context, :env, %{})).status == 404
  end

  @tag :a12f2_h_03
  test "Apple callback retains JWKS issuer audiences nonce hash state one time name email and source errors",
       c do
    {private, key} = signing_key()

    context =
      apple_context(c.context)
      |> Map.merge(%{
        jwks_uri: "http://localhost/keys/" <> Ecto.UUID.generate(),
        http: fn :get, _, _, _ -> {:ok, %{"keys" => [key]}} end,
        callbacks: %{webhook: fn _ -> :ok end},
        ip: "127.0.0.1"
      })

    claims = %{
      "iss" => "https://appleid.apple.com",
      "aud" => "synthetic-client",
      "exp" => DateTime.to_unix(@now) + 300,
      "iat" => DateTime.to_unix(@now),
      "sub" => "web-#{c.id}",
      "email" => "web-" <> c.email,
      "email_verified" => true,
      "nonce" => Base.encode16(:crypto.hash(:sha256, "synthetic-nonce"), case: :lower)
    }

    params = %{
      "id_token" => signed(private, Map.put(claims, "nonce", "wrong")),
      "state" => "synthetic-state"
    }

    response = apple_callback(params, context)
    assert response.status == 302
    assert get_resp_header(response, "location") == ["http://www.example.com/users/sign_in"]
    refute Repo.get_by(Account, uid: claims["sub"])
    response = apple_callback(Map.put(params, "state", "wrong"), context)
    assert get_resp_header(response, "location") == ["http://www.example.com/users/sign_in"]
    params = Map.put(params, "id_token", signed(private, claims))
    response = apple_callback(params, context)
    assert response.status == 302
    user = Repo.get_by!(Account, uid: claims["sub"])
    assert user.sign_in_count == 1
    assert response.resp_cookies["apple_oauth_state"].max_age == 0
    assert response.resp_cookies["apple_oauth_nonce"].max_age == 0

    clean =
      Plug.Test.conn(:post, "/users/auth/apple/callback", URI.encode_query(params))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")

    response = apple(clean, context)
    assert get_resp_header(response, "location") == ["http://www.example.com/users/sign_in"]
    assert Repo.get!(Account, user.id).sign_in_count == 1
  end

  defp apple_context(context),
    do:
      Map.merge(context, %{
        self_hosted: false,
        env:
          Map.merge(context.env, %{
            "APPLE_WEB_SERVICES_ID" => "synthetic-client",
            "APPLE_WEB_TEAM_ID" => "synthetic-team",
            "APPLE_WEB_KEY_ID" => "synthetic-key",
            "APPLE_WEB_P8_BASE64" => "synthetic-config",
            "APPLE_WEB_REDIRECT_URI" => "http://www.example.com/users/auth/apple/callback"
          })
      })

  defp apple(conn, context) do
    module = DawarichWeb.AuthApple.Http

    if Code.ensure_loaded?(module),
      do: apply(module, :call, [conn, [enabled: true, context: context]]),
      else: conn
  end

  defp apple_callback(params, context) do
    conn =
      Plug.Test.conn(:post, "/users/auth/apple/callback", URI.encode_query(params))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")

    conn =
      Enum.reduce(
        [{"apple_oauth_nonce", "synthetic-nonce"}, {"apple_oauth_state", "synthetic-state"}],
        conn,
        fn {key, value}, conn ->
          Phoenix.ConnTest.put_req_cookie(
            conn,
            key,
            Dawarich.RailsCookies.encrypt(
              value,
              key,
              Dawarich.RailsSecret.fetch(),
              DateTime.add(@now, 600)
            )
          )
        end
      )

    apple(conn, context)
  end

  @tag :a12f2_h_07
  test "Mobile handoff preserves secret family five minute token marker redirect priorities and source success responses",
       c do
    context =
      Map.put(
        c.context,
        :env,
        Map.merge(c.context.env, %{"AUTH_JWT_SECRET_KEY" => "synthetic-h-mobile-secret"})
      )

    module = Dawarich.Auth.Mobile.Handoff

    result =
      if Code.ensure_loaded?(module),
        do: apply(module, :redirect, [Repo.get!(Account, c.id), "android", context]),
        else: :unimplemented

    assert {:ok, path} = result
    assert String.starts_with?(path, "/auth/ios/success?")
    token = URI.decode_query(URI.parse(path).query)["token"]
    assert {:ok, claims} = hs_claims(token, "synthetic-h-mobile-secret")
    assert claims == %{"api_key" => "synthetic-h-#{c.id}", "exp" => DateTime.to_unix(@now) + 300}
    assert :invalid == hs_claims(token, "synthetic-h-otp-secret")
    conn = Plug.Test.conn(:get, "/auth/ios/success?token=" <> token)
    response = DawarichWeb.AuthMobile.Success.call(conn, context: context)

    assert response.status == 200 and
             response.resp_body == "Authentication successful! You can close this window."

    response =
      DawarichWeb.AuthMobile.Success.call(Plug.Test.conn(:get, "/auth/ios/success"),
        context: context
      )

    assert Jason.decode!(response.resp_body)["redirect_url"] == "http://www.example.com/"
  end

  @tag :a12f2_h_08
  test "Subscription callback retains secret JWT event NX watermark locking retry and source errors",
       c do
    context =
      Map.put(
        c.context,
        :env,
        Map.put(c.context.env, "SUBSCRIPTION_WEBHOOK_SECRET", "synthetic-h-webhook")
      )

    claims = %{
      "user_id" => c.id,
      "event_id" => Ecto.UUID.generate(),
      "event_timestamp_ms" => 1_790_000_000_000,
      "exp" => DateTime.to_unix(@now) + 300,
      "status" => "inactive",
      "active_until" => nil,
      "plan" => "lite"
    }

    assert subscription(claims, context, "wrong").status == 401
    assert subscription(Map.delete(claims, "event_id"), context).status == 422
    assert subscription(claims, Map.put(context, :env, %{})).status == 503
    rollback = Map.put(context, :before_update, fn -> raise("synthetic-rollback") end)
    assert subscription(claims, rollback).status == 503
    assert Repo.get!(Account, c.id).status == 1
    assert subscription(claims, context).status == 200
    assert Repo.get!(Account, c.id).status == 0
    assert Jason.decode!(subscription(claims, context).resp_body)["message"] == "Stale event"

    older =
      Map.merge(claims, %{
        "event_id" => Ecto.UUID.generate(),
        "event_timestamp_ms" => 1_789_999_999_999,
        "status" => "active"
      })

    assert Jason.decode!(subscription(older, context).resp_body)["message"] == "Stale event"
    equal = Map.merge(claims, %{"event_id" => Ecto.UUID.generate(), "status" => "active"})
    assert subscription(equal, context).status == 200
    assert Repo.get!(Account, c.id).status == 1

    zero =
      Map.merge(claims, %{
        "event_id" => Ecto.UUID.generate(),
        "event_timestamp_ms" => 0,
        "plan" => "unknown"
      })

    assert subscription(zero, context).status == 200
    assert Repo.get!(Account, c.id).plan == 0
    assert subscription(Map.put(claims, "event_id", nil), context).status == 422
    assert subscription(Map.put(claims, "exp", DateTime.to_unix(@now)), context).status == 401
  end

  @tag :a12f2_h_09
  test "Mobile and callback tokens cross Rails and native consumers while accepted provider effects never replay",
       c do
    path = Path.join(System.tmp_dir!(), "h-protocol-#{Ecto.UUID.generate()}.json")
    database = Repo.config()[:database]

    env = [
      {"MIX_ENV", "test"},
      {"PHOENIX_TEST_DATABASE", database},
      {"DATABASE_HOST", "127.0.0.1"},
      {"ASDF_ERLANG_VERSION", "27.3.4.1"},
      {"ASDF_ELIXIR_VERSION", "1.18.3-otp-27"},
      {"PATH", Path.join(System.user_home!(), ".asdf/shims") <> ":" <> System.get_env("PATH")}
    ]

    try do
      {output, status} =
        System.cmd(
          "mix",
          ["run", "--no-start", "test/support/auth/emit_protocol.exs", path, "api_auth"],
          env: env,
          stderr_to_stdout: true
        )

      assert status == 0, "protocol emitter failed: " <> output
      payload = Jason.decode!(File.read!(path))
      assert payload["database"] == database
      root = Path.expand("..")
      swagger = Path.join(root, "swagger/v1/swagger.yaml")
      original = File.read!(swagger)

      try do
        command =
          "true && asdf exec bundle exec rails runner app-phoenix/test/support/auth/consume_protocol.rb " <>
            path <> " api_auth"

        {output, status} =
          System.cmd("zsh", ["-c", command],
            cd: root,
            env:
              env ++
                [
                  {"RAILS_ENV", "test"},
                  {"SECRET_KEY_BASE", "phoenix-a2-cookie-fixture-secret-not-for-production"},
                  {"DATABASE_NAME", database},
                  {"REDIS_URL",
                   URI.to_string(%{
                     URI.parse(System.fetch_env!("PHOENIX_TEST_REDIS_URL"))
                     | path: nil
                   })}
                ],
            stderr_to_stdout: true
          )

        assert status == 0, "protocol Rails consumer failed: " <> output
      after
        File.write!(swagger, original)
      end

      {output, status} =
        System.cmd(
          "mix",
          ["run", "--no-start", "test/support/auth/emit_protocol.exs", path, "api_auth_source"],
          env: env,
          stderr_to_stdout: true
        )

      assert status == 0, "protocol native consumer failed: " <> output
      payload = Jason.decode!(File.read!(path))
      assert payload["rails"]["mobile"]

      context =
        Map.put(
          c.context,
          :env,
          Map.put(c.context.env, "SUBSCRIPTION_WEBHOOK_SECRET", "synthetic-h-webhook")
        )

      claims = %{
        "user_id" => c.id,
        "event_id" => Ecto.UUID.generate(),
        "exp" => DateTime.to_unix(@now) + 300,
        "status" => "inactive",
        "active_until" => nil
      }

      context = Map.put(context, :after_commit, fn -> raise("synthetic-render-failure") end)

      result =
        Dawarich.Subscriptions.Callback.call(
          hs_token(claims, context.env["JWT_SECRET_KEY"]),
          "synthetic-h-webhook",
          context
        )

      refute result == :rails
      assert result == {:error, 503, %{"error" => "subscription_response_unavailable"}}
      assert Repo.get!(Account, c.id).status == 0

      assert Jason.decode!(subscription(claims, Map.delete(context, :after_commit)).resp_body)[
               "message"
             ] == "Stale event"
    after
      File.rm(path)
    end
  end

  defp subscription(claims, context, secret \\ "synthetic-h-webhook") do
    body =
      Jason.encode!(%{
        "token" => hs_token(claims, context.env["JWT_SECRET_KEY"] || "synthetic-h-otp-secret")
      })

    conn =
      Plug.Test.conn(:post, "/api/v1/subscriptions/callback", body)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-webhook-secret", secret)

    module = DawarichWeb.Api.SubscriptionsController

    if Code.ensure_loaded?(module),
      do: apply(module, :call, [conn, [context: context]]),
      else: conn
  end

  defp hs_token(claims, secret) do
    input =
      Base.url_encode64(Jason.encode!(%{"alg" => "HS256"}), padding: false) <>
        "." <> Base.url_encode64(Jason.encode!(claims), padding: false)

    input <> "." <> Base.url_encode64(:crypto.mac(:hmac, :sha256, secret, input), padding: false)
  end

  defp hs_claims(token, secret) do
    [h, p, s] = String.split(token, ".")

    if Base.url_decode64!(s, padding: false) ==
         :crypto.mac(:hmac, :sha256, secret, h <> "." <> p),
       do: {:ok, p |> Base.url_decode64!(padding: false) |> Jason.decode!()},
       else: :invalid
  end

  defp signing_key do
    private = :public_key.generate_key({:rsa, 2048, 65537})
    {:RSAPrivateKey, _, n, e, _, _, _, _, _, _, _} = private

    encode = fn value ->
      value |> :binary.encode_unsigned() |> Base.url_encode64(padding: false)
    end

    {private,
     %{
       "kty" => "RSA",
       "kid" => "synthetic-h",
       "alg" => "RS256",
       "n" => encode.(n),
       "e" => encode.(e)
     }}
  end

  defp signed(private, claims) do
    encode = fn data -> Base.url_encode64(data, padding: false) end

    input =
      encode.(Jason.encode!(%{"alg" => "RS256", "kid" => "synthetic-h"})) <>
        "." <> encode.(Jason.encode!(claims))

    input <> "." <> encode.(:public_key.sign(input, :sha256, private))
  end

  defp response(action, params, context) do
    body = Jason.encode!(params)

    Plug.Test.conn(:post, "/api/v1/auth/" <> action, body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("x-dawarich-client", "ios")
    |> DawarichWeb.AuthApi.Http.call(
      enabled: true,
      standalone: true,
      context: context,
      fallback: fn _ -> flunk("mobile auth reached Rails") end
    )
  end
end

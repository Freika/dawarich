defmodule DawarichWeb.CloudRegistrationEndpointsTest do
  use Dawarich.JobsCase
  import Plug.Conn
  import Dawarich.AnomalyCase
  alias Dawarich.{RailsCookies, RailsSecret}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Auth.Providers.Accounts
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

  test "L1 default browser Cloud signup commits account and real Manager intent before checkout",
       c do
    session = %{
      "_csrf_token" => Base.encode64(String.duplicate("x", 32)),
      "partnero_referral" => "synthetic-partner"
    }

    invalid =
      browser("invalid@example.invalid", session, c.context, %{
        "user[password_confirmation]" => "mismatch"
      })

    assert invalid.status == 422
    assert session(invalid)["partnero_referral"] == "synthetic-partner"

    result =
      browser("browser@example.invalid", session, c.context, %{
        "aff" => String.duplicate("é", 255),
        "via" => "loser"
      })

    assert result.status == 302
    [location] = get_resp_header(result, "location")
    assert String.starts_with?(location, @env["MANAGER_URL"] <> "/checkout?token=")
    token = URI.decode_query(URI.parse(location).query)["token"]
    [_h, p, _s] = String.split(token, ".")
    assert Jason.decode!(Base.url_decode64!(p, padding: false))["variant"] == "reverse_trial"

    [[id, status, variant, key_size]] =
      rows(
        "SELECT id,status,signup_variant,length(api_key) FROM users WHERE email='browser@example.invalid'"
      )

    assert status == 3 and variant == "reverse_trial" and key_size == 64

    assert rows(
             "SELECT command_type FROM job_outbox WHERE aggregate_id=$1 ORDER BY command_type",
             [id]
           ) == [["partnero.customer_signup"], ["users.creation_webhook"]]

    [[partner]] =
      rows(
        "SELECT payload->>'partner_key' FROM job_outbox WHERE command_type='partnero.customer_signup'"
      )

    assert length(String.codepoints(partner)) == 255

    assert partner ==
             String.duplicate("é", 255) |> String.codepoints() |> Enum.take(255) |> Enum.join()

    clean = session(result)
    refute clean["warden.user.user.key"]
    refute clean["partnero_referral"]
    second = browser("second@example.invalid", clean, c.context)
    assert second.status == 302

    assert rows("SELECT count(*) FROM job_outbox WHERE command_type='partnero.customer_signup'") ==
             [[1]]

    Ownership.put!(ScratchRepo, "command:users.creation_webhook", :sidekiq)
    rejected = browser("rejected@example.invalid", session, c.context)
    assert rejected.status == 503
    assert rows("SELECT count(*) FROM users WHERE email='rejected@example.invalid'") == [[0]]
    refute rejected.resp_cookies["_dawarich_session"]
  end

  test "L1 mobile Cloud signup and matching invitation preserve Rails state and callback counts",
       c do
    pending = mobile("mobile@example.invalid", nil, c.context)
    assert pending.status == 201
    payload = Jason.decode!(pending.resp_body)
    assert payload["status"] == "pending_payment"
    owner = user!()
    rows("UPDATE users SET plan=2,status=1,active_until='2027-01-01' WHERE id=$1", [owner])

    [[family]] =
      rows(
        "INSERT INTO families(creator_id,name,access_until,created_at,updated_at) VALUES($1,'Synthetic family','2027-01-01',now(),now()) RETURNING id",
        [owner]
      )

    rows(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,0,now(),now())",
      [family, owner]
    )

    rows(
      "INSERT INTO family_invitations(family_id,email,token,status,invited_by_id,expires_at,created_at,updated_at) VALUES($1,'invitee@example.invalid','synthetic-invitation',0,$2,'2026-11-01',now(),now())",
      [family, owner]
    )

    matched = mobile("INVITEE@EXAMPLE.INVALID", "synthetic-invitation", c.context)
    assert matched.status == 201
    member = Jason.decode!(matched.resp_body)
    assert member["status"] == "active"

    assert rows("SELECT family_id FROM family_memberships WHERE user_id=$1", [member["user_id"]]) ==
             [[family]]

    rows(
      "INSERT INTO family_invitations(family_id,email,token,status,invited_by_id,expires_at,created_at,updated_at) VALUES($1,'someone@example.invalid','synthetic-mismatch',0,$2,'2026-11-01',now(),now())",
      [family, owner]
    )

    mismatch = mobile("other@example.invalid", "synthetic-mismatch", c.context)
    assert mismatch.status == 201
    other = Jason.decode!(mismatch.resp_body)
    assert other["status"] == "pending_payment"

    assert rows("SELECT count(*) FROM family_memberships WHERE user_id=$1", [other["user_id"]]) ==
             [[0]]

    assert rows("SELECT count(*) FROM job_outbox WHERE command_type='users.creation_webhook'") ==
             [[3]]

    assert rows(
             "SELECT count(*) FROM job_outbox WHERE command_type IN ('mail.user.welcome','users.explore_features_mail')"
           ) == [[0]]
  end

  test "L1 Apple GitHub and Google new accounts publish once while existing and linked accounts publish nothing",
       c do
    {private, key} = signing_key()

    for provider <- ["github", "google_oauth2", "apple"] do
      ctx = provider_context(c.context, provider, private, key)

      session = %{
        "omniauth.state" => "synthetic-state",
        "partnero_referral" => "synthetic-partner"
      }

      for _ <- 1..2 do
        result = provider_request(provider, ctx, private, session)
        assert result.status == 302
        [location] = get_resp_header(result, "location")
        assert location == @base <> "/trial/resume"
      end

      [[id, status]] = rows("SELECT id,status FROM users WHERE provider=$1", [provider])
      assert status == 3

      assert rows(
               "SELECT count(*) FROM job_outbox WHERE aggregate_id=$1 AND command_type='users.creation_webhook'",
               [id]
             ) == [[1]]

      assert rows(
               "SELECT count(*) FROM job_outbox WHERE aggregate_id=$1 AND command_type='partnero.customer_signup'",
               [id]
             ) == [[if(provider == "apple", do: 0, else: 1)]]
    end

    assert rows(
             "SELECT count(*) FROM phoenix.processed_commands WHERE handler='users.creation_effects'"
           ) == [[3]]

    parent = self()

    identity = %{
      provider: "github",
      uid: "race",
      email: "race@example.invalid",
      email_verified: true,
      first_name: nil,
      last_name: nil
    }

    context =
      Map.put(c.context, :before_insert, fn ->
        send(parent, {:ready, self()})

        receive do
          :go -> :ok
        end
      end)

    tasks = for _ <- 1..2, do: Task.async(fn -> Accounts.resolve(identity, context) end)

    pids =
      for _ <- tasks do
        assert_receive {:ready, pid}
        pid
      end

    Enum.each(pids, &send(&1, :go))
    results = Enum.map(tasks, &Task.await(&1))
    assert Enum.count(results, fn {:ok, _, created} -> created end) == 1
    [[id]] = rows("SELECT id FROM users WHERE email='race@example.invalid'")
    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]) == [[1]]

    assert {:link_required, _} =
             Accounts.resolve(
               %{identity | uid: "different"},
               Map.put(c.context, :on_email_collision, :raise_only)
             )

    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]) == [[1]]

    oidc =
      request(:get, "/users/auth/openid_connect", %{})
      |> DawarichWeb.AuthProvider.Http.call(enabled: true, context: c.context)

    assert oidc.status == 404
  end

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

  defp mobile(email, invitation, ctx) do
    body =
      Jason.encode!(%{
        "email" => email,
        "password" => "synthetic-password",
        "password_confirmation" => "synthetic-password",
        "invitation_token" => invitation
      })

    Plug.Test.conn(:post, @base <> "/api/v1/auth/register", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> DawarichWeb.AuthMobile.Http.call(enabled: true, context: ctx)
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
      jwks_uri: "https://provider.example.invalid/keys"
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

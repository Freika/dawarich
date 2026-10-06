defmodule DawarichWeb.A12f2GClosureTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Repo, RailsCookies, RailsSecret}
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Providers.{Github, Google, Oidc, OidcAccounts, Accounts, State}

  @base "http://www.example.com"
  @hash Jason.decode!(File.read!("test/fixtures/auth/requests.json"))["user_before"][
          "encrypted_password"
        ]
  @oracle Jason.decode!(File.read!("test/fixtures/auth/a12f2g/providers.json"))

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    previous = Application.fetch_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Repo)

    on_exit(fn ->
      case previous do
        {:ok, repo} -> Application.put_env(:dawarich, :jobs_repo, repo)
        :error -> Application.delete_env(:dawarich, :jobs_repo)
      end
    end)

    if is_nil(Process.whereis(Dawarich.Redis.Cache)) do
      [spec] = Dawarich.Redis.cache_child_specs()
      start_supervised!(spec)
    end

    %{email: "a12g-#{System.unique_integer([:positive])}@dawarich.test"}
  end

  @tag :a12f2_g_02
  test "GitHub initiation and callback retain configured policy state scopes email selection exchange and source refusals" do
    parent = self()

    base =
      server(fn method, path, body, headers ->
        send(parent, {:github_request, method, path})

        case path do
          "/token" ->
            assert URI.decode_query(body)["code"] == "synthetic-code"
            assert URI.decode_query(body)["client_id"] == "synthetic-client"
            %{"access_token" => "synthetic-access"}

          "/user" ->
            assert headers =~ "Bearer synthetic-access"
            %{"id" => 42, "name" => "Ada Lovelace", "email" => "wrong@dawarich.test"}

          "/emails" ->
            [
              %{"email" => "unverified@dawarich.test", "primary" => true, "verified" => false},
              %{"email" => "secondary@dawarich.test", "primary" => false, "verified" => true},
              %{"email" => "primary@dawarich.test", "primary" => true, "verified" => true}
            ]
        end
      end)

    config = github_config(base)

    assert {:ok, url, session} =
             Github.authorize(config, %{"pending_import_ticket" => "synthetic-ticket"})

    query = URI.decode_query(URI.parse(url).query)
    assert query["scope"] == "user:email" and query["response_type"] == "code"
    assert byte_size(query["state"]) >= 32
    assert session["pending_import_ticket"] == "synthetic-ticket"
    assert {:error, :csrf_detected, clean} = State.take(session, %{"state" => "wrong"})
    refute Map.has_key?(clean, "omniauth.state")
    assert {:ok, pending, clean} = State.take(session, %{"state" => query["state"]})
    assert {:ok, identity} = Github.callback(config, %{"code" => "synthetic-code"}, pending, %{})
    assert identity.provider == "github" and identity.uid == "42"
    assert identity.email == "primary@dawarich.test" and identity.email_verified
    assert identity.first_name == "Ada" and identity.last_name == "Lovelace"
    assert {:error, :csrf_detected, _} = State.take(clean, %{"state" => query["state"]})
    for path <- ["/token", "/user", "/emails"], do: assert_receive({:github_request, _, ^path})

    assert {:error, :access_denied} =
             Github.callback(config, %{"error" => "access_denied"}, pending, %{})

    refute_receive {:github_request, _, _}
  end

  @tag :a12f2_g_03
  test "Google web OAuth retains state nonce issuer audience claims discovery key rotation and source failures" do
    {private, key} = signing_key("one")
    {private2, key2} = signing_key("two")
    {:ok, keys} = Agent.start_link(fn -> [key] end)
    parent = self()

    base =
      server(fn _, path, _, _ ->
        send(parent, {:google_request, path})

        case path do
          "/keys" ->
            %{"keys" => Agent.get(keys, & &1)}

          "/token" ->
            %{
              "access_token" => "synthetic-access",
              "id_token" => signed(private, "one", claims("https://accounts.google.com"))
            }

          "/userinfo" ->
            claims("https://accounts.google.com")
        end
      end)

    context = %{
      jwks_uri: base <> "/keys",
      audiences: ["synthetic-client"],
      nonce: "synthetic-nonce"
    }

    claims = claims("https://accounts.google.com") |> Map.put("nonce", "synthetic-nonce")
    token = signed(private, "one", claims)
    assert {:ok, result} = Google.verify_id_token(token, context)
    assert result["sub"] == "subject"
    assert {:ok, _} = Google.verify_id_token(token, Map.delete(context, :nonce))

    for changes <- [
          %{"aud" => "wrong-client"},
          %{"iss" => "https://wrong.dawarich.test"},
          %{"exp" => 1},
          %{"nonce" => "wrong"}
        ] do
      assert {:error, _} =
               Google.verify_id_token(signed(private, "one", Map.merge(claims, changes)), context)
    end

    assert {:error, _} = Google.verify_id_token(token <> "corrupt", context)
    assert {:error, _} = Google.verify_id_token(unsigned(claims), context)

    config = %{
      client_id: "synthetic-client",
      client_secret: "synthetic-client-secret",
      authorization_endpoint: base <> "/authorize",
      token_endpoint: base <> "/token",
      userinfo_endpoint: base <> "/userinfo",
      jwks_uri: base <> "/keys",
      redirect_uri: @base <> "/users/auth/google_oauth2/callback"
    }

    assert {:ok, url, session} = Google.authorize(config, %{})
    query = URI.decode_query(URI.parse(url).query)
    assert query["scope"] == @oracle["google_scope"] and query["access_type"] == "offline"
    refute query["nonce"]
    assert {:ok, pending, _} = State.take(session, %{"state" => query["state"]})
    assert {:ok, profile} = Google.callback(config, %{"code" => "synthetic-code"}, pending, %{})
    assert profile.email_verified and profile.provider == "google_oauth2"

    refute Google.identity(%{
             "sub" => "subject",
             "email" => "synthetic@dawarich.test",
             "email_verified" => "true"
           }).email_verified

    assert_receive {:google_request, "/token"}
    Agent.update(keys, fn _ -> [key2] end)
    assert {:ok, _} = Google.verify_id_token(signed(private2, "two", claims), context)
    assert_receive {:google_request, "/keys"}
    assert_receive {:google_request, "/keys"}
    refute_receive {:google_request, _}
    Agent.stop(keys)
  end

  @tag :a12f2_g_04
  test "OIDC initiation preserves issuer discovery response type scopes PKCE and source configuration refusal" do
    parent = self()
    {private, key} = signing_key("oidc")
    {:ok, holder} = Agent.start_link(fn -> %{} end)

    base =
      server(fn method, path, body, headers ->
        config = Agent.get(holder, & &1)

        case path do
          "/.well-known/openid-configuration" ->
            assert method == "GET"

            %{
              "issuer" => config.base,
              "authorization_endpoint" => config.base <> "/authorize",
              "token_endpoint" => config.base <> "/token",
              "userinfo_endpoint" => config.base <> "/userinfo",
              "jwks_uri" => config.base <> "/keys"
            }

          "/token" ->
            params = URI.decode_query(body)
            assert params["code_verifier"] == config.verifier
            refute Map.has_key?(params, "client_secret")
            refute String.downcase(headers) =~ "authorization: basic"
            send(parent, {:oidc_exchange, params})

            %{
              "access_token" => "synthetic-access",
              "id_token" =>
                signed(private, "oidc", claims(config.base) |> Map.put("nonce", config.nonce))
            }

          "/keys" ->
            %{"keys" => [key]}

          "/userinfo" ->
            %{"sub" => "subject", "email" => "oidc@dawarich.test", "email_verified" => true}
        end
      end)

    Agent.update(holder, fn _ -> %{base: base} end)

    env = %{
      "OIDC_CLIENT_ID" => "synthetic-client",
      "OIDC_PKCE_ENABLED" => " true ",
      "OIDC_ISSUER" => base <> "/.well-known/openid-configuration#paste",
      "APPLICATION_URL" => @base
    }

    assert {:ok, config} = Oidc.configuration(env, %{})
    assert config.issuer == base and config.client_auth_method == :none
    assert {:ok, url, session} = Oidc.authorize(config, %{})
    query = URI.decode_query(URI.parse(url).query)
    assert query["scope"] == "openid email profile" and query["response_type"] == "code"
    assert query["code_challenge_method"] == "S256"
    verifier = session["omniauth.pkce.verifier"]

    assert query["code_challenge"] ==
             Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

    Agent.update(holder, &Map.merge(&1, %{verifier: verifier, nonce: query["nonce"]}))
    assert {:ok, pending, _} = State.take(session, %{"state" => query["state"]})
    assert {:ok, identity} = Oidc.callback(config, %{"code" => "synthetic-code"}, pending, %{})
    assert identity.provider == "openid_connect" and identity.email_verified
    assert_receive {:oidc_exchange, params}
    assert params["redirect_uri"] == @base <> "/users/auth/openid_connect/callback"

    opts = [
      enabled: true,
      context: %{env: env, self_hosted: true, auto_register: true, log_rounds: 4},
      fallback: &replay/1
    ]

    start =
      DawarichWeb.AuthProvider.Http.call(request(:post, "/users/auth/openid_connect", %{}), opts)

    assert start.status == 302
    started = response_session(start)

    Agent.update(
      holder,
      &Map.merge(&1, %{
        verifier: started["omniauth.pkce.verifier"],
        nonce: started["omniauth.nonce"]
      })
    )

    callback =
      DawarichWeb.AuthProvider.Http.call(
        request(:get, "/users/auth/openid_connect/callback", started, %{
          "code" => "synthetic-code",
          "state" => started["omniauth.state"]
        }),
        opts
      )

    assert callback.status == 302 and callback.halted
    assert get_resp_header(callback, "location") == [@base <> "/"]
    assert [[id], _] = response_session(callback)["warden.user.user.key"]
    assert Repo.get!(Account, id).provider == "openid_connect"
    assert_receive {:oidc_exchange, _}
    assert {:error, :configuration} = Oidc.configuration(%{}, %{})
    Agent.stop(holder)
  end

  @tag :a12f2_g_05
  test "OIDC callbacks preserve signed identity claims auto register policy existing accounts and source error redirects",
       ctx do
    identity = identity("openid_connect", ctx.email, "oidc-sub")
    assert {:ok, nil, false} = OidcAccounts.resolve(identity, %{auto_register: false})
    refute Repo.get_by(Account, email: ctx.email)

    for flag <- ["false", "False", "0", "1", "yes"] do
      assert {:ok, nil, false} =
               OidcAccounts.resolve(identity, %{
                 env: %{"OIDC_AUTO_REGISTER" => flag},
                 log_rounds: 4
               })
    end

    assert {:ok, user, true} =
             OidcAccounts.resolve(identity, %{auto_register: true, log_rounds: 4})

    assert user.provider == "openid_connect" and user.uid == "oidc-sub"

    assert [[nil]] =
             Repo.query!("SELECT signup_variant FROM users WHERE id=$1", [user.id], log: false).rows

    assert {:ok, returning, false} =
             OidcAccounts.resolve(%{identity | email: nil}, %{auto_register: false})

    assert returning.id == user.id
    Repo.update!(Ecto.Changeset.change(user, deleted_at: DateTime.utc_now()), log: false)
    assert {:error, :pending_deletion} = OidcAccounts.resolve(identity, %{auto_register: false})

    for provider <- ~w(github google_oauth2 openid_connect) do
      assert @oracle["accounts"][provider]["registration_disabled"]["outcome"] == "denied"
      assert @oracle["accounts"][provider]["returning"]["created"] == false
    end
  end

  @tag :a12f2_g_06
  test "Provider accounts preserve identity uniqueness email collisions verification throttles deletion and source race outcomes",
       ctx do
    local = user(ctx.email)
    ident = identity("github", String.upcase(ctx.email), "new-sub")

    assert {:link_required, required} =
             Accounts.resolve(ident, %{on_email_collision: :raise_only})

    assert required.user.id == local.id
    refute Repo.get!(Account, local.id).provider
    assert {:error, :unverified_email} = Accounts.resolve(%{ident | email_verified: false}, %{})
    parent = self()

    context = %{
      on_email_collision: :send_email,
      base_url: @base,
      enqueue_link: fn payload ->
        send(parent, {:mail, payload})
        :ok
      end
    }

    assert {:link_required, sent} = Accounts.resolve(ident, context)
    refute sent.rate_limited
    assert_receive {:mail, payload}
    assert payload["user_id"] == local.id and payload["provider_label"] == "GitHub"
    assert {:link_required, throttled} = Accounts.resolve(ident, context)
    assert throttled.rate_limited and throttled.retry_after in 1..3600
    refute_receive {:mail, _}

    assert {:ok, missing, true} =
             Accounts.resolve(identity("github", nil, "missing-#{local.id}"), %{log_rounds: 4})

    assert missing.email == "missing-#{local.id}@github.dawarich.app"
    assert {:error, :missing_email} = Accounts.resolve(identity("apple", nil, "apple-sub"), %{})
    Repo.update!(Ecto.Changeset.change(local, deleted_at: DateTime.utc_now()), log: false)
    assert {:error, :pending_deletion} = Accounts.resolve(ident, context)
    race_email = "race-" <> ctx.email
    race = identity("google_oauth2", race_email, race_email)

    gate = fn ->
      send(parent, {:ready, self()})

      receive do
        :insert -> :ok
      end
    end

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
            Accounts.resolve(race, %{log_rounds: 4, before_insert: gate})
          end)
        end)
      end

    assert_receive {:ready, first}, 5000
    assert_receive {:ready, second}, 5000
    send(first, :insert)
    send(second, :insert)
    results = Enum.map(tasks, &Task.await(&1, 10000))
    assert Enum.all?(results, &match?({:ok, _, _}, &1))
    assert Enum.map(results, fn {:ok, u, _} -> u.id end) |> Enum.uniq() |> length() == 1
    assert Enum.sort(Enum.map(results, fn {:ok, _, created} -> created end)) == [false, true]

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      Repo.query!("DELETE FROM users WHERE email=$1", [race_email], log: false)
    end)
  end

  @tag :a12f2_g_07
  test "Account link email fallback challenge confirmation preserve token session Cloud provider and consumption failures",
       ctx do
    closure = Dawarich.Auth.AccountLink.Closure
    local = user(ctx.email)
    context = %{ip: "127.0.0.1"}
    assert {:ok, token} = closure.issue(local.id, "github", "linked-sub", context)
    assert {:ok, result} = closure.confirm(token, %{}, context)
    assert result.user.provider == "github" and result.kind == :sign_in
    assert {:error, :replayed} = closure.confirm(token, %{}, context)
    assert {:error, :invalid_token} = closure.confirm(token <> "bad", %{}, context)

    pending = %{
      "pending_oauth_link" => %{
        "user_id" => local.id,
        "provider" => "google_oauth2",
        "uid" => "other-sub",
        "expires_at" => System.os_time(:second) + 900
      }
    }

    assert {:ok, _} = closure.pending(pending, %{self_hosted: false})
    assert {:error, :incorrect_password, failed} = closure.password(pending, "wrong", context)
    assert failed["pending_oauth_link_attempts"] == 1

    assert {:error, :too_many_attempts, cleared} =
             closure.password(
               Map.put(pending, "pending_oauth_link_attempts", 4),
               "wrong",
               context
             )

    refute cleared["pending_oauth_link"]
    Repo.update!(Ecto.Changeset.change(local, otp_required_for_login: true), log: false)
    assert {:ok, linked} = closure.password(pending, "safepassword12", context)
    assert linked.kind == :link_only and linked.user.provider == "google_oauth2"
    assert {:ok, link_token} = closure.issue(local.id, "github", "third", context)
    assert {:error, :different_identity} = closure.confirm(link_token, %{}, context)
    conn = request(:get, "/auth/account_link", %{}, %{"token" => token})

    response =
      DawarichWeb.AuthAccountLink.Http.call(conn,
        enabled: true,
        context: context,
        closure: true,
        fallback: &replay/1
      )

    assert response.status == 302 and response.halted
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert get_resp_header(response, "location") == [@base <> "/users/sign_in"]
    refute response.private[:replayed]
    options = [enabled: true, closure: true, context: context, fallback: &replay/1]

    challenge =
      DawarichWeb.AuthAccountLink.Http.call(
        request(:get, "/auth/account_link/challenge", pending),
        options
      )

    assert challenge.status == 200 and challenge.resp_body =~ "Google"

    wrong =
      DawarichWeb.AuthAccountLink.Http.call(
        request(:post, "/auth/account_link/challenge", pending, %{"password" => "wrong"}),
        options
      )

    assert wrong.status == 422 and get_resp_header(wrong, "cache-control") == ["no-store"]
    assert response_session(wrong)["pending_oauth_link_attempts"] == 1

    correct =
      DawarichWeb.AuthAccountLink.Http.call(
        request(:post, "/auth/account_link/challenge", pending, %{"password" => "safepassword12"}),
        options
      )

    assert correct.status == 302
    assert get_resp_header(correct, "location") == [@base <> "/users/sign_in"]
    refute response_session(correct)["warden.user.user.key"]
    parent = self()

    mail_options =
      Keyword.put(
        options,
        :context,
        Map.put(context, :enqueue_link, fn payload ->
          send(parent, {:fallback_mail, payload})
          :ok
        end)
      )

    mail =
      DawarichWeb.AuthAccountLink.Http.call(
        request(:post, "/auth/account_link/email", pending),
        mail_options
      )

    assert mail.status == 302 and get_resp_header(mail, "pragma") == ["no-cache"]
    assert_receive {:fallback_mail, payload}
    assert payload["provider_label"] == "Google"

    limited =
      DawarichWeb.AuthAccountLink.Http.call(
        request(:post, "/auth/account_link/email", pending),
        mail_options
      )

    assert limited.status == 302
    refute_receive {:fallback_mail, _}
    current = Repo.get!(Account, local.id)

    Repo.update!(
      Ecto.Changeset.change(current, otp_required_for_login: false, locked_at: DateTime.utc_now()),
      log: false
    )

    assert {:ok, locked_token} = closure.issue(local.id, "google_oauth2", "other-sub", context)
    assert {:error, :locked} = closure.confirm(locked_token, %{}, context)
    assert {:error, :replayed} = closure.confirm(locked_token, %{}, context)
  end

  @tag :a12f2_g_08
  test "Provider completion preserves ticket invitation OTP mobile payment priorities and terminal side effects",
       ctx do
    for {flag, expected} <- [{nil, 404}, {"true", 404}, {"yes", 404}, {"false", 302}, {"0", 302}] do
      env = %{
        "GITHUB_OAUTH_CLIENT_ID" => "synthetic-client",
        "GITHUB_OAUTH_CLIENT_SECRET" => "synthetic-client-secret"
      }

      env = if flag, do: Map.put(env, "SELF_HOSTED", flag), else: env

      initiated =
        DawarichWeb.AuthProvider.Http.call(request(:post, "/users/auth/github", %{}),
          enabled: true,
          context: %{env: env}
        )

      assert initiated.status == expected
    end

    parent = self()
    {:ok, profile} = Agent.start_link(fn -> %{id: 42, email: ctx.email} end)

    base =
      server(fn _, path, _, _ ->
        send(parent, {:exchange, path})

        case path do
          "/token" ->
            %{"access_token" => "synthetic-access"}

          "/user" ->
            %{"id" => Agent.get(profile, & &1.id), "name" => "Ada Lovelace"}

          "/emails" ->
            [%{"email" => Agent.get(profile, & &1.email), "primary" => true, "verified" => true}]
        end
      end)

    local = user(ctx.email)

    Repo.update!(
      Ecto.Changeset.change(local,
        provider: "github",
        uid: "42",
        otp_required_for_login: true,
        failed_attempts: 3
      ),
      log: false
    )

    options = [
      enabled: true,
      context: %{
        providers: %{"github" => github_config(base)},
        self_hosted: false,
        ip: "127.0.0.1",
        mobile_redirect: fn _, _ -> {:ok, "/mobile-success"} end
      },
      fallback: &replay/1
    ]

    start = DawarichWeb.AuthProvider.Http.call(request(:post, "/users/auth/github", %{}), options)
    assert start.status == 302
    pending = response_session(start)
    params = %{"state" => pending["omniauth.state"], "code" => "synthetic-code"}

    callback =
      DawarichWeb.AuthProvider.Http.call(
        request(:get, "/users/auth/github/callback", pending, params),
        options
      )

    assert callback.status == 302 and callback.halted
    assert get_resp_header(callback, "location") == [@base <> "/"]
    assert [[id], _] = response_session(callback)["warden.user.user.key"]
    assert id == local.id
    assert Repo.get!(Account, id).sign_in_count == 1
    assert Repo.get!(Account, id).failed_attempts == 0
    refute callback.private[:replayed]
    for path <- ["/token", "/user", "/emails"], do: assert_receive({:exchange, ^path})
    overflow = Map.merge(pending, %{"huge" => String.duplicate("x", 10000)})

    failed =
      DawarichWeb.AuthProvider.Http.call(
        request(:get, "/users/auth/github/callback", overflow, params),
        options
      )

    assert failed.status == 503 and failed.halted
    for path <- ["/token", "/user", "/emails"], do: assert_receive({:exchange, ^path})
    refute_receive {:exchange, _}
    signup_email = "signup-" <> ctx.email
    Agent.update(profile, fn _ -> %{id: 43, email: signup_email} end)

    new_context =
      Keyword.fetch!(options, :context)
      |> Map.put(:log_rounds, 4)
      |> Map.put(:callbacks, %{
        webhook: fn id ->
          send(parent, {:webhook, id})
          :ok
        end,
        partnero: fn id, referral ->
          send(parent, {:partnero, id, referral})
          :ok
        end
      })

    signup_options = Keyword.put(options, :context, new_context)

    signup =
      DawarichWeb.AuthProvider.Http.call(
        request(:post, "/users/auth/github", %{}, %{
          "aff" => "synthetic-partner",
          "utm_source" => "synthetic-campaign"
        }),
        signup_options
      )

    signup_session = response_session(signup)

    signed_up =
      DawarichWeb.AuthProvider.Http.call(
        request(:get, "/users/auth/github/callback", signup_session, %{
          "state" => signup_session["omniauth.state"],
          "code" => "synthetic-code"
        }),
        signup_options
      )

    assert signed_up.status == 302
    assert get_resp_header(signed_up, "location") == [@base <> "/trial/resume"]
    created = Repo.get_by!(Account, email: signup_email)
    assert created.status == 3
    assert_receive {:webhook, created_id}
    assert created_id == created.id
    assert_receive {:partnero, ^created_id, "synthetic-partner"}

    assert [["synthetic-campaign"]] =
             Repo.query!("SELECT utm_source FROM users WHERE id=$1", [created_id], log: false).rows

    for path <- ["/token", "/user", "/emails"], do: assert_receive({:exchange, ^path})
    refute_receive {:webhook, _}
    Agent.stop(profile)
    completion = Dawarich.Auth.Providers.Completion

    context = %{
      self_hosted: false,
      ip: "127.0.0.1",
      mobile_redirect: fn _, _ -> {:ok, "/mobile-success"} end
    }

    payment = Repo.update!(Ecto.Changeset.change(local, status: 3), log: false)
    conn = request(:get, "/", %{"dawarich_client" => "ios"})
    conn = assign(conn, :rails_session, %{"dawarich_client" => "ios"})
    result = completion.complete(conn, payment, false, "github", context)
    assert get_resp_header(result, "location") == [@base <> "/trial/resume"]
    Repo.update!(Ecto.Changeset.change(payment, status: 1), log: false)
    unsafe = assign(conn, :rails_session, %{"user_return_to" => "//attacker.test"})

    result =
      completion.complete(
        unsafe,
        %{payment | status: 1},
        false,
        "github",
        Map.delete(context, :mobile_redirect)
      )

    assert get_resp_header(result, "location") == [@base <> "/"]

    locked =
      Repo.update!(Ecto.Changeset.change(payment, status: 1, locked_at: DateTime.utc_now()),
        log: false
      )

    refused =
      completion.complete(assign(conn, :rails_session, %{}), locked, false, "github", context)

    assert get_resp_header(refused, "location") == [@base <> "/users/sign_in"]
    refute response_session(refused)["warden.user.user.key"]
  end

  @tag :a12f2_g_09
  test "OAuth failures retain source root sign in status flashes cancellation config errors and safe diagnostics" do
    handler = Dawarich.Auth.Providers.Failure

    for reason <- [:invalid_credentials, :timeout, :csrf_detected, :discovery, :issuer_mismatch] do
      conn = request(:get, "/users/auth/failure", %{}) |> assign(:rails_session, %{})
      result = handler.respond(conn, reason, "openid_connect", %{})
      assert result.status == 302 and result.halted
      assert get_resp_header(result, "location") == [@base <> "/"]

      key =
        %{
          invalid_credentials: "invalid_credentials",
          timeout: "connection_timeout",
          csrf_detected: "security_error",
          discovery: "provider_unavailable",
          issuer_mismatch: "provider_configuration_error"
        }[reason]

      assert response_session(result)["flash"]["flashes"]["alert"] ==
               @oracle["failure_messages"][key]

      refute result.resp_body =~ "synthetic-access"
    end

    conn = request(:get, "/users/auth/failure", %{}) |> assign(:rails_session, %{})
    result = handler.respond(conn, :unverified_email, "github", %{})
    assert get_resp_header(result, "location") == [@base <> "/users/sign_in"]
    assert response_session(result)["flash"]["flashes"]["alert"] =~ "is not verified"
  end

  @tag :a12f2_g_r1
  test "G-R1 rejected Google callback ID tokens never create link or sign in accounts", ctx do
    {private, key} = signing_key("callback-refusal")
    parent = self()
    existing = user(ctx.email)

    Repo.update!(Ecto.Changeset.change(existing, provider: "google_oauth2", uid: "returning"),
      log: false
    )

    collision = user("collision-" <> ctx.email)

    config =
      google_config(
        "https://callback-refusal-#{System.unique_integer([:positive])}.dawarich.test"
      )

    before_count = Repo.aggregate(Account, :count)

    for {email, subject} <- [
          {ctx.email, "returning"},
          {collision.email, "collision"},
          {"new-" <> ctx.email, "new"}
        ],
        invalid <- [:audience, :expiry, :issuer, :nonce, :signature, :malformed] do
      valid =
        claims("https://accounts.google.com")
        |> Map.merge(%{"email" => email, "sub" => subject, "nonce" => "expected"})

      changes =
        case invalid do
          :audience -> %{"aud" => "wrong-client"}
          :expiry -> %{"exp" => 1}
          :issuer -> %{"iss" => "https://wrong.dawarich.test"}
          :nonce -> %{"nonce" => "wrong"}
          _ -> %{}
        end

      token = signed(private, "callback-refusal", Map.merge(valid, changes))

      token =
        case invalid do
          :signature -> token <> "corrupt"
          :malformed -> "malformed"
          _ -> token
        end

      context = %{
        self_hosted: true,
        providers: %{"google_oauth2" => config},
        http: fn _, url, _, _ ->
          cond do
            url == config.token_endpoint ->
              {:ok, %{"access_token" => "synthetic-access", "id_token" => token}}

            url == config.jwks_uri ->
              {:ok, %{"keys" => [key]}}

            url == config.userinfo_endpoint ->
              send(parent, :userinfo_fallback)
              {:ok, valid}
          end
        end
      }

      session = %{"omniauth.state" => "synthetic-state", "omniauth.nonce" => "expected"}

      result =
        DawarichWeb.AuthProvider.Http.call(
          request(:get, "/users/auth/google_oauth2/callback", session, %{
            "code" => "synthetic-code",
            "state" => "synthetic-state"
          }),
          enabled: true,
          context: context,
          fallback: &replay/1
        )

      assert result.status == 302 and result.halted
      refute response_session(result)["warden.user.user.key"]
      refute response_session(result)["pending_oauth_link"]
      refute response_session(result)["omniauth.state"]

      assert response_session(result)["flash"]["flashes"]["alert"] ==
               @oracle["failure_messages"]["invalid_credentials"]

      assert get_resp_header(result, "location") == [@base <> "/"]
      refute result.private[:replayed]
      assert Repo.aggregate(Account, :count) == before_count
      assert Repo.get!(Account, existing.id).sign_in_count == existing.sign_in_count
      assert Repo.get!(Account, collision.id).provider == nil
      refute_receive :userinfo_fallback
    end

    for absent <- [nil, ""] do
      context = %{
        http: fn _, url, _, _ ->
          if url == config.token_endpoint,
            do: {:ok, %{"access_token" => "synthetic-access", "id_token" => absent}},
            else: {:ok, claims("https://accounts.google.com")}
        end
      }

      assert {:ok, _} =
               Google.callback(config, %{"code" => "synthetic-code"}, %{nonce: nil}, context)
    end
  end

  @tag :a12f2_g_r2
  test "G-R2 Google rejects future not-before claims with retained sixty second leeway" do
    {private, key} = signing_key("not-before")
    now = DateTime.from_unix!(1_800_000_000)

    config =
      google_config("https://not-before-#{System.unique_integer([:positive])}.dawarich.test")

    context = %{
      jwks_uri: config.jwks_uri,
      audiences: [config.client_id],
      clock: fn -> now end,
      http: fn _, _, _, _ -> {:ok, %{"keys" => [key]}} end
    }

    valid = claims("https://accounts.google.com") |> Map.put("exp", DateTime.to_unix(now) + 7200)

    for offset <- [3600, 61] do
      token = signed(private, "not-before", Map.put(valid, "nbf", DateTime.to_unix(now) + offset))
      assert {:error, :invalid_credentials} = Google.verify_id_token(token, context)
    end

    for offset <- [-1, 0, 60] do
      token = signed(private, "not-before", Map.put(valid, "nbf", DateTime.to_unix(now) + offset))
      assert {:ok, _} = Google.verify_id_token(token, context)
    end

    assert {:ok, _} = Google.verify_id_token(signed(private, "not-before", valid), context)
  end

  @tag :a12f2_g_r3
  test "G-R3 callback mobile headers and client parameters preserve precedence and payment priority",
       ctx do
    local = user(ctx.email)
    Repo.update!(Ecto.Changeset.change(local, provider: "github", uid: "42"), log: false)
    parent = self()

    context = %{
      self_hosted: true,
      mobile_redirect: fn _, client ->
        send(parent, {:mobile_completion, client})
        {:ok, "/mobile-success"}
      end
    }

    conn =
      request(:get, "/users/auth/github/callback", %{})
      |> put_req_header("x-dawarich-client", "ios")
      |> assign(:rails_session, %{})

    result = Dawarich.Auth.Providers.Completion.complete(conn, local, false, "github", context)
    assert get_resp_header(result, "location") == [@base <> "/mobile-success"]
    assert_receive {:mobile_completion, "ios"}
    assert response_session(result)["dawarich_client"] == "ios"
    config = github_config("https://mobile.dawarich.test")

    context =
      Map.merge(context, %{
        providers: %{"github" => config},
        http: fn _, url, _, _ ->
          cond do
            url == config.token_endpoint ->
              {:ok, %{"access_token" => "synthetic-access"}}

            url == config.userinfo_endpoint ->
              {:ok, %{"id" => 42, "name" => "Ada Lovelace"}}

            url == config.emails_endpoint ->
              {:ok, [%{"email" => ctx.email, "primary" => true, "verified" => true}]}
          end
        end
      })

    options = [enabled: true, context: context, fallback: &replay/1]

    for {header, param, stored, expected} <- [
          {"ios", "android", "android", "ios"},
          {nil, "android", nil, "android"},
          {nil, nil, "ios", "ios"},
          {"browser", "android", "ios", nil},
          {nil, "browser", nil, nil}
        ] do
      session = %{"omniauth.state" => "synthetic-state"}
      session = if stored, do: Map.put(session, "dawarich_client", stored), else: session
      params = %{"state" => "synthetic-state", "code" => "synthetic-code"}
      params = if param, do: Map.put(params, "client", param), else: params
      conn = request(:get, "/users/auth/github/callback", session, params)
      conn = if header, do: put_req_header(conn, "x-dawarich-client", header), else: conn
      result = DawarichWeb.AuthProvider.Http.call(conn, options)
      assert result.status == 302

      if expected do
        assert get_resp_header(result, "location") == [@base <> "/mobile-success"]
        assert_receive {:mobile_completion, ^expected}
        assert response_session(result)["dawarich_client"] == expected
      else
        assert get_resp_header(result, "location") == [@base <> "/"]
        refute_receive {:mobile_completion, _}
      end
    end

    start =
      DawarichWeb.AuthProvider.Http.call(
        request(:post, "/users/auth/github", %{}, %{"client" => "android"}),
        options
      )

    assert response_session(start)["dawarich_client"] == "android"
    payment = Repo.update!(Ecto.Changeset.change(local, status: 3), log: false)
    result = Dawarich.Auth.Providers.Completion.complete(conn, payment, false, "github", context)
    assert get_resp_header(result, "location") == [@base <> "/trial/resume"]
    refute_receive {:mobile_completion, _}

    [[family_id]] =
      Repo.query!(
        "INSERT INTO families(creator_id,name,created_at,updated_at) VALUES($1,'Synthetic family',now(),now()) RETURNING id",
        [local.id],
        log: false
      ).rows

    invitation = "synthetic-mobile-invitation-#{local.id}"

    Repo.query!(
      "INSERT INTO family_invitations(family_id,invited_by_id,email,token,expires_at,created_at,updated_at) VALUES($1,$2,$3,$4,now()+interval '1 hour',now(),now())",
      [family_id, local.id, local.email, invitation],
      log: false
    )

    invited = assign(conn, :rails_session, %{"invitation_token" => invitation})

    result =
      Dawarich.Auth.Providers.Completion.complete(invited, payment, false, "github", context)

    assert get_resp_header(result, "location") == [@base <> "/family/invitations/" <> invitation]
    refute_receive {:mobile_completion, _}
  end

  @tag :a12f2_g_r4
  test "G-R4 default Cloud Google authorization scopes match the retained Rails strategy" do
    context = %{
      self_hosted: false,
      env: %{
        "GOOGLE_OAUTH_CLIENT_ID" => "synthetic-client",
        "GOOGLE_OAUTH_CLIENT_SECRET" => "synthetic-client-secret"
      }
    }

    result =
      DawarichWeb.AuthProvider.Http.call(request(:post, "/users/auth/google_oauth2", %{}),
        enabled: true,
        context: context
      )

    assert result.status == 302
    [location] = get_resp_header(result, "location")
    query = URI.decode_query(URI.parse(location).query)
    assert query["scope"] == @oracle["google_scope"]

    assert query["scope"] ==
             "https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile"

    refute "openid" in String.split(query["scope"])
  end

  defp google_config(base),
    do: %{
      client_id: "synthetic-client",
      client_secret: "synthetic-client-secret",
      authorization_endpoint: base <> "/authorize",
      token_endpoint: base <> "/token",
      userinfo_endpoint: base <> "/userinfo",
      jwks_uri: base <> "/keys",
      redirect_uri: @base <> "/users/auth/google_oauth2/callback"
    }

  defp request(method, path, session, params \\ %{}) do
    session =
      if method == :post,
        do: elem(Dawarich.Auth.SessionCookie.for_form(session, RailsSecret.fetch()), 0),
        else: session

    raw = URI.encode_query(params)

    conn =
      if method == :post do
        Plug.Test.conn(method, @base <> path, raw)
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> put_req_header("content-length", to_string(byte_size(raw)))
      else
        Plug.Test.conn(method, @base <> path <> if(raw == "", do: "", else: "?" <> raw))
      end

    cookie = RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())
    conn = put_req_header(conn, "cookie", "_dawarich_session=" <> cookie)

    if method == :post do
      token = DawarichWeb.RailsCsrf.masked_form_token(session, path, "POST")
      put_req_header(conn, "x-csrf-token", token)
    else
      conn
    end
  end

  defp response_session(conn) do
    cookie = conn.resp_cookies["_dawarich_session"].value

    {:ok, session} =
      RailsCookies.decrypt(cookie, "_dawarich_session", RailsSecret.fetch(), DateTime.utc_now())

    session
  end

  defp replay(conn), do: put_private(conn, :replayed, true) |> send_resp(299, "")

  defp identity(provider, email, uid),
    do: %{
      provider: provider,
      uid: uid,
      email: email,
      email_verified: true,
      first_name: "Ada",
      last_name: "Lovelace"
    }

  defp user(email) do
    [[id]] =
      Repo.query!(
        "INSERT INTO users(email,encrypted_password,api_key,status,plan,settings,created_at,updated_at) VALUES($1,$2,$3,1,1,'{}',now(),now()) RETURNING id",
        [email, @hash, Ecto.UUID.generate()],
        log: false
      ).rows

    Repo.get!(Account, id)
  end

  defp github_config(base),
    do: %{
      client_id: "synthetic-client",
      client_secret: "synthetic-client-secret",
      authorization_endpoint: base <> "/authorize",
      token_endpoint: base <> "/token",
      userinfo_endpoint: base <> "/user",
      emails_endpoint: base <> "/emails",
      redirect_uri: @base <> "/users/auth/github/callback",
      scope: "user:email"
    }

  defp claims(issuer),
    do: %{
      "iss" => issuer,
      "aud" => "synthetic-client",
      "sub" => "subject",
      "exp" => System.os_time(:second) + 300,
      "iat" => System.os_time(:second),
      "email" => "oidc@dawarich.test",
      "email_verified" => true
    }

  defp signing_key(kid) do
    private = :public_key.generate_key({:rsa, 2048, 65537})
    {:RSAPrivateKey, _, n, e, _, _, _, _, _, _, _} = private

    {private,
     %{
       "kty" => "RSA",
       "kid" => kid,
       "alg" => "RS256",
       "use" => "sig",
       "n" => Base.url_encode64(:binary.encode_unsigned(n), padding: false),
       "e" => Base.url_encode64(:binary.encode_unsigned(e), padding: false)
     }}
  end

  defp signed(private, kid, claims) do
    input = encode(%{"alg" => "RS256", "kid" => kid}) <> "." <> encode(claims)
    input <> "." <> Base.url_encode64(:public_key.sign(input, :sha256, private), padding: false)
  end

  defp unsigned(claims), do: encode(%{"alg" => "none"}) <> "." <> encode(claims) <> "."
  defp encode(value), do: Jason.encode!(value) |> Base.url_encode64(padding: false)

  defp server(handler) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, {_, port}} = :inet.sockname(listener)
    pid = spawn_link(fn -> accept(listener, handler) end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    "http://127.0.0.1:#{port}"
  end

  defp accept(listener, handler) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        raw = read_headers(socket, "")
        [headers, body] = String.split(raw, "\r\n\r\n", parts: 2)
        [method, target, _] = headers |> String.split("\r\n") |> hd() |> String.split(" ")

        length =
          case Regex.run(~r/content-length:\s*(\d+)/i, headers) do
            [_, n] -> String.to_integer(n)
            _ -> 0
          end

        body = read_payload(socket, body, length)
        response = handler.(method, URI.parse(target).path, body, headers) |> Jason.encode!()

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: #{byte_size(response)}\r\n\r\n" <>
              response
          )

        :gen_tcp.close(socket)
        accept(listener, handler)

      {:error, :closed} ->
        :ok
    end
  end

  defp read_headers(socket, raw) do
    if String.contains?(raw, "\r\n\r\n"),
      do: raw,
      else:
        (
          {:ok, bytes} = :gen_tcp.recv(socket, 0, 5000)
          read_headers(socket, raw <> bytes)
        )
  end

  defp read_payload(_, raw, length) when byte_size(raw) >= length, do: raw

  defp read_payload(socket, raw, length) do
    {:ok, bytes} = :gen_tcp.recv(socket, length - byte_size(raw), 5000)
    raw <> bytes
  end
end

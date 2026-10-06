defmodule DawarichWeb.StandaloneActivationTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Auth.{Account, Recovery.Token, RegistrationSetting}
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    if is_nil(Process.whereis(Dawarich.Redis.Cache)) do
      [spec] = Dawarich.Redis.cache_child_specs()
      start_supervised!(spec)
    end

    names = ~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL)
    previous = Map.new(names, &{&1, System.get_env(&1)})

    keys = [
      :jobs_repo,
      :phoenix_auth,
      :rails_routes,
      :rails_upstream,
      :provider_auth_context,
      :recovery_context
    ]

    config = Map.new(keys, &{&1, Application.fetch_env(:dawarich, &1)})
    Application.put_env(:dawarich, :jobs_repo, Repo)
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    System.put_env("FORCE_SSL", "false")
    Application.put_env(:dawarich, :phoenix_auth, [])
    Application.put_env(:dawarich, :rails_routes, [])
    :ok = Dawarich.State.put_registration_enabled(Repo, true)

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

    user =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "activation@dawarich.test",
        api_key: "activation-synthetic-key",
        settings: %{"timezone" => "UTC"}
      })

    %{
      user: user,
      guest: %{"session_id" => Ecto.UUID.generate(), "_csrf_token" => RailsCsrf.new_token()}
    }
  end

  @tag :activation_registration
  test "standalone registration reaches native forms and creation with policy CSRF and rotated sessions",
       c do
    form = request(:get, "/users/sign_up", c.guest)
    assert form.status == 200
    assert get_resp_header(form, "x-dawarich-auth-owner") == ["native-registration"]

    params = %{
      "user[email]" => "new-activation@dawarich.test",
      "user[password]" => "synthetic-password12",
      "user[password_confirmation]" => "synthetic-password12"
    }

    invalid = request(:post, "/users", c.guest, params)
    assert invalid.status == 422
    refute Repo.get_by(Account, email: params["user[email]"])
    created = request(:post, "/users", c.guest, signed(params, c.guest))
    assert created.status == 303
    session = RailsFormRequests.rails_session(created)
    assert session["session_id"] != c.guest["session_id"]
    assert [[id], _] = session["warden.user.user.key"]
    assert Repo.get!(Account, id).email == params["user[email]"]
    assert Map.has_key?(created.private, :dawarich_rate_limit)
    :ok = RegistrationSetting.put(false)
    assert request(:get, "/users/sign_up", c.guest).status == 302

    assert request(
             :post,
             "/users",
             c.guest,
             signed(Map.put(params, "user[email]", "denied@dawarich.test"), c.guest)
           ).status == 302

    refute Repo.get_by(Account, email: "denied@dawarich.test")

    override =
      request(:post, "/users", c.guest, Map.put(signed(params, c.guest), "_method", "patch"))

    refute get_resp_header(override, "x-dawarich-auth-owner") == ["native-registration"]
    assert override.status == 422
    guard([{:get, "/users/sign_up", %{}}, {:post, "/users", signed(params, c.guest)}], c.guest)
  end

  @tag :activation_recovery
  test "standalone recovery request edit and both updates select native closure and rotate login",
       c do
    Application.put_env(:dawarich, :recovery_context, %{log_rounds: 4})

    for path <- ["/users/password/new", "/users/password/edit?reset_password_token=synthetic"] do
      page = request(:get, path, c.guest)
      assert page.status == 200
      assert page.resp_body =~ ~s(href="/users/sign_up")
    end

    sent =
      request(
        :post,
        "/users/password",
        c.guest,
        signed(%{"user[email]" => c.user.email}, c.guest)
      )

    assert sent.status == 303
    assert Map.has_key?(sent.private, :dawarich_rate_limit) == true
    assert get_resp_header(sent, "x-dawarich-auth-owner") == ["native-recovery"]
    assert Repo.get!(Account, c.user.id).reset_password_token != nil

    assert Repo.query!("SELECT count(*) FROM oban.oban_jobs", [], log: false).rows |> hd() |> hd() >
             0

    invalid = request(:patch, "/users/password", c.guest, %{})
    assert invalid.status == 422

    for method <- [:put, :patch] do
      raw = "activation-reset-#{method}"
      digest = Token.digest(:reset_password_token, raw, Dawarich.RailsSecret.fetch())

      Repo.query!(
        "UPDATE users SET reset_password_token=$2,reset_password_sent_at=now() WHERE id=$1",
        [c.user.id, digest],
        log: false
      )

      reset = %{
        "user[reset_password_token]" => raw,
        "user[password]" => "new-synthetic-password12",
        "user[password_confirmation]" => "new-synthetic-password12"
      }

      result = request(method, "/users/password", c.guest, signed(reset, c.guest))
      assert result.status == 303
      assert Repo.get!(Account, c.user.id).reset_password_token == nil
      assert RailsFormRequests.rails_session(result)["session_id"] != c.guest["session_id"]
    end

    guard(
      [
        {:get, "/users/password/new", %{}},
        {:get, "/users/password/edit?reset_password_token=synthetic", %{}},
        {:post, "/users/password", signed(%{"user[email]" => c.user.email}, c.guest)},
        {:put, "/users/password", signed(reset_params("activation-reset-put"), c.guest)},
        {:patch, "/users/password", signed(reset_params("activation-reset-patch"), c.guest)}
      ],
      c.guest
    )
  end

  for provider <- ~w(github google_oauth2 openid_connect) do
    @tag String.to_atom("activation_" <> provider)
    test "standalone #{provider} initiation and callbacks use native state and CSRF admission",
         c do
      provider = unquote(provider)
      path = "/users/auth/" <> provider

      config = %{
        client_id: "synthetic",
        client_secret: "synthetic",
        authorization_endpoint: "https://idp.example.test/authorize",
        redirect_uri: "http://www.example.com" <> path <> "/callback",
        scope: "email",
        issuer: "https://idp.example.test",
        response_type: "code",
        pkce: false,
        client_auth_method: :basic,
        token_endpoint: "http://idp.example.test/token",
        userinfo_endpoint: "http://idp.example.test/profile",
        emails_endpoint: "http://idp.example.test/emails"
      }

      owner = self()

      context = %{
        providers: %{provider => config},
        http: fn method, url, _, _ ->
          send(owner, {:state_exchange, method})

          case URI.parse(url).path do
            "/token" ->
              {:ok, %{"access_token" => "synthetic"}}

            "/profile" ->
              {:ok,
               %{
                 "id" => "synthetic",
                 "sub" => "synthetic",
                 "name" => "Synthetic",
                 "email" => c.user.email,
                 "email_verified" => true
               }}

            "/emails" ->
              {:ok, [%{"email" => c.user.email, "primary" => true, "verified" => true}]}
          end
        end
      }

      Application.put_env(:dawarich, :provider_auth_context, context)
      assert request(:post, path, c.guest, %{}).status == 422
      started = request(:post, path, c.guest, signed(%{}, c.guest))
      assert started.status == 302

      assert get_resp_header(started, "location")
             |> hd()
             |> String.starts_with?("https://idp.example.test/")

      assert Map.has_key?(started.private, :dawarich_rate_limit)

      pending = RailsFormRequests.rails_session(started)

      for method <- [:get, :post], state <- [nil, "mismatched"] do
        params = %{"code" => "synthetic-code"}
        params = if state, do: Map.put(params, "state", state), else: params

        route =
          if method == :get,
            do: path <> "/callback?" <> URI.encode_query(params),
            else: path <> "/callback"

        failed = request(method, route, pending, params)
        assert failed.status == 302
        assert get_resp_header(failed, "x-dawarich-auth-owner") == ["native-provider"]
        clean = RailsFormRequests.rails_session(failed)
        refute clean["warden.user.user.key"]
        refute clean["pending_oauth_link"]
        refute clean["omniauth.state"]
        refute clean["omniauth.nonce"]
        refute clean["omniauth.pkce.verifier"]
        refute_receive {:state_exchange, _}
        assert Repo.get!(Account, c.user.id).sign_in_count == 0
      end

      guard(
        [
          {:post, path, signed(%{}, c.guest)},
          {:get, path <> "/callback", %{}},
          {:post, path <> "/callback", %{}}
        ],
        c.guest
      )
    end
  end

  @tag :activation_link
  test "standalone account linkage uses closure endpoints and rejects unsigned writes", c do
    for path <- ["/auth/account_link", "/auth/account_link/challenge"] do
      response = request(:get, path, c.guest)
      assert response.status == 302
      assert get_resp_header(response, "x-dawarich-auth-owner") == ["native-provider"]
    end

    for path <- ["/auth/account_link/challenge", "/auth/account_link/email"] do
      assert request(:post, path, c.guest, %{}).status == 422
      response = request(:post, path, c.guest, signed(%{}, c.guest))
      assert response.status == 302
      assert Map.has_key?(response.private, :dawarich_rate_limit)
    end

    {:ok, token} =
      Dawarich.Auth.AccountLink.Closure.issue(
        c.user.id,
        "github",
        "synthetic-activation-uid",
        %{}
      )

    path = "/auth/account_link?" <> URI.encode_query(%{token: token})
    linked = request(:get, path, c.guest)
    assert linked.status == 302
    assert Repo.get!(Account, c.user.id).provider == "github"
    session = RailsFormRequests.rails_session(linked)
    assert session["session_id"] != c.guest["session_id"]
    assert [[id], _] = session["warden.user.user.key"]
    assert id == c.user.id
    replay = request(:get, path, c.guest)
    assert replay.status == 302
    refute Map.has_key?(RailsFormRequests.rails_session(replay), "warden.user.user.key")

    guard(
      [
        {:get, "/auth/account_link", %{}},
        {:get, "/auth/account_link/challenge", %{}},
        {:post, "/auth/account_link/challenge", %{}},
        {:post, "/auth/account_link/email", signed(%{}, c.guest)},
        {:post, "/auth/account_link/challenge", signed(%{}, c.guest)},
        {:get, path, %{}}
      ],
      c.guest
    )
  end

  @tag :activation_settings
  test "standalone settings PATCH persists the native result and retains API authentication", c do
    path = "/api/v1/settings"
    params = %{"settings" => %{"point_dragging_enabled" => true}}
    saved = api(:patch, path, c.user, params)
    assert saved.status == 200
    assert Jason.decode!(saved.resp_body)["status"] == "success"
    assert Accounts.settings(c.user.id)["point_dragging_enabled"] == true
    assert api(:patch, path, nil, params).status == 401
    guard_api(:patch, path, c.user, params)
  end

  @tag :activation_position
  test "standalone point position PATCH reaches native validation with the point path parameter",
       c do
    id = System.unique_integer([:positive])

    Repo.query!(
      "INSERT INTO points(id,user_id,timestamp,lonlat,lock_version,created_at,updated_at) VALUES($1,$2,1700000000,ST_SetSRID(ST_MakePoint(13,52),4326),0,now(),now())",
      [id, c.user.id],
      log: false
    )

    path = "/api/v1/points/#{id}/position"

    params = %{
      "point" => %{"latitude" => 51.5, "longitude" => 12.5, "revision" => 0},
      "history_scope" => %{"start_at" => 1_699_999_999, "end_at" => 1_700_000_001}
    }

    moved = api(:patch, path, c.user, params)
    assert moved.status == 200
    assert Jason.decode!(moved.resp_body)["revision"]["point"] == 1

    assert Repo.query!(
             "SELECT ST_X(lonlat::geometry),ST_Y(lonlat::geometry) FROM points WHERE id=$1",
             [id],
             log: false
           ).rows == [[12.5, 51.5]]

    assert api(:patch, path, nil, params).status == 401
    assert api(:patch, path, c.user, params).status == 409
    guard_api(:patch, path, c.user, params)
  end

  @tag :activation_timeline
  test "standalone timeline missing dates return the merged native validation", c do
    response = api(:get, "/api/v1/timeline", c.user, %{})
    assert response.status == 400
    assert Jason.decode!(response.resp_body) == %{"error" => "start_at and end_at are required"}
    guard_api(:get, "/api/v1/timeline", c.user, %{})
  end

  @tag :activation_hexagons
  test "standalone hexagon index returns the merged native empty collection", c do
    response = api(:get, "/api/v1/maps/hexagons", c.user, %{})
    assert response.status == 200
    assert Jason.decode!(response.resp_body)["features"] == []
    assert api(:get, "/api/v1/maps/hexagons", nil, %{}).status == 401
    public = api(:get, "/api/v1/maps/hexagons?uuid=missing-synthetic-grant", nil, %{})
    assert public.status == 404
    guard_api(:get, "/api/v1/maps/hexagons", c.user, %{})
  end

  defp reset_params(raw) do
    %{
      "user[reset_password_token]" => raw,
      "user[password]" => "new-synthetic-password12",
      "user[password_confirmation]" => "new-synthetic-password12"
    }
  end

  defp signed(params, session),
    do: Map.put(params, "authenticity_token", RailsCsrf.masked_token(session))

  defp request(method, path, session, params \\ %{}) do
    body = if method == :get, do: "", else: URI.encode_query(params)
    ip = :erlang.phash2(session["session_id"], 65_536)

    %{build_conn() | remote_ip: {198, 18, div(ip, 256), rem(ip, 256)}}
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("accept", "text/html")
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> dispatch(@endpoint, method, path, body)
  end

  defp api(method, path, user, params) do
    body = if method == :get, do: "", else: Jason.encode!(params)

    conn =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-length", to_string(byte_size(body)))

    conn =
      if user, do: put_req_header(conn, "authorization", "Bearer " <> user.api_key), else: conn

    dispatch(conn, @endpoint, method, path, body)
  end

  defp guard(routes, session) do
    System.delete_env("DAWARICH_RAILS")
    upstream = RailsFormRequests.upstream!()

    for {method, path, params} <- routes do
      {{line, body}, response} =
        RailsFormRequests.forwarded(upstream, fn -> request(method, path, session, params) end)

      assert response.status == 204
      assert String.starts_with?(line, String.upcase(to_string(method)) <> " " <> path <> " ")
      assert body == if(method == :get, do: "", else: URI.encode_query(params))
    end

    System.put_env("DAWARICH_RAILS", "off")
  end

  defp guard_api(method, path, user, params) do
    System.delete_env("DAWARICH_RAILS")
    upstream = RailsFormRequests.upstream!()

    {{line, body}, response} =
      RailsFormRequests.forwarded(upstream, fn -> api(method, path, user, params) end)

    assert response.status == 204
    assert String.starts_with?(line, String.upcase(to_string(method)) <> " " <> path <> " ")
    assert body == if(method == :get, do: "", else: Jason.encode!(params))
    System.put_env("DAWARICH_RAILS", "off")
  end
end

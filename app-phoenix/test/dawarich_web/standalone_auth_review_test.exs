defmodule DawarichWeb.StandaloneAuthReviewTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.{Repo, Accounts}
  alias Dawarich.Auth.Account
  alias Dawarich.Test.{RailsUser, RailsFormRequests}
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
      :apple_auth_context,
      :api_auth_context,
      :subscription_context
    ]

    config = Map.new(keys, &{&1, Application.fetch_env(:dawarich, &1)})
    Application.put_env(:dawarich, :jobs_repo, Repo)
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "false")
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

    id = System.unique_integer([:positive])

    user =
      RailsUser.insert!(%{
        id: id,
        email: "review-#{id}@dawarich.test",
        api_key: "synthetic-review-#{id}",
        provider: "github",
        uid: "#{id}"
      })

    guest = %{"session_id" => Ecto.UUID.generate(), "_csrf_token" => RailsCsrf.new_token()}
    %{user: user, guest: guest}
  end

  @tag :review_r1
  test "R1 duplicate session cookies refuse initiation and successful callbacks in both orders",
       c do
    github(c.user)
    path = "/users/auth/github"
    pending = start(path, c.guest)
    params = %{"code" => "synthetic-code", "state" => pending["omniauth.state"]}

    for {method, route, session, params} <- [
          {:get, path <> "/callback?" <> URI.encode_query(params), pending, %{}},
          {:post, path, c.guest, csrf(%{}, c.guest)}
        ],
        order <- [:first, :last] do
      response = web(method, route, session, params, duplicate: order)
      assert response.status == 422
      refute response.resp_cookies["_dawarich_session"]
      refute_receive {:exchange, _}
      assert Repo.get!(Account, c.user.id).sign_in_count == 0

      guard(
        fn -> web(method, route, session, params, duplicate: order) end,
        method,
        route,
        if(method == :get, do: "", else: URI.encode_query(params))
      )
    end

    good = web(:get, path <> "/callback?" <> URI.encode_query(params), pending)
    assert_logged_in(good, c.user.id, pending)
    assert_receive {:exchange, :post}
  end

  @tag :review_r1_families
  test "R1 every newly admitted browser auth family refuses cookie ambiguity", c do
    github(c.user)
    Application.put_env(:dawarich, :apple_auth_context, apple_context())

    routes = [
      {:get, "/users/sign_up", %{}},
      {:post, "/users", csrf(%{}, c.guest)},
      {:get, "/users/password/new", %{}},
      {:post, "/users/password", csrf(%{}, c.guest)},
      {:patch, "/users", csrf(%{}, c.guest)},
      {:get, "/auth/account_link", %{}},
      {:post, "/auth/account_link/challenge", csrf(%{}, c.guest)},
      {:get, "/users/auth/apple", %{}},
      {:post, "/users/auth/apple/callback", %{}},
      {:post, "/api/v1/auth/apple", %{}},
      {:post, "/api/v1/auth/google.json", %{}}
    ]

    for {method, path, params} <- routes, order <- [:first, :last] do
      response = web(method, path, c.guest, params, duplicate: order)
      assert response.status == 422
      refute response.resp_cookies["_dawarich_session"]
    end

    refute_receive {:exchange, _}
  end

  @tag :review_r3
  test "R3 Cloud signed in POST overrides and literal PATCH PUT persist through native account admission",
       c do
    password = "synthetic-current-password12"
    hash = Bcrypt.hash_pwd_salt(password, log_rounds: 4)

    Repo.query!(
      "UPDATE users SET provider=NULL,encrypted_password=$2 WHERE id=$1",
      [c.user.id, hash],
      log: false
    )

    session = Map.put(c.guest, "warden.user.user.key", [[c.user.id], binary_part(hash, 0, 29)])

    for {method, override} <- [{:post, "patch"}, {:post, "put"}, {:patch, nil}, {:put, nil}] do
      name = "Review-#{method}-#{override}"
      params = csrf(%{"user[first_name]" => name, "user[current_password]" => password}, session)
      params = if override, do: Map.put(params, "_method", override), else: params
      response = web(method, "/users", session, params)
      assert response.status == 303
      assert get_resp_header(response, "x-dawarich-auth-owner") == ["native-account"]
      assert Repo.get!(Account, c.user.id).first_name == name
      assert response.method == String.upcase(to_string(method))
      assert response.private.dawarich_raw_body == URI.encode_query(params)
      assert response.private.dawarich_rate_limit == []

      guard(
        fn -> web(method, "/users", session, params) end,
        method,
        "/users",
        URI.encode_query(params)
      )

      invalid = web(method, "/users", session, Map.delete(params, "authenticity_token"))
      assert invalid.status == 422
      assert Repo.get!(Account, c.user.id).first_name == name
    end
  end

  @tag :review_r4
  test "R4 valid code with missing mismatched state never exchanges and matching state rotates login",
       c do
    github(c.user)
    path = "/users/auth/github"
    pending = start(path, c.guest)

    for method <- [:get, :post], state <- [nil, "mismatched"] do
      params = %{"code" => "synthetic-code"}
      params = if state, do: Map.put(params, "state", state), else: params

      route =
        if method == :get,
          do: path <> "/callback?" <> URI.encode_query(params),
          else: path <> "/callback"

      failed = web(method, route, pending, params)
      assert failed.status == 302
      clean = RailsFormRequests.rails_session(failed)
      refute clean["warden.user.user.key"]
      refute clean["pending_oauth_link"]
      refute clean["omniauth.state"]
      refute clean["omniauth.nonce"]
      refute clean["omniauth.pkce.verifier"]
      refute_receive {:exchange, _}
      assert Repo.get!(Account, c.user.id).sign_in_count == 0
      assert Repo.aggregate(Account, :count) == 1
    end

    success =
      web(
        :get,
        path <>
          "/callback?" <>
          URI.encode_query(%{"code" => "synthetic-code", "state" => pending["omniauth.state"]}),
        pending
      )

    assert_logged_in(success, c.user.id, pending)
    assert_receive {:exchange, :post}
  end

  @tag :review_r2_mobile
  test "R2 all mobile actions formats and settings reach native admission through Endpoint", c do
    Application.put_env(:dawarich, :api_auth_context, %{log_rounds: 4})

    for setting <- ["false", "true", nil] do
      if setting,
        do: System.put_env("SELF_HOSTED", setting),
        else: System.delete_env("SELF_HOSTED")

      for suffix <- ["", ".json", ".html"],
          {action, expected} <- [
            {"login", 401},
            {"otp_challenge", 401},
            {"register", 422},
            {"google", 401},
            {"apple", 401}
          ] do
        path = "/api/v1/auth/" <> action <> suffix
        response = api(:post, path, %{})
        assert response.status == expected
        refute response.resp_cookies["_dawarich_session"]
        assert Map.has_key?(response.private, :dawarich_rate_limit)
        assert is_map(response.body_params)
        guard(fn -> api(:post, path, %{}) end, :post, path, "{}")
      end
    end

    System.put_env("SELF_HOSTED", "false")
    form = web(:post, "/api/v1/auth/register", c.guest, %{"email" => "invalid"})
    assert form.status == 422
    assert form.private.dawarich_raw_body == "email=invalid"
    System.put_env("SELF_HOSTED", "true")

    params = %{
      "email" => "mobile-#{c.user.id}@dawarich.test",
      "password" => "synthetic-password12",
      "password_confirmation" => "synthetic-password12"
    }

    response = api(:post, "/api/v1/auth/register", params)
    assert response.status == 201
    assert Repo.get_by!(Account, email: params["email"]).sign_in_count == 0
    refute response.resp_cookies["_dawarich_session"]
  end

  @tag :review_r2_apple
  test "R2 Apple web initiation callback state nonce bridge and session rotation reach Endpoint",
       c do
    {private, key} = signing_key()

    context =
      Map.merge(apple_context(), %{
        jwks_uri: "http://idp.test/keys/" <> Ecto.UUID.generate(),
        http: fn :get, _, _, _ -> {:ok, %{"keys" => [key]}} end
      })

    Application.put_env(:dawarich, :apple_auth_context, context)
    Repo.query!("UPDATE users SET provider='apple' WHERE id=$1", [c.user.id], log: false)
    started = web(:get, "/users/auth/apple", c.guest)
    assert started.status == 302

    query =
      started
      |> get_resp_header("location")
      |> hd()
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    for name <- ~w(apple_oauth_state apple_oauth_nonce) do
      assert started.resp_cookies[name].http_only
      assert started.resp_cookies[name].secure
      assert started.resp_cookies[name].same_site == "None"
      assert started.resp_cookies[name].max_age == 600
    end

    claims = %{
      "iss" => "https://appleid.apple.com",
      "aud" => "synthetic-client",
      "exp" => System.os_time(:second) + 300,
      "iat" => System.os_time(:second),
      "sub" => c.user.uid,
      "email" => c.user.email,
      "email_verified" => true,
      "nonce" => query["nonce"]
    }

    params = %{"state" => query["state"], "id_token" => jwt(private, claims)}
    cookies = Map.new(started.resp_cookies, fn {name, value} -> {name, value.value} end)

    for bad <- [
          Map.put(params, "state", "wrong"),
          Map.put(params, "id_token", jwt(private, Map.put(claims, "nonce", "wrong")))
        ] do
      failed = web(:post, "/users/auth/apple/callback", c.guest, bad, cookies: cookies)
      assert failed.status == 302
      refute RailsFormRequests.rails_session(failed)["warden.user.user.key"]
      assert failed.resp_cookies["apple_oauth_state"].max_age == 0
      assert Repo.get!(Account, c.user.id).sign_in_count == 0
    end

    success = web(:post, "/users/auth/apple/callback", c.guest, params, cookies: cookies)
    assert_logged_in(success, c.user.id, c.guest)
    assert success.resp_cookies["apple_oauth_nonce"].max_age == 0
    assert Map.has_key?(success.private, :dawarich_raw_body)
    guard(fn -> web(:get, "/users/auth/apple", c.guest) end, :get, "/users/auth/apple")

    guard(
      fn -> web(:post, "/users/auth/apple/callback", c.guest, params, cookies: cookies) end,
      :post,
      "/users/auth/apple/callback",
      URI.encode_query(params)
    )
  end

  @tag :review_r2_apple_transport
  test "R2 Apple source HEAD and optional formats retain native ownership and coexistence", c do
    Application.put_env(:dawarich, :apple_auth_context, apple_context())

    for method <- [:get, :head], suffix <- ["", ".html", ".json"] do
      path = "/users/auth/apple" <> suffix
      response = web(method, path, c.guest)
      assert response.status == 302
      assert response.resp_cookies["apple_oauth_state"]
      assert response.resp_body == ""
      guard(fn -> web(method, path, c.guest) end, method, path)
    end
  end

  @tag :review_r2_handoff
  test "R2 provider mobile client reaches real signed handoff and GET HEAD success Endpoint", c do
    github(c.user)
    path = "/users/auth/github"
    pending = start(path, c.guest, %{"client" => "ios"})

    response =
      web(
        :get,
        path <>
          "/callback?" <>
          URI.encode_query(%{"code" => "synthetic-code", "state" => pending["omniauth.state"]}),
        pending
      )

    assert_logged_in(response, c.user.id, pending)
    location = get_resp_header(response, "location") |> hd() |> URI.parse()
    assert location.path == "/auth/ios/success"
    token = URI.decode_query(location.query)["token"]
    assert token
    [header, payload, signature] = String.split(token, ".")

    assert Base.url_decode64!(signature, padding: false) ==
             :crypto.mac(
               :hmac,
               :sha256,
               Dawarich.Auth.Mobile.Handoff.secret(%{}),
               header <> "." <> payload
             )

    claims = payload |> Base.url_decode64!(padding: false) |> Jason.decode!()
    assert claims["api_key"] == c.user.api_key

    for method <- [:get, :head] do
      success = web(method, location.path <> "?" <> location.query, c.guest)
      assert success.status == 200

      assert if(method == :head,
               do: success.resp_body == "",
               else: success.resp_body =~ "close this window"
             )

      guard(
        fn -> web(method, location.path <> "?" <> location.query, c.guest) end,
        method,
        location.path <> "?" <> location.query
      )
    end
  end

  @tag :review_r2_subscription
  test "R2 subscription callback uses webhook admission without API key and exact method path",
       c do
    Application.put_env(:dawarich, :subscription_context, %{
      env: %{"SUBSCRIPTION_WEBHOOK_SECRET" => "synthetic", "JWT_SECRET_KEY" => "synthetic"}
    })

    response = api(:post, "/api/v1/subscriptions/callback", %{"token" => "invalid"})
    assert response.status == 401
    assert Map.has_key?(response.private, :dawarich_rate_limit)

    guard(
      fn -> api(:post, "/api/v1/subscriptions/callback", %{"token" => "invalid"}) end,
      :post,
      "/api/v1/subscriptions/callback",
      Jason.encode!(%{"token" => "invalid"})
    )

    assert api(:get, "/api/v1/subscriptions/callback", %{}).status == 404
    assert api(:post, "/api/v1/subscriptions/callback.json", %{}).status == 404

    claims = %{
      "user_id" => c.user.id,
      "event_id" => Ecto.UUID.generate(),
      "exp" => System.os_time(:second) + 300,
      "status" => "inactive",
      "plan" => "lite",
      "event_timestamp_ms" => System.os_time(:millisecond)
    }

    header = Base.url_encode64(~s({"alg":"HS256"}), padding: false)
    payload = Base.url_encode64(Jason.encode!(claims), padding: false)
    input = header <> "." <> payload

    token =
      input <>
        "." <> Base.url_encode64(:crypto.mac(:hmac, :sha256, "synthetic", input), padding: false)

    send_event = fn ->
      api(:post, "/api/v1/subscriptions/callback", %{"token" => token}, [
        {"x-webhook-secret", "synthetic"}
      ])
    end

    assert send_event.().status == 200
    assert Repo.get!(Account, c.user.id).status == 0
    assert Repo.get!(Account, c.user.id).plan == 0
    assert Jason.decode!(send_event.().resp_body)["message"] == "Stale event"
    assert Accounts.get(c.user.id)
  end

  defp github(user) do
    owner = self()

    config = %{
      client_id: "synthetic",
      client_secret: "synthetic",
      scope: "email",
      authorization_endpoint: "https://idp.test/authorize",
      redirect_uri: "http://www.example.com/users/auth/github/callback",
      token_endpoint: "http://idp.test/token",
      userinfo_endpoint: "http://idp.test/profile",
      emails_endpoint: "http://idp.test/emails"
    }

    context = %{
      providers: %{"github" => config},
      http: fn method, url, _, _ ->
        send(owner, {:exchange, method})

        case URI.parse(url).path do
          "/token" -> {:ok, %{"access_token" => "synthetic"}}
          "/profile" -> {:ok, %{"id" => user.uid, "name" => "Synthetic User"}}
          "/emails" -> {:ok, [%{"email" => user.email, "primary" => true, "verified" => true}]}
        end
      end
    }

    Application.put_env(:dawarich, :provider_auth_context, context)
  end

  defp start(path, session, params \\ %{}) do
    started = web(:post, path, session, csrf(params, session))
    assert started.status == 302
    RailsFormRequests.rails_session(started)
  end

  defp assert_logged_in(response, id, pending) do
    assert response.status == 302
    session = RailsFormRequests.rails_session(response)
    assert [[^id], _] = session["warden.user.user.key"]
    assert session["session_id"] != pending["session_id"]
    refute session["omniauth.state"]
  end

  defp csrf(params, session),
    do: Map.put(params, "authenticity_token", RailsCsrf.masked_token(session))

  defp web(method, path, session, params \\ %{}, opts \\ []) do
    body = if method in [:get, :head], do: "", else: URI.encode_query(params)
    cookie = "_dawarich_session=" <> RailsUser.cookie(session)

    cookie =
      case opts[:duplicate] do
        :first -> cookie <> "; _dawarich_session=malformed"
        :last -> "_dawarich_session=malformed; " <> cookie
        _ -> cookie
      end

    cookie =
      Enum.reduce(opts[:cookies] || %{}, cookie, fn {name, value}, acc ->
        acc <> "; " <> name <> "=" <> value
      end)

    %{build_conn() | remote_ip: {198, 18, 1, rem(:erlang.phash2(session["session_id"]), 250)}}
    |> put_req_header("cookie", cookie)
    |> put_req_header("accept", "text/html")
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> dispatch(@endpoint, method, path, body)
  end

  defp api(method, path, params, headers \\ []) do
    body = if method == :get, do: "", else: Jason.encode!(params)

    %{build_conn() | remote_ip: {198, 19, 1, rem(System.unique_integer([:positive]), 250)}}
    |> then(fn conn ->
      Enum.reduce(headers, conn, fn {name, value}, conn -> put_req_header(conn, name, value) end)
    end)
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> dispatch(@endpoint, method, path, body)
  end

  defp guard(fun, method, path, expected_body \\ "") do
    System.delete_env("DAWARICH_RAILS")
    upstream = RailsFormRequests.upstream!()
    {{line, body}, response} = RailsFormRequests.forwarded(upstream, fun)
    assert response.status == 204
    assert String.starts_with?(line, String.upcase(to_string(method)) <> " " <> path <> " ")
    assert body == expected_body
    System.put_env("DAWARICH_RAILS", "off")
  end

  defp apple_context do
    %{
      self_hosted: false,
      env: %{
        "APPLE_WEB_SERVICES_ID" => "synthetic-client",
        "APPLE_WEB_TEAM_ID" => "synthetic",
        "APPLE_WEB_KEY_ID" => "synthetic",
        "APPLE_WEB_P8_BASE64" => "synthetic",
        "APPLE_WEB_REDIRECT_URI" => "http://www.example.com/users/auth/apple/callback"
      }
    }
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
       "kid" => "synthetic-review",
       "alg" => "RS256",
       "n" => encode.(n),
       "e" => encode.(e)
     }}
  end

  defp jwt(private, claims) do
    encode = fn value -> Base.url_encode64(value, padding: false) end

    input =
      encode.(Jason.encode!(%{"alg" => "RS256", "kid" => "synthetic-review"})) <>
        "." <> encode.(Jason.encode!(claims))

    input <> "." <> encode.(:public_key.sign(input, :sha256, private))
  end
end

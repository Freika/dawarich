defmodule DawarichWeb.TrialWelcomeEndpointTest do
  use Dawarich.JobsCase, async: false
  import Plug.Conn
  alias Dawarich.{RailsCookies, RailsSecret, Repo}
  alias Dawarich.Test.{RailsUser, SharingSeeds}

  @moduletag :capture_log
  @jwt "synthetic-welcome-endpoint-secret"
  @user_id 18161

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    saved =
      Map.new(
        ~w(DAWARICH_RAILS SELF_HOSTED JWT_SECRET_KEY OIDC_CLIENT_ID OIDC_CLIENT_SECRET OIDC_PKCE_ENABLED GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET),
        &{&1, System.get_env(&1)}
      )

    Enum.each(Map.keys(saved), &System.delete_env/1)
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "false")
    System.put_env("JWT_SECRET_KEY", @jwt)
    RailsUser.insert!(%{id: @user_id, email: "welcome-endpoint@example.invalid", status: 2})

    on_exit(fn ->
      for {key, value} <- saved,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    :ok
  end

  test "Cloud proxy welcome redirects and tracks Rails client IP across IPv4 and IPv6 chains" do
    for {headers, peer, expected} <- [
          {[{"x-forwarded-for", "192.0.2.5, 10.0.0.2, 127.0.0.1"}], {127, 0, 0, 1}, "192.0.2.5"},
          {[{"x-forwarded-for", "192.0.2.5, 198.51.100.9, 172.16.1.2"}], {10, 0, 0, 1},
           "198.51.100.9"},
          {[{"x-forwarded-for", "2001:db8::5, fc00::2, fe80::3"}], {0, 0, 0, 0, 0, 0, 0, 1},
           "2001:db8::5"},
          {[{"x-forwarded-for", "invalid, 192.0.2.6, 169.254.1.2"}], {127, 0, 0, 1}, "192.0.2.6"},
          {[{"x-forwarded-for", "10.0.0.5, 192.168.1.2"}], {127, 0, 0, 1}, "10.0.0.5"},
          {[{"client-ip", "192.0.2.7"}], {127, 0, 0, 1}, "192.0.2.7"},
          {[
             {"forwarded", ~s(for="[2001:db8::8]:443";proto=https, for=10.0.0.2;proto=https)},
             {"x-forwarded-for", "192.0.2.99"}
           ], {127, 0, 0, 1}, "192.0.2.99"},
          {[{"x-forwarded-for", "192.0.2.9, 10.0.0.2"}], {203, 0, 113, 8}, "203.0.113.8"}
        ] do
      reset_trackable()
      path = welcome_path()
      conn = %{Phoenix.ConnTest.build_conn() | remote_ip: peer}

      conn =
        Enum.reduce(proxy_headers() ++ headers, conn, fn {key, value}, c ->
          put_req_header(c, key, value)
        end)

      result = dispatch(conn, :get, path)
      assert_welcome(result)
      assert get_resp_header(result, "location") == ["https://cloud.example.test/map/v2"]

      assert Repo.query!("SELECT current_sign_in_ip FROM users WHERE id=$1", [@user_id],
               log: false
             ).rows == [[expected]]

      assert get_resp_header(result, "cache-control") == ["no-store"]
      replay = dispatch(conn, :get, path)
      assert get_resp_header(replay, "location") == ["https://cloud.example.test/users/sign_in"]

      assert Repo.query!("SELECT sign_in_count FROM users WHERE id=$1", [@user_id], log: false).rows ==
               [[1]]
    end

    claims_before = Repo.query!("SELECT count(*) FROM phoenix.once_claims", [], log: false).rows

    invalid =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("x-forwarded-for", "192.0.2.5, 10.0.0.2")
      |> dispatch(:get, "/trial/welcome?token=invalid")

    assert invalid.status == 302
    assert get_resp_header(invalid, "location") == ["http://www.example.com/users/sign_in"]

    for field <- ["otp_required_for_login", "locked_at"] do
      value = if field == "locked_at", do: "CURRENT_TIMESTAMP", else: "true"
      Repo.query!("UPDATE users SET #{field}=#{value} WHERE id=$1", [@user_id], log: false)
      refused = dispatch(Phoenix.ConnTest.build_conn(), :get, welcome_path())
      assert refused.status == 500
      assert refused.resp_cookies == %{}

      Repo.query!(
        "UPDATE users SET #{field}=#{if field == "locked_at", do: "NULL", else: "false"} WHERE id=$1",
        [@user_id],
        log: false
      )
    end

    assert Repo.query!("SELECT count(*) FROM phoenix.once_claims", [], log: false).rows ==
             claims_before

    spoofed =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("x-forwarded-for", "192.0.2.5")
      |> put_req_header("client-ip", "198.51.100.6")
      |> dispatch(:get, welcome_path())

    assert spoofed.status == 500
    assert spoofed.resp_cookies == %{}
    assert get_resp_header(spoofed, "location") == []

    assert Repo.query!("SELECT sign_in_count FROM users WHERE id=$1", [@user_id], log: false).rows ==
             [[1]]
  end

  test "welcome redemption succeeds with configured OIDC and Google OAuth" do
    for prefix <- ~w(OIDC GOOGLE_OAUTH) do
      System.put_env(prefix <> "_CLIENT_ID", "synthetic-client")
      System.put_env(prefix <> "_CLIENT_SECRET", "synthetic-secret")
      reset_trackable()
      assert_welcome(dispatch(Phoenix.ConnTest.build_conn(), :get, welcome_path()))
      System.delete_env(prefix <> "_CLIENT_ID")
      System.delete_env(prefix <> "_CLIENT_SECRET")
    end
  end

  test "welcome redemption signs in OAuth targets without starting a provider flow" do
    for provider <- ~w(google_oauth2 openid_connect apple) do
      Repo.query!(
        "UPDATE users SET provider=$1,uid=$2 WHERE id=$3",
        [provider, "synthetic-uid", @user_id],
        log: false
      )

      reset_trackable()
      assert_welcome(dispatch(Phoenix.ConnTest.build_conn(), :get, welcome_path()))
    end
  end

  test "guest trial redirects preserve mobile and referral markers before authentication" do
    for path <- ~w(/trial/upgrade /trial/resume), mode <- ~w(false true) do
      System.put_env("SELF_HOSTED", mode)
      result = dispatch(Phoenix.ConnTest.build_conn(), :get, path <> "?client=ios&aff=partner")
      assert result.status == 302
      assert get_resp_header(result, "location") == ["http://www.example.com/users/sign_in"]
      stored = session(result)
      assert stored["dawarich_client"] == "ios"
      assert stored["partnero_referral"] == if(mode == "false", do: "partner", else: nil)
      assert stored["user_return_to"] == path <> "?client=ios&aff=partner"
      assert stored["flash"]["flashes"]["alert"] != nil
      refute Map.has_key?(stored, "warden.user.user.key")

      marked =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("x-dawarich-client", "android")
        |> Phoenix.ConnTest.put_req_cookie(
          "_dawarich_session",
          RailsUser.cookie(%{"partnero_referral" => "original"})
        )
        |> dispatch(:get, path <> "?client=ios&via=next")
        |> session()

      assert marked["dawarich_client"] == "android"
      assert marked["partnero_referral"] == if(mode == "false", do: "next", else: "original")
    end
  end

  test "Cloud shared link unlock accepts the same forwarding envelope as welcome" do
    SharingSeeds.load!()
    id = "a9500000-0000-4000-8000-000000000002"

    [[phrase]] =
      Repo.query!("SELECT magic_phrase FROM shared_links WHERE id=$1::text::uuid", [id],
        log: false
      ).rows

    body = URI.encode_query(%{"phrase" => phrase})

    conn =
      Enum.reduce(
        proxy_headers() ++ [{"x-forwarded-for", "2001:db8::5, 10.0.0.2"}],
        Phoenix.ConnTest.build_conn(),
        fn {key, value}, c -> put_req_header(c, key, value) end
      )
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", to_string(byte_size(body)))

    result =
      Phoenix.ConnTest.dispatch(
        conn,
        DawarichWeb.Endpoint,
        :post,
        "/s/#{id}/unlock",
        body
      )

    assert result.status == 302
    assert get_resp_header(result, "location") == ["https://cloud.example.test/s/#{id}"]
    assert map_size(result.resp_cookies) > 0
  end

  test "rotating Forwarded XFF prefixes and X-Real-IP cannot evade unlock or OAuth challenge limits in either mode" do
    SharingSeeds.load!()
    hosts = Application.get_env(:dawarich, :allowed_hosts)

    Application.put_env(
      :dawarich,
      :allowed_hosts,
      DawarichWeb.HostAuthorization.boot_config(%{
        "RAILS_ENV" => "production",
        "APPLICATION_HOSTS" => "www.example.com"
      })
    )

    on_exit(fn -> Application.put_env(:dawarich, :allowed_hosts, hosts) end)

    for mode <- ~w(false true),
        {path, body, denied} <- [
          {"/s/a9500000-0000-4000-8000-000000000002/unlock", "phrase=wrong", 401},
          {"/auth/account_link/challenge", "password=wrong", 422}
        ],
        forged? <- [false, true] do
      System.put_env("SELF_HOSTED", mode)
      ScratchRepo.query!("DELETE FROM phoenix.counters", [], log: false)

      statuses =
        for attempt <- 1..6 do
          conn = %{
            Phoenix.ConnTest.build_conn()
            | remote_ip: {10, 0, 0, 2},
              req_headers: [{"host", "www.example.com"}]
          }

          conn =
            conn
            |> put_req_header("x-forwarded-proto", "https")
            |> put_req_header(
              "x-forwarded-for",
              if(forged?,
                do: "198.51.100.#{attempt}, 203.0.113.25, 10.0.0.3",
                else: "203.0.113.25"
              )
            )
            |> put_req_header("content-type", "application/x-www-form-urlencoded")
            |> put_req_header("content-length", to_string(byte_size(body)))

          conn =
            if forged?,
              do:
                conn
                |> put_req_header("forwarded", "for=198.51.100.#{attempt}")
                |> put_req_header("x-real-ip", "192.0.2.#{attempt}"),
              else: conn

          Phoenix.ConnTest.dispatch(conn, DawarichWeb.Endpoint, :post, path, body).status
        end

      assert statuses == [denied, denied, denied, denied, denied, 429],
             inspect({mode, path, forged?, statuses})
    end
  end

  test "pass-through XFF and Client-IP preserve Rails fresh buckets without ingress-written identity in both modes" do
    SharingSeeds.load!()
    hosts = Application.get_env(:dawarich, :allowed_hosts)

    Application.put_env(
      :dawarich,
      :allowed_hosts,
      DawarichWeb.HostAuthorization.boot_config(%{
        "RAILS_ENV" => "production",
        "APPLICATION_HOSTS" => "www.example.com"
      })
    )

    on_exit(fn -> Application.put_env(:dawarich, :allowed_hosts, hosts) end)

    for mode <- ~w(false true),
        {path, body, denied} <- [
          {"/s/a9500000-0000-4000-8000-000000000002/unlock", "phrase=wrong", 401},
          {"/auth/account_link/challenge", "password=wrong", 422}
        ],
        form <- [:none, :xff, :client, :client_v4_host, :client_bracket, :client_v6_host] do
      System.put_env("SELF_HOSTED", mode)
      ScratchRepo.query!("DELETE FROM phoenix.counters", [], log: false)

      statuses =
        for attempt <- 1..6 do
          conn = %{
            Phoenix.ConnTest.build_conn()
            | remote_ip: {10, 0, 0, 2},
              req_headers: [{"host", "www.example.com"}]
          }

          headers =
            case form do
              :none -> []
              :xff -> [{"x-forwarded-for", "198.51.100.#{attempt}"}]
              :client -> [{"client-ip", "198.51.100.#{attempt}"}]
              :client_v4_host -> [{"client-ip", "198.51.100.#{attempt}/32"}]
              :client_bracket -> [{"client-ip", "[2001:db8::#{attempt}]"}]
              :client_v6_host -> [{"client-ip", "2001:db8::#{attempt}/128"}]
            end

          conn =
            Enum.reduce(headers, conn, fn {key, value}, c -> put_req_header(c, key, value) end)
            |> put_req_header("x-forwarded-proto", "https")
            |> put_req_header("content-type", "application/x-www-form-urlencoded")
            |> put_req_header("content-length", to_string(byte_size(body)))

          Phoenix.ConnTest.dispatch(conn, DawarichWeb.Endpoint, :post, path, body).status
        end

      expected =
        if form == :none, do: List.duplicate(denied, 5) ++ [429], else: List.duplicate(denied, 6)

      assert statuses == expected, inspect({mode, path, form, statuses})
    end
  end

  defp proxy_headers,
    do: [
      {"x-forwarded-proto", "http, https"},
      {"x-forwarded-host", "proxy.internal, cloud.example.test"}
    ]

  defp assert_welcome(result) do
    assert result.status == 302
    assert get_resp_header(result, "x-dawarich-trial-owner") == ["native-welcome"]
    stored = session(result)
    assert hd(stored["warden.user.user.key"]) == [@user_id]
    assert stored["flash"]["flashes"]["notice"] != nil

    assert Repo.query!("SELECT sign_in_count FROM users WHERE id=$1", [@user_id], log: false).rows ==
             [[1]]
  end

  defp reset_trackable,
    do: Repo.query!("UPDATE users SET sign_in_count=0 WHERE id=$1", [@user_id], log: false)

  defp session(result) do
    {:ok, stored} =
      RailsCookies.decrypt(
        result.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        RailsSecret.fetch(),
        DateTime.utc_now()
      )

    stored
  end

  defp dispatch(conn, method, path),
    do: Phoenix.ConnTest.dispatch(conn, DawarichWeb.Endpoint, method, path, nil)

  defp welcome_path do
    payload = %{
      "purpose" => "trial_welcome",
      "user_id" => @user_id,
      "exp" => System.os_time(:second) + 1800,
      "jti" => "welcome-endpoint-#{System.unique_integer([:positive])}"
    }

    input =
      Base.url_encode64(~s({"alg":"HS256"}), padding: false) <>
        "." <> Base.url_encode64(Jason.encode!(payload), padding: false)

    token =
      input <> "." <> Base.url_encode64(:crypto.mac(:hmac, :sha256, @jwt, input), padding: false)

    "/trial/welcome?" <> URI.encode_query(%{"token" => token})
  end
end

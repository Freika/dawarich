defmodule Dawarich.Auth.HttpBoundaryTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.Auth.SessionCookie
  alias DawarichWeb.{AuthCookie, AuthForm, AuthHandler, RailsSession}
  alias Dawarich.RailsCookies

  @secret "phoenix-a2-cookie-fixture-secret-not-for-production"

  test "OTP initiation replays Turbo Stream XHR unsupported Accept and query-format requests without native effects" do
    alias Dawarich.{Repo, Test.RailsUser}
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    old_hosted = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if old_hosted,
        do: System.put_env("SELF_HOSTED", old_hosted),
        else: System.delete_env("SELF_HOSTED")
    end)

    fixtures = File.read!("test/fixtures/auth/requests.json") |> Jason.decode!()
    crypto = File.read!("test/fixtures/active_record_encryption.json") |> Jason.decode!()
    env = Enum.find(crypto["environments"], &(&1["name"] == "explicit keys"))["env"]

    RailsUser.insert!(%{
      id: 75540,
      email: "a11d-boundary@dawarich.test",
      api_key: "A11D_BOUNDARY",
      encrypted_password: fixtures["login"]["user"]["encrypted_password"],
      otp_required_for_login: true,
      settings: %{}
    })

    {session, cookie} = SessionCookie.for_form(%{}, @secret)

    raw =
      URI.encode_query(%{
        "authenticity_token" => DawarichWeb.RailsCsrf.masked_token(session),
        "user[email]" => "a11d-boundary@dawarich.test",
        "user[password]" => "safepassword12"
      })

    before = Repo.query!("SELECT to_jsonb(u) FROM users u ORDER BY id", [], log: false).rows

    opts = [
      enabled: true,
      registration_enabled: false,
      otp_enabled: true,
      otp_context: %{self_hosted: true, oidc: false, env: env},
      fallback: fn conn ->
        original = conn.private[:dawarich_raw_body] || elem(read_body(conn), 1)

        send(
          self(),
          {:otp_boundary_replay, conn.method, original, get_req_header(conn, "cookie")}
        )

        put_private(conn, :handed_to_rails, true)
      end
    ]

    for {path, extra} <- [
          {"/users/sign_in", [{"accept", "text/vnd.turbo-stream.html, text/html"}]},
          {"/users/sign_in", [{"x-requested-with", "XMLHttpRequest"}]},
          {"/users/sign_in", [{"accept", "text/plain"}]},
          {"/users/sign_in", [{"accept", "application/json"}]},
          {"/users/sign_in", [{"accept", "application/xml"}]},
          {"/users/sign_in?format=html", []},
          {"/users/sign_in?locale=de", []},
          {"/users/sign_in.json", []}
        ] do
      conn =
        Plug.Test.conn(:post, path, raw)
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
        |> put_req_header("cookie", "_dawarich_session=#{cookie}")

      conn = Enum.reduce(extra, conn, fn {key, value}, acc -> put_req_header(acc, key, value) end)
      response = AuthHandler.call(conn, opts)
      assert response.private[:handed_to_rails] == true
      assert response.resp_cookies == %{}
      assert get_resp_header(response, "x-dawarich-auth-owner") == []
      assert_received {:otp_boundary_replay, "POST", ^raw, [original_cookie]}
      preserved = original_cookie == "_dawarich_session=#{cookie}"
      assert preserved
      refute_received {:otp_boundary_replay, _, _, _}

      unchanged =
        Repo.query!("SELECT to_jsonb(u) FROM users u ORDER BY id", [], log: false).rows == before

      assert unchanged
    end

    supported =
      Plug.Test.conn(:post, "/users/sign_in", raw)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
      |> put_req_header("cookie", "_dawarich_session=#{cookie}")
      |> put_req_header("accept", "text/html")

    response = AuthHandler.call(supported, opts)
    assert response.status == 422
    assert get_resp_header(response, "x-dawarich-auth-owner") == ["native-otp"]
    Repo.query!("UPDATE users SET otp_required_for_login=false WHERE id=75540", [], log: false)

    conn =
      Plug.Test.conn(:post, "/users/sign_in", raw)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
      |> put_req_header("cookie", "_dawarich_session=#{cookie}")
      |> put_req_header("accept", "text/vnd.turbo-stream.html, text/html")

    assert AuthHandler.call(conn, opts).status == 303
  end

  setup do
    old = Application.get_env(:dawarich, :rails_secret)
    Application.put_env(:dawarich, :rails_secret, @secret)
    on_exit(fn -> Application.put_env(:dawarich, :rails_secret, old) end)
    :ok
  end

  test "ownership defaults inactive and preserves the untouched request for fallback" do
    conn = Plug.Test.conn(:post, "/users/sign_in", "user%5Bemail%5D=test")
    assert AuthHandler.call(conn, fallback: & &1) == conn
  end

  test "ambiguous form replay and a missing CSRF token hand the consumed body to Rails before credentials" do
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    duplicate = "user%5Bemail%5D=a&user%5Bemail%5D=b"

    conn =
      Plug.Test.conn(:post, "/users/sign_in", duplicate)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(duplicate)))

    replayed = AuthHandler.call(conn, enabled: true, registration_enabled: false, fallback: & &1)
    assert replayed.private.dawarich_raw_body == duplicate
    refute replayed.halted
    invalid_type = put_req_header(conn, "content-type", "application/x-www-form-urlencoded-bad")

    untouched =
      AuthHandler.call(invalid_type, enabled: true, registration_enabled: false, fallback: & &1)

    refute Map.has_key?(untouched.private, :dawarich_raw_body)
    override = "_method=delete&user%5Bemail%5D=a"

    conn =
      Plug.Test.conn(:post, "/users/sign_in", override)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(override)))

    upstream = Dawarich.Test.RawHTTP.listen()
    previous_upstream = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, previous_upstream) end)

    peer =
      Task.async(fn ->
        socket = Dawarich.Test.RawHTTP.accept(upstream)
        {head, rest} = Dawarich.Test.RawHTTP.read_head(socket)
        body = Dawarich.Test.RawHTTP.read_at_least(socket, rest, byte_size(override))
        Dawarich.Test.RawHTTP.reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
        :gen_tcp.close(socket)
        {Dawarich.Test.RawHTTP.request_line(head), body}
      end)

    replayed = AuthHandler.call(conn, enabled: true, registration_enabled: false, fallback: & &1)
    assert replayed.status == 200 and replayed.halted
    assert Task.await(peer) == {"POST /users/sign_in HTTP/1.1", override}
    assert replayed.private.dawarich_raw_body == override

    raw = "user%5Bemail%5D=unknown&user%5Bpassword%5D=secret"

    conn =
      Plug.Test.conn(:post, "/users/sign_in", raw)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(raw)))

    refused = AuthHandler.call(conn, enabled: true, registration_enabled: false, fallback: & &1)
    refute refused.halted
    assert refused.private.dawarich_raw_body == raw
  end

  test "absent authoritative registration policy remains a pre-effect handoff" do
    conn = Plug.Test.conn(:get, "/users/sign_in")
    result = AuthHandler.call(conn, enabled: true, fallback: & &1)
    refute result.halted
    assert result.resp_cookies == %{}
  end

  test "auth cookie cancels staged layout changes rather than replacing new Warden credentials" do
    user = %{id: 7, encrypted_password: String.duplicate("a", 60)}
    issued = SessionCookie.for_login(%{}, user, "Signed in successfully.", @secret)

    conn =
      Plug.Test.conn(:get, "/")
      |> RailsSession.stage(%{"locale" => "de", "_csrf_token" => "old"})
      |> AuthCookie.session(issued)
      |> send_resp(303, "")

    cookie = conn.resp_cookies["_dawarich_session"].value

    assert {:ok, decoded} =
             RailsCookies.decrypt(cookie, "_dawarich_session", @secret, DateTime.utc_now())

    assert decoded["warden.user.user.key"] == [[7], String.duplicate("a", 29)]
    refute Map.has_key?(decoded, "_csrf_token")
    refute Map.has_key?(decoded, "locale")
  end

  test "layout changes staged after remember restoration preserve the renewed Warden session" do
    user = %{id: 7, encrypted_password: String.duplicate("a", 60)}
    issued = SessionCookie.for_restore(%{}, user, @secret)
    token = DawarichWeb.RailsCsrf.new_token()

    conn =
      Plug.Test.conn(:get, "/stats")
      |> AuthCookie.session(issued)
      |> RailsSession.stage(%{"_csrf_token" => token})
      |> send_resp(200, "")

    cookie = conn.resp_cookies["_dawarich_session"].value

    assert {:ok, decoded} =
             RailsCookies.decrypt(cookie, "_dawarich_session", @secret, DateTime.utc_now())

    assert decoded["warden.user.user.key"] == [[7], String.duplicate("a", 29)]
    assert decoded["_csrf_token"] == token
  end

  test "login form escapes the submitted email and keeps the remember-me hidden field" do
    html = AuthForm.render("token", "\"><script>alert(1)</script>")
    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
    assert html =~ "name=\"user[remember_me]\" type=\"hidden\" value=\"0\""
  end
end

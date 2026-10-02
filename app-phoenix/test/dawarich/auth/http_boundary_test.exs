defmodule Dawarich.Auth.HttpBoundaryTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.Auth.SessionCookie
  alias DawarichWeb.{AuthCookie, AuthForm, AuthHandler, RailsSession}
  alias Dawarich.RailsCookies

  @secret "phoenix-a2-cookie-fixture-secret-not-for-production"

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

    replayed = AuthHandler.call(conn, enabled: true, registration_enabled: false, fallback: & &1)
    refute replayed.halted
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

  test "login form escapes submitted email and alert HTML" do
    html = AuthForm.render("token", "\"><script>alert(1)</script>", "<script>bad</script>")
    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
    assert html =~ "name=\"user[remember_me]\" value=\"0\""
  end
end

defmodule Dawarich.Auth.AuthHandlerTest do
  use ExUnit.Case, async: false
  import Plug.Conn

  alias Dawarich.{Accounts, RailsCookies, RailsSecret, Repo}
  alias Dawarich.Auth.RememberCookie
  alias DawarichWeb.{AuthHandler, AuthRestore, RailsAuth, RailsCsrf}

  @fixture Jason.decode!(File.read!(Path.expand("../../fixtures/auth/requests.json", __DIR__)))
  @hash @fixture["user_before"]["encrypted_password"]
  @base "http://www.example.com"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    email = "handler-a11-#{System.unique_integer([:positive])}@dawarich.test"

    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO users(email,encrypted_password,status,created_at,updated_at) VALUES($1,$2,1,now(),now()) RETURNING id",
        [email, @hash]
      )

    %{id: id, email: email}
  end

  test "a correct password answers 303 to the absolute root with Rails' session keys", ctx do
    session = guest()

    conn =
      call(
        :post,
        "/users/sign_in",
        [session_cookie(session)],
        sign_in(session, ctx.email, "safepassword12"),
        [{"origin", @base}]
      )

    assert conn.status == @fixture["login"]["response"]["status"]
    assert get_resp_header(conn, "location") == [@fixture["login"]["response"]["location"]]
    assert get_resp_header(conn, "x-dawarich-auth-owner") == ["native-credentials"]

    assert Enum.sort(Map.keys(response_session(conn))) ==
             Enum.sort(Map.keys(@fixture["login"]["decoded"]["session"]))

    refute Map.has_key?(conn.resp_cookies, "remember_user_token")
    assert state(ctx.id) == %{failed_attempts: 0, sign_in_count: 1, remembered: false}
  end

  test "a wrong password and an unknown email get the same native 422 without the owner header",
       ctx do
    session = guest()

    for email <- [ctx.email, "nobody-#{ctx.email}"] do
      conn =
        call(
          :post,
          "/users/sign_in",
          [session_cookie(session)],
          sign_in(session, email, "not-the-password")
        )

      assert conn.status == @fixture["wrong_password"]["response"]["status"]
      assert conn.resp_body =~ "Invalid email or password."
      assert get_resp_header(conn, "x-dawarich-auth-owner") == []
    end

    assert state(ctx.id).failed_attempts == @fixture["wrong_password"]["user"]["failed_attempts"]
  end

  test "the failure message capitalises a leading authentication key, as Devise's failure app does",
       ctx do
    session = Map.put(guest(), "locale", "fr")

    conn =
      call(
        :post,
        "/users/sign_in",
        [session_cookie(session)],
        sign_in(session, ctx.email, "not-the-password")
      )

    assert conn.status == 422
    assert conn.resp_body =~ "Email ou mot de passe incorrect."
  end

  test "an effective count of 7 stays native and 8 is handed to Rails untouched", ctx do
    Repo.query!("UPDATE users SET failed_attempts=7 WHERE id=$1", [ctx.id])
    session = guest()
    body = sign_in(session, ctx.email, "not-the-password")

    assert call(:post, "/users/sign_in", [session_cookie(session)], body).status == 422
    assert state(ctx.id).failed_attempts == 9

    Repo.query!("UPDATE users SET failed_attempts=8 WHERE id=$1", [ctx.id])
    conn = call(:post, "/users/sign_in", [session_cookie(session)], body)
    assert conn.private[:handed_to_rails]
    assert conn.private.dawarich_raw_body == body
    assert state(ctx.id).failed_attempts == 8
  end

  test "sign-out revokes remember credentials on every device and deletes the cookie", ctx do
    Repo.query!("UPDATE users SET remember_created_at=now() WHERE id=$1", [ctx.id])
    session = signed_in(ctx.id)
    conn = call(:post, "/users/sign_out", [session_cookie(session)], sign_out(session))

    assert conn.status == @fixture["logout"]["response"]["status"]
    assert get_resp_header(conn, "location") == [@fixture["logout"]["response"]["location"]]

    assert Enum.sort(Map.keys(response_session(conn))) ==
             Enum.sort(Map.keys(@fixture["logout"]["decoded"]["session"]))

    assert %{max_age: 0, path: "/"} = conn.resp_cookies["remember_user_token"]
    assert state(ctx.id).remembered == false
  end

  test "user_return_to redirects only to a plain local path", ctx do
    for {stored, path} <- [{"//x", "/"}, {"/\\x", "/"}, {"/\t/x", "/"}, {"/ok", "/ok"}] do
      session = Map.put(guest(), "user_return_to", stored)

      conn =
        call(
          :post,
          "/users/sign_in",
          [session_cookie(session)],
          sign_in(session, ctx.email, "safepassword12")
        )

      assert get_resp_header(conn, "location") == [@base <> path], inspect(stored)
    end
  end

  test "a foreign Origin or an unverifiable token hands the retained body to Rails before any effect",
       ctx do
    session = guest()
    body = sign_in(session, ctx.email, "not-the-password")
    other = sign_in(guest(), ctx.email, "not-the-password")

    for {cookies, request, headers} <- [
          {[session_cookie(session)], body, [{"origin", "http://evil.example"}]},
          {[session_cookie(session)], other, []},
          {[], body, []}
        ] do
      conn = call(:post, "/users/sign_in", cookies, request, headers)
      assert conn.private[:handed_to_rails]
      assert conn.private.dawarich_raw_body == request
    end

    assert state(ctx.id).failed_attempts == 0
  end

  test "a locked session or locked remember cookie is handed to Rails on every auth route", ctx do
    Repo.query!(
      "UPDATE users SET locked_at=now(),failed_attempts=10,remember_created_at=now() - interval '1 minute' WHERE id=$1",
      [ctx.id]
    )

    session = signed_in(ctx.id)
    visitor = guest()
    remember = remember_cookie(ctx.id)

    for {method, path, cookies, body} <- [
          {:get, "/users/sign_in", [session_cookie(session)], nil},
          {:post, "/users/sign_in", [session_cookie(session)],
           sign_in(session, ctx.email, "safepassword12")},
          {:post, "/users/sign_out", [session_cookie(session)], sign_out(session)},
          {:get, "/users/sign_in", [remember], nil},
          {:post, "/users/sign_in", [session_cookie(visitor), remember],
           sign_in(visitor, ctx.email, "safepassword12")}
        ] do
      conn = call(method, path, cookies, body)
      assert conn.private[:handed_to_rails], "#{method} #{path}"
      assert conn.resp_cookies == %{}
    end

    assert state(ctx.id) == %{failed_attempts: 10, sign_in_count: 0, remembered: true}
  end

  test "a sign-out without a live session user is Rails' to answer, with the body untouched",
       ctx do
    Repo.query!(
      "UPDATE users SET remember_created_at=now() - interval '1 minute' WHERE id=$1",
      [ctx.id]
    )

    stale = %{"session_id" => "after-sign-out"}
    session = guest()

    for {cookies, body} <- [
          {[session_cookie(stale)], sign_out(session)},
          {[session_cookie(session)], sign_out(session)},
          {[session_cookie(session), remember_cookie(ctx.id)], sign_out(session)}
        ] do
      conn = call(:post, "/users/sign_out", cookies, body)
      assert conn.private[:handed_to_rails]
      assert {:ok, ^body, _} = read_body(conn)
      assert conn.resp_cookies == %{}
    end

    assert state(ctx.id).remembered == true
  end

  test "AuthRestore restores a remember-only browser and leaves a live session alone", ctx do
    Repo.query!(
      "UPDATE users SET remember_created_at=now() - interval '1 minute' WHERE id=$1",
      [ctx.id]
    )

    remember = remember_cookie(ctx.id)
    restored = restore([remember])

    assert restored.assigns.rails_session["warden.user.user.key"] ==
             [[ctx.id], binary_part(@hash, 0, 29)]

    assert Map.has_key?(restored.resp_cookies, "_dawarich_session")
    assert state(ctx.id).sign_in_count == 1

    for conn <- [
          restore([session_cookie(signed_in(ctx.id)), remember]),
          restore([remember], [{"x-forwarded-for", "192.0.2.1"}]),
          restore([remember], [], enabled: false)
        ] do
      assert conn.resp_cookies == %{}
    end

    assert state(ctx.id).sign_in_count == 1
  end

  defp call(method, path, cookies, body, headers \\ []) do
    method
    |> request(path, cookies, body, headers)
    |> AuthHandler.call(
      enabled: true,
      registration_enabled: false,
      fallback: &put_private(&1, :handed_to_rails, true)
    )
  end

  defp restore(cookies, headers \\ [], opts \\ [enabled: true]) do
    :get
    |> request("/stats", cookies, nil, headers)
    |> RailsAuth.call([])
    |> AuthRestore.call(opts)
  end

  defp request(method, path, cookies, body, headers) do
    conn = Plug.Test.conn(method, path, body || "")

    conn =
      if cookies == [],
        do: conn,
        else:
          put_req_header(
            conn,
            "cookie",
            Enum.map_join(cookies, "; ", fn {k, v} -> "#{k}=#{v}" end)
          )

    conn =
      if body,
        do:
          conn
          |> put_req_header("content-type", "application/x-www-form-urlencoded")
          |> put_req_header("content-length", Integer.to_string(byte_size(body))),
        else: conn

    Enum.reduce(headers, conn, fn {name, value}, conn -> put_req_header(conn, name, value) end)
  end

  defp guest, do: %{"session_id" => "a11-guest", "_csrf_token" => RailsCsrf.new_token()}

  defp signed_in(id),
    do: %{
      "warden.user.user.key" => [[id], binary_part(@hash, 0, 29)],
      "_csrf_token" => RailsCsrf.new_token()
    }

  defp sign_in(session, email, password),
    do:
      URI.encode_query([
        {"authenticity_token", RailsCsrf.masked_token(session)},
        {"user[email]", email},
        {"user[password]", password},
        {"user[remember_me]", "0"}
      ])

  defp sign_out(session),
    do:
      URI.encode_query([
        {"_method", "delete"},
        {"authenticity_token", RailsCsrf.masked_token(session)}
      ])

  defp session_cookie(session),
    do:
      {"_dawarich_session",
       RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())}

  defp remember_cookie(id) do
    now = DateTime.utc_now()
    payload = [[id], binary_part(@hash, 0, 29), Accounts.remember_generated_at(now)]

    {"remember_user_token",
     RememberCookie.sign(payload, RailsSecret.fetch(), DateTime.add(now, 3600))}
  end

  defp response_session(conn) do
    {:ok, session} =
      RailsCookies.decrypt(
        conn.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        RailsSecret.fetch(),
        DateTime.utc_now()
      )

    session
  end

  defp state(id) do
    %{rows: [[failed, count, remembered]]} =
      Repo.query!(
        "SELECT failed_attempts,sign_in_count,remember_created_at IS NOT NULL FROM users WHERE id=$1",
        [id]
      )

    %{failed_attempts: failed, sign_in_count: count, remembered: remembered}
  end
end

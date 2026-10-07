defmodule Dawarich.Auth.AuthHandlerTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  require Phoenix.LiveViewTest

  alias Dawarich.{Accounts, RailsCookies, RailsSecret, Repo}
  alias Dawarich.Auth.RememberCookie
  alias Dawarich.Test.{AuthMarkup, ParityHTML}
  alias DawarichWeb.{AuthHandler, AuthRestore, RailsAuth, RailsCsrf}

  @fixture Jason.decode!(File.read!(Path.expand("../../fixtures/auth/requests.json", __DIR__)))
  @hash @fixture["user_before"]["encrypted_password"]
  @base "http://www.example.com"
  @markup AuthMarkup.fixture()["signin"]

  test "credentials dispatch starts OTP only after CSRF and only with its opt-in", ctx do
    crypto = File.read!("test/fixtures/active_record_encryption.json") |> Jason.decode!()
    env = Enum.find(crypto["environments"], &(&1["name"] == "explicit keys"))["env"]
    context = %{self_hosted: true, oidc: false, env: env}

    Repo.query!(
      "UPDATE users SET otp_required_for_login=true,settings='{}',failed_attempts=2,failed_otp_attempts=3 WHERE id=$1",
      [ctx.id],
      log: false
    )

    session = Map.merge(guest(), %{"otp_failed_attempts" => 2, "locale" => "de"})

    body =
      sign_in(session, ctx.email, "safepassword12")
      |> String.replace("user%5Bremember_me%5D=0", "user%5Bremember_me%5D=1")

    before = otp_snapshot()

    opts = [
      enabled: true,
      registration_enabled: false,
      otp_enabled: true,
      otp_context: context,
      fallback: fn conn ->
        send(self(), :otp_replayed)
        put_private(conn, :handed_to_rails, true)
      end
    ]

    response =
      request(:post, "/users/sign_in", [session_cookie(session)], body, [{"origin", @base}])
      |> AuthHandler.call(opts)

    assert response.status == 422 and response.halted
    assert get_resp_header(response, "x-dawarich-auth-owner") == ["native-otp"]
    pending = response_session(response)
    assert pending["otp_user_id"] == ctx.id and pending["otp_remember_me"] == true
    assert pending["otp_failed_attempts"] == 2 and pending["locale"] == "de"
    refute Map.has_key?(pending, "warden.user.user.key")
    refute Map.has_key?(response.resp_cookies, "remember_user_token")
    refute_received :otp_replayed
    unchanged = otp_snapshot() == before
    assert unchanged

    for {submitted_session, email, password, headers, enabled} <- [
          {session, ctx.email, "safepassword12", [], false},
          {session, String.upcase(ctx.email), "safepassword12", [], true},
          {session, " #{ctx.email} ", "safepassword12", [], true},
          {session, ctx.email, "wrong", [], true},
          {session, ctx.email, "", [], true},
          {session, ctx.email, "safepassword12", [{"origin", "http://foreign.invalid"}], true},
          {Map.put(session, "user_return_to", "//foreign.invalid"), ctx.email, "safepassword12",
           [], true}
        ] do
      raw = sign_in(submitted_session, email, password)
      conn = request(:post, "/users/sign_in", [session_cookie(submitted_session)], raw, headers)
      conn = AuthHandler.call(conn, Keyword.put(opts, :otp_enabled, enabled))
      assert conn.private[:handed_to_rails] == true
      assert conn.private[:dawarich_raw_body] == raw
      assert conn.resp_cookies == %{}
      assert_received :otp_replayed
      refute_received :otp_replayed
      unchanged = otp_snapshot() == before
      assert unchanged
    end

    invalid =
      request(
        :post,
        "/users/sign_in",
        [session_cookie(session)],
        sign_in(guest(), ctx.email, "safepassword12"),
        []
      )

    assert AuthHandler.call(invalid, opts).private[:handed_to_rails] == true
    assert_received :otp_replayed

    for cookies <- [
          [session_cookie(signed_in(ctx.id))],
          [session_cookie(session), remember_cookie(ctx.id)]
        ] do
      Repo.query!(
        "UPDATE users SET remember_created_at=now() - interval '1 minute' WHERE id=$1",
        [ctx.id],
        log: false
      )

      conn = request(:post, "/users/sign_in", cookies, body, []) |> AuthHandler.call(opts)
      assert conn.private[:handed_to_rails] == true and conn.resp_cookies == %{}
      assert_received :otp_replayed
    end

    Repo.query!("UPDATE users SET otp_required_for_login=false WHERE id=$1", [ctx.id], log: false)
    session = guest()

    response =
      request(
        :post,
        "/users/sign_in",
        [session_cookie(session)],
        sign_in(session, ctx.email, "safepassword12"),
        []
      )
      |> AuthHandler.call(opts)

    assert response.status == 303
    assert state(ctx.id).sign_in_count == 1
    refute_received :otp_replayed
  end

  defp otp_snapshot,
    do: Repo.query!("SELECT to_jsonb(u) FROM users u ORDER BY id", [], log: false).rows

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

  test "the sign-in page Phoenix serves is Rails' devise/sessions/new, byte for byte" do
    conn = call(:get, "/users/sign_in", [session_cookie(guest())], nil)

    assert conn.status == 200
    assert get_resp_header(conn, "x-dawarich-auth-owner") == ["native-credentials"]

    assert AuthMarkup.strict(AuthMarkup.hero(conn.resp_body)) ==
             AuthMarkup.strict(@markup["signin"]["html"])
  end

  test "the browser's own field set, commit=Log in included, signs in natively", ctx do
    session = guest()
    body = sign_in(session, ctx.email, "safepassword12") <> "&commit=Log+in"

    conn = call(:post, "/users/sign_in", [session_cookie(session)], body, [{"origin", @base}])

    refute conn.private[:handed_to_rails]
    assert conn.status == 303
    assert get_resp_header(conn, "x-dawarich-auth-owner") == ["native-credentials"]
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
      assert get_resp_header(conn, "x-dawarich-auth-owner") == []

      failed = @markup["signin_failed"]
      shown = String.replace(failed["html"], ~s(value="#{failed["email"]}"), ~s(value="#{email}"))
      assert AuthMarkup.strict(AuthMarkup.hero(conn.resp_body)) == AuthMarkup.strict(shown)

      assert ParityHTML.normalize(AuthMarkup.toast(conn.resp_body)) ==
               ParityHTML.normalize(failed["toast"])
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

  @tag :proxy_identity
  test "forged forwarding headers from an untrusted peer cannot change sign in identity", ctx do
    session = guest()

    conn =
      request(
        :post,
        "/users/sign_in",
        [session_cookie(session)],
        sign_in(session, ctx.email, "safepassword12"),
        []
      )

    conn = %{conn | remote_ip: {198, 51, 100, 20}}

    conn =
      conn
      |> put_req_header("x-forwarded-for", "192.0.2.99")
      |> put_req_header("client-ip", "192.0.2.99")

    response = AuthHandler.call(conn, enabled: true, native: true, registration_enabled: false)
    assert response.status == 303

    assert Repo.query!("SELECT current_sign_in_ip::text FROM users WHERE id=$1", [ctx.id],
             log: false
           ).rows == [["198.51.100.20"]]
  end

  @tag :signed_in_form
  test "signed in GET sign in redirects with the Devise already authenticated alert", ctx do
    before = state(ctx.id)

    for native <- [false, true], query <- ["", "?locale=en"] do
      session = Map.put(signed_in(ctx.id), "user_return_to", "/stats")
      response = request(:get, "/users/sign_in" <> query, [session_cookie(session)], nil, [])

      response =
        AuthHandler.call(response,
          enabled: true,
          native: native,
          registration_enabled: false,
          fallback: &put_private(&1, :handed_to_rails, true)
        )

      assert response.status == 302
      assert get_resp_header(response, "location") == [@base <> "/stats"]

      assert response_session(response)["flash"]["flashes"]["alert"] ==
               "You are already signed in."

      assert response_session(response)["warden.user.user.key"] ==
               signed_in(ctx.id)["warden.user.user.key"]

      refute Map.has_key?(response_session(response), "user_return_to")
    end

    response = request(:get, "/users/sign_in", [session_cookie(signed_in(ctx.id))], nil, [])

    response =
      AuthHandler.call(response, enabled: true, native: true, registration_enabled: false)

    assert response.status == 302
    assert get_resp_header(response, "location") == [@base <> "/"]
    assert state(ctx.id) == before
  end

  @tag :review_payment
  test "signed in pending payment GET sign in resumes trial and retains stored location", ctx do
    Repo.query!("UPDATE users SET status=3 WHERE id=$1", [ctx.id], log: false)
    before = state(ctx.id)

    for native <- [false, true], stored <- [nil, "/stats"], query <- ["", "?locale=en"] do
      session = signed_in(ctx.id)
      session = if stored, do: Map.put(session, "user_return_to", stored), else: session
      response = request(:get, "/users/sign_in" <> query, [session_cookie(session)], nil, [])

      response =
        AuthHandler.call(response, enabled: true, native: native, registration_enabled: false)

      assert response.status == 302
      assert get_resp_header(response, "location") == [@base <> "/trial/resume"]
      updated = response_session(response)
      assert updated["user_return_to"] == stored
      assert updated["warden.user.user.key"] == session["warden.user.user.key"]
      assert updated["_csrf_token"] == session["_csrf_token"]
      assert updated["flash"]["flashes"]["alert"] == "You are already signed in."
    end

    assert state(ctx.id) == before
  end

  @tag :review_flash
  test "signed in redirect consumes incoming flash and shows the new alert for one request",
       ctx do
    for status <- [1, 3] do
      Repo.query!("UPDATE users SET status=$1 WHERE id=$2", [status, ctx.id], log: false)
      before = state(ctx.id)

      for native <- [false, true],
          query <- ["", "?locale=en"],
          discard <- [[], ["expired"], ["notice", "expired"]] do
        session =
          signed_in(ctx.id)
          |> Map.put("user_return_to", "/stats")
          |> Map.put("flash", %{
            "discard" => discard,
            "flashes" => %{
              "notice" => "Existing notice",
              "expired" => "Old message",
              "alert" => "Old alert"
            }
          })

        response =
          request(:get, "/users/sign_in" <> query, [session_cookie(session)], nil, [])
          |> AuthHandler.call(enabled: true, native: native, registration_enabled: false)

        target = if status == 3, do: "/trial/resume", else: "/stats"
        assert response.status == 302
        assert get_resp_header(response, "location") == [@base <> target]

        redirected = flash_page(target, response)
        assert redirected.assigns.flash_messages == [{"alert", "You are already signed in."}]
        assert redirected.resp_body =~ "You are already signed in."
        refute redirected.resp_body =~ "Existing notice"
        refute Map.has_key?(response_session(redirected), "flash")

        following = flash_page(target, redirected)
        assert following.assigns.flash_messages == []
        refute following.resp_body =~ "You are already signed in."
        updated = response_session(redirected)
        assert updated["_csrf_token"] == session["_csrf_token"]
        assert updated["warden.user.user.key"] == session["warden.user.user.key"]
        assert updated["user_return_to"] == if(status == 3, do: "/stats", else: nil)

        assert response_session(response)["flash"] == %{
                 "discard" => [],
                 "flashes" => %{"alert" => "You are already signed in."}
               }
      end

      assert state(ctx.id) == before
    end
  end

  defp flash_page(path, previous) do
    cookie = {"_dawarich_session", previous.resp_cookies["_dawarich_session"].value}

    conn =
      request(:get, path, [cookie], nil, [])
      |> RailsAuth.call([])
      |> fetch_query_params()
      |> DawarichWeb.LayoutAssigns.call([])

    body =
      Enum.map_join(conn.assigns.flash_messages, fn {type, message} ->
        Phoenix.LiveViewTest.render_component(&DawarichWeb.Chrome.flash_message/1,
          type: type,
          message: message,
          locale: "en"
        )
      end)

    send_resp(conn, 200, body)
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

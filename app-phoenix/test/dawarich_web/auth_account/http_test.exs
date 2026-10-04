defmodule DawarichWeb.AuthAccount.HttpTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Accounts, RailsCookies, Repo}
  alias Dawarich.Auth.SessionCookie
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{RailsCsrf, AuthAccount.Http}

  @secret "a11rest-http-cookie-secret-not-for-production"
  @password "a11rest-password-42"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    previous = Map.new(~w(SELF_HOSTED APPLICATION_PROTOCOL RAILS_ENV), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("APPLICATION_PROTOCOL", "http")
    System.put_env("RAILS_ENV", "test")

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    hash = Bcrypt.hash_pwd_salt(@password, log_rounds: 4)

    RailsUser.insert!(%{
      id: 73801,
      email: "a11rest-http@dawarich.test",
      encrypted_password: hash,
      api_key: "A11REST_HTTP_KEY",
      settings: %{"timezone" => "Europe/Berlin", "onboarding_completed" => true}
    })

    {session, _} =
      SessionCookie.for_form(%{"a11rest" => "retained", "user_return_to" => "/stats"}, @secret)

    session = Map.put(session, "warden.user.user.key", [[73801], binary_part(hash, 0, 29)])
    owner = self()

    opts = [
      enabled: true,
      context: %{secret: @secret, self_hosted: true, oidc: false, log_rounds: 4},
      fallback: fn conn ->
        raw =
          case conn.private[:dawarich_raw_body] do
            nil ->
              {:ok, raw, _} = read_body(conn)
              raw

            raw ->
              raw
          end

        send(owner, {:replayed, conn.method, conn.query_string, conn.req_headers, raw})
        put_private(conn, :a11rest_replayed, true)
      end
    ]

    %{session: session, opts: opts, hash: hash}
  end

  test "serves local PUT PATCH and overridden POST updates exactly once", c do
    assert Code.ensure_loaded?(Http), "account HTTP module must exist"

    for {method, override, effective} <- [
          {"PUT", nil, "PUT"},
          {"PATCH", nil, "PATCH"},
          {"POST", "put", "PUT"},
          {"POST", "patch", "PATCH"}
        ],
        kind <- [:global, :per_form] do
      token = token(c.session, effective, kind)

      params = %{
        "user[email]" => "#{method}-#{override}-#{kind}@dawarich.test",
        "user[current_password]" => @password,
        "authenticity_token" => token
      }

      params = if override, do: Map.put(params, "_method", override), else: params
      raw = URI.encode_query(params)
      before = snapshot()
      conn = request(c.session, method, "/users", raw) |> Http.call(c.opts)
      assert conn.status == 303 and conn.halted
      assert get_resp_header(conn, "x-dawarich-auth-owner") == ["native-account"]
      assert get_resp_header(conn, "location") == ["http://www.example.com/"]

      assert Repo.query!("SELECT email FROM users WHERE id=73801").rows == [
               [String.downcase(params["user[email]"])]
             ]

      assert unchanged_except?(
               before,
               snapshot(),
               ~w(email updated_at reset_password_token reset_password_sent_at)
             )

      assert conn.assigns.rails_session["a11rest"] == "retained"
      assert Map.keys(conn.resp_cookies) == ["_dawarich_session"]
      refute_received {:replayed, _, _, _, _}
    end

    raw =
      URI.encode_query(%{
        "user[current_password]" => "wrong",
        "user[email]" => "refused@dawarich.test",
        "authenticity_token" => token(c.session, "PUT", :per_form)
      })

    before = snapshot()
    conn = request(c.session, "PUT", "/users", raw) |> Http.call(c.opts)
    assert conn.status == 422 and conn.halted
    assert conn.resp_body =~ "Current password is invalid"
    assert same?(snapshot(), before)
    refute_received {:replayed, _, _, _, _}

    raw =
      URI.encode_query(%{
        "user[current_password]" => @password,
        "user[password]" => "a11rest-new-password-42",
        "authenticity_token" => token(c.session, "PATCH", :per_form)
      })

    conn = request(c.session, "PATCH", "/users", raw) |> Http.call(c.opts)
    assert conn.status == 303
    user = Accounts.get(73801)
    assert Bcrypt.verify_pass("a11rest-new-password-42", user.encrypted_password)
    assert Accounts.from_session(c.session, DateTime.utc_now()) == nil

    assert {:ok, returned} =
             RailsCookies.decrypt(
               conn.resp_cookies["_dawarich_session"].value,
               "_dawarich_session",
               @secret,
               DateTime.utc_now()
             )

    assert Accounts.from_session(returned, DateTime.utc_now()).id == user.id

    huge = Map.put(returned, "huge", String.duplicate("x", 6000))

    raw =
      URI.encode_query(%{
        "user[current_password]" => "a11rest-new-password-42",
        "user[email]" => "committed@dawarich.test",
        "authenticity_token" => token(huge, "PUT", :global)
      })

    assert_raise DawarichWeb.RailsSession.Overflow, fn ->
      request(huge, "PUT", "/users", raw) |> Http.call(c.opts)
    end

    assert Repo.query!("SELECT email FROM users WHERE id=73801").rows == [
             ["committed@dawarich.test"]
           ]

    refute_received {:replayed, _, _, _, _}
  end

  test "unsupported account requests replay original bytes before effects", c do
    assert Code.ensure_loaded?(Http), "account HTTP module must exist"

    raw =
      URI.encode_query(%{
        "user[email]" => "unowned@dawarich.test",
        "user[current_password]" => @password,
        "authenticity_token" => token(c.session, "PUT", :global)
      })

    base = request(c.session, "PUT", "/users", raw)

    cases = [
      {request(c.session, "POST", "/users", raw), c.opts, raw},
      {request(c.session, "POST", "/users", raw <> "&_method=delete"), c.opts,
       raw <> "&_method=delete"},
      {request(c.session, "POST", "/users", raw <> "&_method=PATCH"), c.opts,
       raw <> "&_method=PATCH"},
      {request(c.session, "PUT", "/users", raw <> "&_method=patch"), c.opts,
       raw <> "&_method=patch"},
      {request(c.session, "PUT", "/users", raw <> "&user%5Bemail%5D=last%40dawarich.test"),
       c.opts, raw <> "&user%5Bemail%5D=last%40dawarich.test"},
      {request(c.session, "PUT", "/users", raw <> "&user%5Bcurrent_password%5D=wrong"), c.opts,
       raw <> "&user%5Bcurrent_password%5D=wrong"},
      {request(c.session, "PUT", "/users", raw <> "&user=conflict"), c.opts,
       raw <> "&user=conflict"},
      {request(c.session, "PUT", "/users", raw <> "&user%5Bemail%5D%5Bvalue%5D=x"), c.opts,
       raw <> "&user%5Bemail%5D%5Bvalue%5D=x"},
      {request(c.session, "PUT", "/users", raw <> "&unknown=x"), c.opts, raw <> "&unknown=x"},
      {request(c.session, "PUT", "/users", raw <> "&commit=%ZZ"), c.opts, raw <> "&commit=%ZZ"},
      {request(c.session, "PUT", "/users", raw <> "&commit=%FF"), c.opts, raw <> "&commit=%FF"},
      {request(c.session, "PUT", "/users?locale=en", raw), c.opts, raw},
      {request(c.session, "DELETE", "/users", raw), c.opts, raw},
      {request(c.session, "HEAD", "/users", raw), c.opts, raw},
      {request(c.session, "GET", "/users", raw), c.opts, raw},
      {request(c.session, "PUT", "/users.json", raw), c.opts, raw},
      {base, Keyword.put(c.opts, :enabled, false), raw},
      {base, Keyword.put(c.opts, :context, %{secret: @secret, self_hosted: false, oidc: false}),
       raw},
      {base, Keyword.put(c.opts, :context, %{secret: @secret, self_hosted: true, oidc: true}),
       raw},
      {base, Keyword.put(c.opts, :context, %{secret: nil, self_hosted: true, oidc: false}), raw},
      {delete_req_header(base, "content-length"), c.opts, raw},
      {put_req_header(base, "content-length", "wrong"), c.opts, raw},
      {put_req_header(base, "content-length", "65537"), c.opts, raw},
      {put_req_header(base, "transfer-encoding", "chunked"), c.opts, raw},
      {put_req_header(base, "content-type", "application/json"), c.opts, raw},
      {put_req_header(base, "accept", "application/json"), c.opts, raw},
      {put_req_header(base, "accept", "application/xml"), c.opts, raw},
      {put_req_header(base, "accept", "text/vnd.turbo-stream.html, text/html"), c.opts, raw},
      {put_req_header(base, "origin", "https://foreign.dawarich.test"), c.opts, raw},
      {put_req_header(base, "x-http-method-override", "PUT"), c.opts, raw},
      {put_req_header(base, "x-forwarded-for", "127.0.0.2"), c.opts, raw},
      {put_req_header(base, "x-dawarich-client", "mobile"), c.opts, raw},
      {%{base | req_headers: [{"content-length", "1"} | base.req_headers]}, c.opts, raw},
      {%{
         base
         | req_headers: [{"x-csrf-token", "bad"}, {"x-csrf-token", "worse"} | base.req_headers]
       }, c.opts, raw},
      {put_req_header(base, "x-csrf-token", "bad"), c.opts, raw},
      {request(%{}, "PUT", "/users", raw), c.opts, raw},
      {request(Map.put(c.session, "invitation_token", "special"), "PUT", "/users", raw), c.opts,
       raw},
      {request(
         Map.put(c.session, "warden.user.user.key", [[73801], "stale"]),
         "PUT",
         "/users",
         raw
       ), c.opts, raw}
    ]

    before = snapshot()

    for {input, opts, original} <- cases do
      result = Http.call(input, opts)
      assert result.private[:a11rest_replayed] == true and result.halted
      assert_received {:replayed, method, query, headers, bytes}

      assert method == input.method and query == input.query_string and
               headers == input.req_headers

      assert bytes == original
      assert result.resp_cookies == %{}
      refute result.private[:dawarich_rails_session_changes]
      assert get_resp_header(result, "x-dawarich-auth-owner") == []
      assert same?(snapshot(), before)
    end

    for sql <- [
          "provider='github'",
          "otp_required_for_login=true",
          "status=3",
          "locked_at=now()",
          "deleted_at=now()",
          "settings='{\"immich_url\":\"https://immich.dawarich.test/\"}'::jsonb",
          "settings='[]'::jsonb"
        ] do
      Repo.query!("UPDATE users SET #{sql} WHERE id=73801")
      previous = snapshot()
      result = Http.call(base, c.opts)
      assert result.private[:a11rest_replayed] == true and result.halted, sql
      assert_received {:replayed, _, _, _, ^raw}
      assert same?(snapshot(), previous)

      Repo.query!(
        "UPDATE users SET provider=NULL,otp_required_for_login=false,status=1,locked_at=NULL,deleted_at=NULL,settings='{\"timezone\":\"Europe/Berlin\",\"onboarding_completed\":true}'::jsonb WHERE id=73801"
      )
    end

    Repo.query!("UPDATE users SET remember_created_at=now()-interval '1 minute' WHERE id=73801")
    now = DateTime.utc_now()
    payload = [[73801], binary_part(c.hash, 0, 29), Accounts.remember_generated_at(now)]
    assert Accounts.from_remember_cookie(payload, now).id == 73801

    remembered =
      request(Map.delete(c.session, "warden.user.user.key"), "PUT", "/users", raw)
      |> Plug.Test.put_req_cookie(
        "remember_user_token",
        Dawarich.Auth.RememberCookie.sign(
          payload,
          @secret,
          DateTime.add(now, Accounts.remember_for())
        )
      )

    before = snapshot()
    result = Http.call(remembered, c.opts)
    assert result.private[:a11rest_replayed] == true and result.halted
    assert_received {:replayed, _, _, _, ^raw}
    assert same?(snapshot(), before)
    assert result.resp_cookies == %{}

    for token <- [nil, "bad"] do
      params = %{
        "user[email]" => "invalid-csrf@dawarich.test",
        "user[current_password]" => @password
      }

      params = if token, do: Map.put(params, "authenticity_token", token), else: params
      body = URI.encode_query(params)
      result = request(c.session, "PUT", "/users", body) |> Http.call(c.opts)
      assert result.private[:a11rest_replayed] == true and result.halted
      assert_received {:replayed, _, _, _, ^body}
      assert same?(snapshot(), before)
      assert result.resp_cookies == %{}
    end
  end

  defp request(session, method, path, raw) do
    Plug.Test.conn(method, "http://www.example.com" <> path, raw)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("accept", "text/html")
    |> Plug.Test.put_req_cookie(
      "_dawarich_session",
      RailsCookies.encrypt(session, "_dawarich_session", @secret)
    )
  end

  defp token(session, _method, :global), do: RailsCsrf.masked_token(session)

  defp token(session, method, :per_form) do
    {:ok, csrf} = Base.url_decode64(session["_csrf_token"], padding: false)
    token = :crypto.mac(:hmac, :sha256, csrf, "/users#" <> String.downcase(method))
    pad = :crypto.strong_rand_bytes(32)
    Base.url_encode64(pad <> :crypto.exor(pad, token), padding: false)
  end

  defp snapshot do
    [row] = Repo.query!("SELECT to_jsonb(users) FROM users WHERE id=73801", [], log: false).rows
    hd(row)
  end

  defp same?(left, right), do: left == right

  defp unchanged_except?(before, after_row, fields),
    do: Map.drop(before, fields) == Map.drop(after_row, fields)
end

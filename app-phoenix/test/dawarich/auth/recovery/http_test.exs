defmodule Dawarich.Auth.Recovery.HttpTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.Auth.SessionCookie
  alias Dawarich.Repo
  alias DawarichWeb.AuthRecovery.Http

  @effects Jason.decode!(
             File.read!(Path.expand("../../../fixtures/auth/recovery/effects.json", __DIR__))
           )
  @http Jason.decode!(
          File.read!(Path.expand("../../../fixtures/auth/recovery/http.json", __DIR__))
        )
  @secret "phoenix-a2-cookie-fixture-secret-not-for-production"
  defmodule FailingRead do
    def read_req_body(_state, _opts), do: {:error, :timeout}
    defdelegate send_resp(state, status, headers, body), to: Plug.Adapters.Test.Conn
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    email = "http-#{System.unique_integer([:positive])}@dawarich.test"

    [[id]] =
      Repo.query!(
        "INSERT INTO users(email,created_at,updated_at) VALUES($1,now(),now()) RETURNING id",
        [email]
      ).rows

    {session, cookie} = SessionCookie.for_form(%{}, @secret)
    token = DawarichWeb.RailsCsrf.masked_token(session)
    owner = self()

    opts = [
      enabled: true,
      context: %{
        self_hosted: true,
        oidc: false,
        registration_enabled: true,
        secret: @secret,
        log_rounds: 4,
        enqueue: fn intent ->
          send(owner, {:intent, intent})
          :ok
        end
      },
      fallback: fn conn -> put_private(conn, :recovery_fallback, true) end
    ]

    %{id: id, email: email, cookie: cookie, token: token, opts: opts}
  end

  test "native request validates CSRF then issues the generic 303", c do
    conn =
      post(c, %{"user[email]" => c.email, "authenticity_token" => c.token}) |> Http.call(c.opts)

    assert conn.status == 303
    assert get_resp_header(conn, "x-dawarich-auth-owner") == ["native-recovery"]
    assert_received {:intent, _}
  end

  test "a paranoid request for an account with legacy settings answers natively and stores Rails' sanitized settings",
       c do
    row = @http["dirty_settings_request"]
    Repo.query!("UPDATE users SET settings=$1 WHERE id=$2", [row["settings_before"], c.id])

    conn =
      post(c, %{"user[email]" => c.email, "authenticity_token" => c.token}) |> Http.call(c.opts)

    refute conn.private[:recovery_fallback]
    assert conn.status == row["status"]
    assert get_resp_header(conn, "x-dawarich-auth-owner") == ["native-recovery"]
    [[settings]] = Repo.query!("SELECT settings FROM users WHERE id=$1", [c.id]).rows
    assert settings == row["settings"]
    assert_received {:intent, _}
  end

  test "without an enabled option every recovery route falls back with zero writes", c do
    opts = Keyword.delete(c.opts, :enabled)
    form = URI.encode_query(%{"user[email]" => c.email, "authenticity_token" => c.token})

    for {method, path, raw} <- [
          {"GET", "/users/password/new", ""},
          {"GET", "/users/password/edit?reset_password_token=synthetic", ""},
          {"GET", "/users/unlock/new", ""},
          {"GET", "/users/unlock?unlock_token=synthetic", ""},
          {"POST", "/users/password", form},
          {"POST", "/users/unlock", form},
          {"PUT", "/users/password", form}
        ] do
      assert (request(c, method, path, raw) |> Http.call(opts)).private[:recovery_fallback]
    end

    [[token, unlock]] =
      Repo.query!("SELECT reset_password_token,unlock_token FROM users WHERE id=$1", [c.id]).rows

    assert {token, unlock} == {nil, nil}
    refute_received {:intent, _}
  end

  test "invalid CSRF and foreign origin hand the request and its body to Rails with zero recovery mutation",
       c do
    for params <- [
          %{"user[email]" => c.email},
          %{"user[email]" => c.email, "authenticity_token" => "bad"},
          %{"user[email]" => c.email, "authenticity_token" => c.token}
        ] do
      conn = post(c, params)
      conn = if params["authenticity_token"] == c.token, do: foreign(conn), else: conn
      conn = Http.call(conn, c.opts)
      assert conn.private[:recovery_fallback]
      assert conn.private[:dawarich_raw_body] == URI.encode_query(params)
      assert conn.status == nil
    end

    [[token]] = Repo.query!("SELECT reset_password_token FROM users WHERE id=$1", [c.id]).rows
    assert token == nil
    refute_received {:intent, _}
  end

  test "duplicates and unsupported framing preserve body for whole-flow handback", c do
    raw =
      URI.encode_query(%{"authenticity_token" => c.token, "user[email]" => c.email}) <>
        "&user%5Bemail%5D=other%40test"

    conn = request(c, "POST", "/users/password", raw) |> Http.call(c.opts)
    assert conn.private[:recovery_fallback]
    assert conn.private[:dawarich_raw_body] == raw

    assert (request(c, "POST", "/users/password", raw)
            |> delete_req_header("content-length")
            |> Http.call(c.opts)).private[:recovery_fallback]

    [[token]] = Repo.query!("SELECT reset_password_token FROM users WHERE id=$1", [c.id]).rows
    assert token == nil
  end

  test "delivery-owner missing hands back before issuance; failed delivery rolls issuance back and answers 500",
       c do
    params = %{"authenticity_token" => c.token, "user[email]" => c.email}

    missing =
      Keyword.put(c.opts, :context, %{
        self_hosted: true,
        oidc: false,
        registration_enabled: true,
        secret: @secret
      })

    assert (post(c, params) |> Http.call(missing)).private[:recovery_fallback]
    [[token]] = Repo.query!("SELECT reset_password_token FROM users WHERE id=$1", [c.id]).rows
    assert token == nil

    failed =
      Keyword.update!(
        c.opts,
        :context,
        &Map.put(&1, :enqueue, fn _ -> {:error, :synthetic_failure} end)
      )

    assert (post(c, params) |> Http.call(failed)).status == @effects["delivery_failure"]["status"]
    [[token]] = Repo.query!("SELECT reset_password_token FROM users WHERE id=$1", [c.id]).rows
    assert token == nil
  end

  test "a request body that cannot be read answers 400 instead of crashing", c do
    conn = post(c, %{"user[email]" => c.email, "authenticity_token" => c.token})
    {Plug.Adapters.Test.Conn, state} = conn.adapter
    conn = Http.call(%{conn | adapter: {FailingRead, state}}, c.opts)

    assert {conn.state, conn.status, conn.halted} == {:sent, 400, true}
    refute_received {:intent, _}
  end

  test "native GET forms render masked Rails CSRF and method override", c do
    conn =
      request(c, "GET", "/users/password/edit?reset_password_token=synthetic", "")
      |> Http.call(c.opts)

    assert conn.status == 200
    assert conn.resp_body =~ ~s(name="_method" value="put")
    assert conn.resp_body =~ ~s(name="authenticity_token")
    assert conn.resp_body =~ ~s(value="synthetic" name="user[reset_password_token]")
  end

  defp post(c, params), do: request(c, "POST", "/users/password", URI.encode_query(params))
  defp foreign(conn), do: put_req_header(conn, "origin", "http://foreign.test")

  defp request(c, method, path, raw) do
    Plug.Test.conn(method, "http://localhost" <> path, raw)
    |> then(fn conn -> %{conn | req_headers: [{"host", "localhost"} | conn.req_headers]} end)
    |> put_req_header("cookie", Plug.Conn.Cookies.encode("_dawarich_session", %{value: c.cookie}))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
  end
end

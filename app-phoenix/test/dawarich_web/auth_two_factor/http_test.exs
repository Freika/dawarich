defmodule DawarichWeb.AuthTwoFactor.HttpTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{RailsCookies, Repo}
  alias Dawarich.Auth.{Account, SessionCookie}
  alias Dawarich.Auth.TwoFactor.{Secret, Totp}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{AuthTwoFactor.Http, RailsCsrf}
  @id 74601
  @path "/settings/two_factor"
  @secret "a11c-http-synthetic-cookie-key"
  @now ~U[2026-10-04 12:00:00.000000Z]
  @env %{
    "OTP_ENCRYPTION_PRIMARY_KEY" => "a11c-synthetic-primary-not-for-production",
    "OTP_ENCRYPTION_DETERMINISTIC_KEY" => "a11c-synthetic-deterministic-not-for-production",
    "OTP_ENCRYPTION_KEY_DERIVATION_SALT" => "a11c-synthetic-salt-not-for-production"
  }
  defmodule CountingRepo do
    defdelegate one(query, opts), to: Repo
    defdelegate query!(query, params, opts), to: Repo

    def update!(changeset, opts) do
      send(self(), :otp_write)
      Repo.update!(changeset, opts)
    end
  end

  defmodule Unreadable do
    def read_req_body(_, _), do: {:error, :closed}
    defdelegate send_resp(state, status, headers, body), to: Plug.Adapters.Test.Conn
  end

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

    hash = Bcrypt.hash_pwd_salt("a11c-http-password", log_rounds: 4)

    RailsUser.insert!(%{
      id: @id,
      email: "a11c-http@dawarich.test",
      encrypted_password: hash,
      api_key: "A11C_HTTP",
      settings: %{}
    })

    {session, _} = SessionCookie.for_form(%{"user_return_to" => "/stats"}, @secret)
    session = Map.put(session, "warden.user.user.key", [[@id], binary_part(hash, 0, 29)])
    owner = self()

    opts = [
      enabled: true,
      context: %{
        secret: @secret,
        self_hosted: true,
        oidc: false,
        env: @env,
        clock: fn -> @now end,
        repo: CountingRepo,
        backup_options: [cost: 4]
      },
      fallback: fn conn ->
        raw =
          case conn.private[:dawarich_raw_body] do
            nil ->
              {:ok, raw, _} = read_body(conn)
              raw

            raw ->
              raw
          end

        send(owner, {:replayed, conn.method, raw})
        put_private(conn, :replayed, true)
      end
    ]

    %{session: session, opts: opts}
  end

  test "management HTTP dispatch matches source actions and CSRF-bound overrides", c do
    assert Code.ensure_loaded?(Http), "management HTTP module must exist"
    assert Http.init([]) == []
    before = snapshot()
    show = request(c.session, "", "GET") |> Http.call(c.opts)
    assert show.status == 200 and show.halted
    assert snapshot() == before
    assert_identity(show, c.session)
    refute_received :otp_write

    for enabled <- [false, true], source <- [:body, :header] do
      seed(otp_required_for_login: enabled, consumed_timestep: nil, otp_backup_codes: nil)
      setup = submit(c, "POST", @path, %{}, source)
      assert setup.status == 200 and setup.halted
      assert setup.resp_body =~ "otp_attempt"
      assert Repo.get!(Account, @id).otp_required_for_login == enabled
      assert_received :otp_write
      refute_received :otp_write
      assert_identity(setup, c.session)
      {:ok, secret} = Secret.decrypt(Repo.get!(Account, @id).otp_secret, @env)
      bad = submit(c, "POST", @path <> "/verify", %{"otp_attempt" => "bad"}, source)
      assert bad.status == 422
      assert bad.resp_body =~ ~s(name="otp_attempt")
      refute bad.resp_body =~ ~s(value="bad")
      refute_received :otp_write

      good =
        submit(
          c,
          "POST",
          @path <> "/verify",
          %{"otp_attempt" => Totp.at(secret, DateTime.to_unix(@now))},
          source
        )

      assert good.status == 200
      assert Repo.get!(Account, @id).otp_required_for_login
      assert length(Repo.get!(Account, @id).otp_backup_codes) == 10
      assert_received :otp_write
      assert_received :otp_write
      refute_received :otp_write
      assert_identity(good, c.session)

      for method <- ["DELETE", "POST"] do
        params = %{"password" => "wrong", "otp_attempt" => "bad"}
        params = if method == "POST", do: Map.put(params, "_method", "delete"), else: params
        result = submit(c, method, @path, params, source, "DELETE")
        assert result.status == 302
        assert get_resp_header(result, "location") == ["http://www.example.com" <> @path]
        refute_received :otp_write
      end

      result =
        submit(
          c,
          "POST",
          @path,
          %{
            "_method" => "delete",
            "password" => "a11c-http-password",
            "otp_attempt" => Totp.at(secret, DateTime.to_unix(@now) + 30)
          },
          source,
          "DELETE"
        )

      assert result.status == 302
      user = Repo.get!(Account, @id)
      refute user.otp_required_for_login
      assert is_nil(user.otp_secret) and is_nil(user.otp_backup_codes)
      assert_received :otp_write
      assert_received :otp_write
      refute_received :otp_write
      refute_received {:replayed, _, _}
    end

    unavailable = Keyword.update!(c.opts, :context, &Map.put(&1, :env, %{}))
    result = request(c.session, "", "GET") |> Http.call(unavailable)
    assert result.status == 302
    assert get_resp_header(result, "location") == ["http://www.example.com/settings/general"]
    refute_received :otp_write
  end

  test "unsupported management requests reach Rails before effects with original bytes", c do
    assert Code.ensure_loaded?(Http), "management HTTP module must exist"
    raw = URI.encode_query(%{"authenticity_token" => RailsCsrf.masked_token(c.session)})
    base = request(c.session, raw)

    invalid = [
      request(c.session, raw, "HEAD"),
      request(c.session, raw, "PATCH"),
      request(c.session, raw, "GET", @path <> ".json"),
      request(c.session, raw, "POST", @path <> "?locale=en"),
      request(c.session, raw, "GET", @path <> "/verify"),
      request(c.session, raw <> "&unknown=1"),
      request(c.session, raw <> "&otp_attempt[]=bad"),
      request(c.session, raw <> "&authenticity_token=duplicate"),
      request(c.session, raw <> "&_method=patch"),
      request(c.session, "authenticity_token=%ZZ"),
      request(c.session, raw <> "&password=ignored"),
      request(c.session, "otp_attempt=bad", "POST", @path <> "/verify"),
      request(%{}, raw),
      request(Map.put(c.session, "warden.user.user.key", [[@id], "stale"]), raw),
      request(Map.put(c.session, "pending_import_ticket", "special"), raw),
      put_req_header(base, "accept", "application/json"),
      put_req_header(base, "accept", "text/vnd.turbo-stream.html"),
      put_req_header(base, "x-requested-with", "XMLHttpRequest"),
      put_req_header(base, "x-http-method-override", "DELETE"),
      put_req_header(base, "x-dawarich-client", "mobile"),
      put_req_header(base, "x-forwarded-for", "127.0.0.2"),
      put_req_header(base, "origin", "https://foreign.dawarich.test"),
      put_req_header(base, "x-csrf-token", RailsCsrf.masked_token(c.session)),
      delete_req_header(base, "content-length"),
      put_req_header(base, "content-length", "65537"),
      put_req_header(base, "transfer-encoding", "chunked"),
      put_req_header(base, "content-type", "application/json"),
      %{base | req_headers: [{"accept", "text/html"} | base.req_headers]}
    ]

    before = snapshot()

    for input <- invalid do
      result = Http.call(input, c.opts)
      assert result.private[:replayed] and result.halted
      assert_received {:replayed, method, bytes}
      assert method == input.method and bytes == input.private.original_body
      assert snapshot() == before
      assert result.resp_cookies == %{}
      assert get_resp_header(result, "x-dawarich-auth-owner") == []
      refute_received :otp_write
    end

    for options <- [
          Keyword.put(c.opts, :enabled, false),
          Keyword.update!(c.opts, :context, &Map.put(&1, :self_hosted, false)),
          Keyword.update!(c.opts, :context, &Map.put(&1, :oidc, true))
        ] do
      assert Http.call(base, options).private[:replayed]
      assert_received {:replayed, "POST", ^raw}
      assert snapshot() == before
      refute_received :otp_write
    end

    for sql <- [
          "provider='github'",
          "status=3",
          "locked_at=now()",
          "deleted_at=now()",
          "email=''",
          "otp_secret='corrupt'",
          "settings='[]'::jsonb"
        ] do
      Repo.query!("UPDATE users SET #{sql} WHERE id=$1", [@id], log: false)
      before = snapshot()
      assert Http.call(base, c.opts).private[:replayed], sql
      assert_received {:replayed, "POST", ^raw}
      assert snapshot() == before
      refute_received :otp_write

      Repo.query!(
        "UPDATE users SET provider=NULL,status=1,locked_at=NULL,deleted_at=NULL,
        email='a11c-http@dawarich.test',otp_secret=NULL,settings='{}'::jsonb WHERE id=$1",
        [@id],
        log: false
      )
    end

    missing = request(c.session, raw, "POST", @path <> "/verify") |> Http.call(c.opts)
    assert missing.private[:replayed]
    assert_received {:replayed, "POST", ^raw}
    refute_received :otp_write
    {_, adapter_state} = base.adapter
    unreadable = Http.call(%{base | adapter: {Unreadable, adapter_state}}, c.opts)
    assert unreadable.status == 400 and unreadable.halted
    refute_received {:replayed, _, _}
    refute_received :otp_write
    terminal = register_before_send(base, fn _ -> raise "synthetic post-save render failure" end)

    assert_raise RuntimeError, "synthetic post-save render failure", fn ->
      Http.call(terminal, c.opts)
    end

    assert is_binary(Repo.get!(Account, @id).otp_secret)
    assert_received :otp_write
    refute_received {:replayed, _, _}
  end

  defp submit(c, method, path, params, source, effective \\ nil) do
    token = action_token(c.session, effective || method, path)
    params = if source == :body, do: Map.put(params, "authenticity_token", token), else: params
    conn = request(c.session, URI.encode_query(params), method, path)
    conn = if source == :header, do: put_req_header(conn, "x-csrf-token", token), else: conn
    Http.call(conn, c.opts)
  end

  defp action_token(session, method, path) do
    {:ok, csrf} = Base.url_decode64(session["_csrf_token"], padding: false)
    token = :crypto.mac(:hmac, :sha256, csrf, path <> "#" <> String.downcase(method))
    pad = :crypto.strong_rand_bytes(32)
    Base.url_encode64(pad <> :crypto.exor(pad, token), padding: false)
  end

  defp request(session, raw, method \\ "POST", path \\ @path) do
    Plug.Test.conn(method, "http://www.example.com" <> path, raw)
    |> put_private(:original_body, raw)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("accept", "text/html")
    |> Plug.Test.put_req_cookie(
      "_dawarich_session",
      RailsCookies.encrypt(session, "_dawarich_session", @secret)
    )
  end

  defp snapshot do
    [[row]] = Repo.query!("SELECT to_jsonb(users) FROM users WHERE id=$1", [@id], log: false).rows
    row
  end

  defp seed(values),
    do: Repo.get!(Account, @id) |> Ecto.Changeset.change(values) |> Repo.update!(log: false)

  defp assert_identity(result, session) do
    assert get_resp_header(result, "x-dawarich-auth-owner") == ["native-two-factor"]
    assert result.assigns.rails_session == session
    assert Map.keys(result.resp_cookies) == ["_dawarich_session"]
  end
end

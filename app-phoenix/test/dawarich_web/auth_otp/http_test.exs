defmodule DawarichWeb.AuthOtp.HttpTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Repo, RailsCookies, Test.RailsUser}
  alias Dawarich.Auth.{Account, SessionCookie}
  alias Dawarich.Auth.TwoFactor.{Secret, Totp}
  alias DawarichWeb.{AuthOtp.Http, RailsCsrf}
  @now ~U[2026-10-04 12:00:00.000000Z]
  @key "a11d-http-synthetic-cookie-key"
  @otp "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
  @hash Jason.decode!(File.read!("test/fixtures/auth/requests.json"))["login"]["user"][
          "encrypted_password"
        ]
  @crypto Jason.decode!(File.read!("test/fixtures/active_record_encryption.json"))
  @env Enum.find(@crypto["environments"], &(&1["name"] == "explicit keys"))["env"]
  @id 75_550

  defmodule FailedRepo do
    defdelegate one(query, opts), to: Repo
    defdelegate query!(query, params, opts), to: Repo

    def update!(changeset, opts) do
      if Map.has_key?(changeset.changes, :sign_in_count), do: raise("a11d-trackable-terminal")
      Repo.update!(changeset, opts)
    end
  end

  defmodule BrokenBody do
    def read_req_body(_, _opts), do: {:error, :closed}
    defdelegate send_resp(state, status, headers, body), to: Plug.Adapters.Test.Conn
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    old = Map.new(~w(SELF_HOSTED APPLICATION_PROTOCOL RAILS_ENV), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("APPLICATION_PROTOCOL", "http")
    System.put_env("RAILS_ENV", "test")

    on_exit(fn ->
      for {k, v} <- old, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
    end)

    {:ok, cipher} = Secret.encrypt(@otp, @env)

    RailsUser.insert!(%{
      id: @id,
      email: "a11d-http@dawarich.test",
      encrypted_password: @hash,
      otp_secret: cipher,
      otp_required_for_login: true,
      otp_backup_codes: [@hash],
      settings: %{},
      api_key: "A11D_HTTP"
    })

    {session, _} =
      SessionCookie.for_form(
        %{
          "otp_user_id" => @id,
          "otp_challenge_at" => DateTime.to_unix(@now),
          "otp_remember_me" => true,
          "user_return_to" => "/trips"
        },
        @key
      )

    %{session: session, context: %{secret: @key, clock: fn -> @now end, env: @env}}
  end

  defp request(session, raw) do
    Plug.Test.conn("POST", "http://www.example.com/users/otp_challenge", raw)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("accept", "text/html")
    |> Plug.Test.put_req_cookie(
      "_dawarich_session",
      RailsCookies.encrypt(session, "_dawarich_session", @key)
    )
  end

  defp raw(session, code),
    do:
      URI.encode_query(%{
        "otp_attempt" => code,
        "authenticity_token" =>
          RailsCsrf.masked_form_token(session, "/users/otp_challenge", "POST")
      })

  defp snapshot,
    do: Repo.query!("SELECT to_jsonb(u) FROM users u ORDER BY id", [], log: false).rows

  defp seed(values),
    do: Repo.get!(Account, @id) |> Ecto.Changeset.change(values) |> Repo.update!(log: false)

  defp call(conn, context) do
    Http.call(conn,
      enabled: true,
      context: context,
      fallback: fn conn ->
        send(self(), {:replay, conn})
        put_private(conn, :rails_replay, true)
      end
    )
  end

  test "completion HTTP replays refusals byte-identically before every effect", c do
    assert Code.ensure_loaded?(Http)
    valid = raw(c.session, Totp.at(@otp, DateTime.to_unix(@now)))
    initial = request(c.session, valid)
    before = snapshot()
    bad_token = URI.encode_query(%{"otp_attempt" => "123456", "authenticity_token" => "invalid"})

    wrong_path =
      URI.encode_query(%{
        "otp_attempt" => "123456",
        "authenticity_token" => RailsCsrf.masked_form_token(c.session, "/users/sign_in", "POST")
      })

    refusals = [
      request(c.session, raw(c.session, "not-a-code")),
      request(c.session, bad_token),
      request(c.session, wrong_path),
      request(c.session, valid <> "&otp_attempt=duplicate"),
      request(c.session, valid <> "&_method=post"),
      request(c.session, valid <> "&otp_attempt%5Bx%5D=1"),
      request(c.session, valid <> "&commit=%GG"),
      request(c.session, valid <> "&commit=%FF"),
      request(c.session, valid <> "&otp_attempt=%00"),
      %{initial | method: "GET"},
      %{initial | query_string: "format=html"},
      put_req_header(initial, "origin", "https://foreign.invalid"),
      put_req_header(initial, "x-requested-with", "XMLHttpRequest"),
      put_req_header(initial, "accept", "text/vnd.turbo-stream.html"),
      put_req_header(initial, "accept", "application/json"),
      put_req_header(initial, "accept", "text/plain"),
      put_req_header(initial, "accept", "text/html;q=0"),
      put_req_header(initial, "content-type", "application/json"),
      put_req_header(initial, "x-http-method-override", "POST"),
      put_req_header(initial, "x-dawarich-client", "mobile"),
      put_req_header(initial, "x-forwarded-for", "127.0.0.1"),
      put_req_header(initial, "forwarded", "for=127.0.0.1"),
      request(Map.put(c.session, "pending_import_ticket", "synthetic"), valid),
      request(Map.put(c.session, "otp_challenge_at", "malformed"), valid),
      request(Map.put(c.session, "otp_remember_me", "1"), valid),
      Plug.Test.put_req_cookie(
        initial,
        "remember_user_token",
        RailsCookies.sign(
          [[@id], binary_part(@hash, 0, 29), Dawarich.Accounts.remember_generated_at(@now)],
          "remember_user_token",
          @key,
          DateTime.add(@now, 3600)
        )
      ),
      delete_req_header(initial, "content-length"),
      put_req_header(initial, "content-length", "65537"),
      put_req_header(initial, "transfer-encoding", "chunked"),
      %{
        initial
        | req_headers: [{"x-csrf-token", "x"}, {"x-csrf-token", "y"} | initial.req_headers]
      },
      request(Map.put(c.session, "user_return_to", "//foreign.invalid"), valid),
      request(Map.put(c.session, "invitation_token", "synthetic"), valid),
      request(
        Map.put(c.session, "warden.user.user.key", [[@id], binary_part(@hash, 0, 29)]),
        valid
      ),
      Plug.Test.put_req_cookie(initial, "_dawarich_session", "malformed")
    ]

    for conn <- refusals do
      response = call(conn, c.context)
      assert response.private[:rails_replay] and response.halted
      assert_receive {:replay, seen}
      assert seen.method == conn.method and seen.query_string == conn.query_string
      cookie_equal = get_req_header(seen, "cookie") == get_req_header(conn, "cookie")
      assert cookie_equal
      {_, state} = conn.adapter
      expected = state.req_body
      replayed = seen.private[:dawarich_raw_body] || elem(Plug.Conn.read_body(seen), 1)
      assert replayed == expected
      unchanged = snapshot() == before
      assert unchanged
      assert response.resp_cookies == %{}
    end

    for values <- [
          [consumed_timestep: div(DateTime.to_unix(@now), 30)],
          [otp_locked_at: DateTime.add(@now, -60)],
          [locked_at: DateTime.add(@now, -60)],
          [provider: "github"],
          [status: 3],
          [deleted_at: @now],
          [settings: %{"maps" => 1}]
        ] do
      user = Repo.get!(Account, @id)
      [[settings]] = Repo.query!("SELECT settings FROM users WHERE id=$1", [@id], log: false).rows
      user = %{user | settings: settings}
      seed(values)
      state = snapshot()
      replayed = call(initial, c.context).private[:rails_replay]
      assert replayed
      assert_receive {:replay, _}
      unchanged = snapshot() == state
      assert unchanged
      seed(Map.new(values, fn {k, _} -> {k, Map.fetch!(user, k)} end))
    end

    assert call(initial, %{c.context | env: %{}}).private[:rails_replay]
    assert_receive {:replay, _}
    broken = %{initial | adapter: {BrokenBody, elem(initial.adapter, 1)}}
    assert %{status: 400, halted: true} = call(broken, c.context)
    refute_received {:replay, _}
    unchanged = snapshot() == before
    assert unchanged
    expired = Map.put(c.session, "otp_challenge_at", DateTime.to_unix(@now) - 300)
    assert %{status: 302} = call(request(expired, raw(expired, "invalid")), c.context)
    unchanged = snapshot() == before
    assert unchanged
    response = call(initial, c.context)

    assert response.status == 302 and
             get_resp_header(response, "x-dawarich-auth-owner") == ["native-otp"]

    assert get_resp_header(response, "location") == ["http://www.example.com/trips"]

    {:ok, completed} =
      RailsCookies.decrypt(
        response.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        @key,
        @now
      )

    assert completed["otp_user_id"] == nil and completed["warden.user.user.key"] != nil
    assert Map.has_key?(response.resp_cookies, "remember_user_token")
    assert Repo.get!(Account, @id).sign_in_count == 1
    replayed = call(initial, c.context).private[:rails_replay]
    assert replayed
    assert_receive {:replay, _}
    seed(otp_locked_at: DateTime.add(@now, -60), failed_otp_attempts: 10)
    assert call(request(c.session, raw(c.session, "safepassword12")), c.context).status == 302
    assert Repo.get!(Account, @id).otp_backup_codes == []
    seed(consumed_timestep: nil, sign_in_count: 0)

    assert_raise RuntimeError, "a11d-trackable-terminal", fn ->
      call(initial, Map.put(c.context, :repo, FailedRepo))
    end

    refute_received {:replay, _}
    assert Repo.get!(Account, @id).consumed_timestep != nil
    assert Repo.get!(Account, @id).sign_in_count == 0
  end
end

defmodule DawarichWeb.AuthAccountLink.HttpTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Repo, ScratchRepo, State, RailsCookies, Test.RailsUser}
  alias Dawarich.Auth.{Account, SessionCookie}
  alias DawarichWeb.{AuthAccountLink.Http, RailsCsrf, RateLimit.Rules}
  @now ~U[2026-10-05 12:00:00.000000Z]
  @key "a11e-http-synthetic-cookie-key"
  @id 911_453_001
  @source "test/fixtures/auth/account_link/requests.json" |> File.read!() |> Jason.decode!()

  defmodule FailedRepo do
    defdelegate one(query, opts), to: Repo
    defdelegate query!(query, params, opts), to: Repo

    def update!(changeset, opts) do
      if Map.has_key?(changeset.changes, :sign_in_count), do: raise("a11e-terminal-callback")
      Repo.update!(changeset, opts)
    end
  end

  defmodule PartialRepo do
    def query!(_sql, [key, by, _ttl], _opts) when by == -1,
      do: raise(DBConnection.ConnectionError, key)

    def query!(sql, [key, 1, ttl] = params, opts) do
      if String.contains?(key, "challenge_ip"), do: raise(DBConnection.ConnectionError, "down")
      ScratchRepo.query!(sql, [hd(params), 1, ttl], opts)
    end
  end

  defmodule FirstFailedRepo do
    def query!(sql, [key, 1, ttl], opts) do
      if String.contains?(key, "challenge_session"),
        do: raise(DBConnection.ConnectionError, "a11e-session-down")

      ScratchRepo.query!(sql, [key, 1, ttl], opts)
    end
  end

  defmodule BrokenBody do
    def read_req_body(_, _opts), do: {:error, :closed}
    defdelegate send_resp(state, status, headers, body), to: Plug.Adapters.Test.Conn
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    old = Map.new(~w(SELF_HOSTED APPLICATION_PROTOCOL RAILS_ENV), &{&1, System.get_env(&1)})
    secret = Application.get_env(:dawarich, :rails_secret)
    System.put_env("SELF_HOSTED", "true")
    System.put_env("APPLICATION_PROTOCOL", "http")
    System.put_env("RAILS_ENV", "test")
    Application.put_env(:dawarich, :rails_secret, @key)

    on_exit(fn ->
      for {k, v} <- old, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
      Application.put_env(:dawarich, :rails_secret, secret)
    end)

    RailsUser.insert!(%{
      id: @id,
      email: "a11e-http@example.invalid",
      encrypted_password: @source["challenge_en"]["before"]["encrypted_password"],
      settings: %{},
      api_key: "A11E_HTTP",
      provider: nil,
      uid: nil
    })

    session =
      @source["challenge_en"]["session"]
      |> put_in(["pending_oauth_link", "user_id"], @id)
      |> put_in(["pending_oauth_link", "uid"], "a11e-http-target")

    {session, _} = SessionCookie.for_form(Map.drop(session, ~w(session_id _csrf_token)), @key)

    keys =
      for delta <- [0, 900],
          {name, value} <- [
            {"auth/account_link_challenge_session", @id},
            {"auth/account_link_challenge_ip", "198.51.100.233"}
          ],
          do: Rules.key(DateTime.to_unix(@now) + delta, 900, name, value)

    for key <- keys do
      assert State.count(ScratchRepo, key) == 0
    end

    on_exit(fn ->
      for key <- keys,
          do: ScratchRepo.query!("DELETE FROM phoenix.counters WHERE key=$1", [key], log: false)
    end)

    %{
      session: session,
      context: %{
        secret: @key,
        clock: fn -> @now end,
        rate_now: DateTime.to_unix(@now),
        rate_repo: ScratchRepo
      }
    }
  end

  defp request(session, raw, method \\ "POST") do
    Plug.Test.conn(method, "http://www.example.com/auth/account_link/challenge", raw)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("accept", "text/html")
    |> Plug.Test.put_req_cookie(
      "_dawarich_session",
      RailsCookies.encrypt(session, "_dawarich_session", @key)
    )
    |> Map.put(:remote_ip, {198, 51, 100, 233})
  end

  defp raw(session, password \\ "safepassword12"),
    do:
      URI.encode_query(%{
        "password" => password,
        "authenticity_token" =>
          RailsCsrf.masked_form_token(session, "/auth/account_link/challenge", "POST")
      })

  defp snapshot,
    do: Repo.query!("SELECT to_jsonb(u) FROM users u ORDER BY id", [], log: false).rows

  defp seed(values),
    do: Repo.get!(Account, @id) |> Ecto.Changeset.change(values) |> Repo.update!(log: false)

  defp call(conn, context),
    do:
      Http.call(conn,
        enabled: true,
        context: context,
        fallback: fn conn ->
          send(self(), {:replay, conn})
          put_private(conn, :rails_replay, true)
        end
      )

  test "account-link HTTP claims only trusted pending GET and CSRF-valid correct-password POST",
       c do
    assert Code.ensure_loaded?(Http)
    valid = raw(c.session)
    initial = request(c.session, valid)
    before = snapshot()

    invalid =
      URI.encode_query(%{"password" => "safepassword12", "authenticity_token" => "invalid"})

    wrong_action =
      URI.encode_query(%{
        "password" => "safepassword12",
        "authenticity_token" =>
          RailsCsrf.masked_form_token(c.session, "/auth/account_link/email", "POST")
      })

    refusals = [
      request(c.session, raw(c.session, "wrong")),
      request(c.session, raw(c.session, "")),
      request(c.session, "password=safepassword12"),
      request(c.session, invalid),
      request(c.session, wrong_action),
      request(c.session, valid <> "&password=duplicate"),
      request(c.session, valid <> "&_method=post"),
      request(c.session, valid <> "&password[x]=1"),
      request(c.session, valid <> "&commit=%GG"),
      request(c.session, valid <> "&commit=%FF"),
      request(c.session, valid <> "&extra=1"),
      %{initial | method: "HEAD"},
      %{initial | query_string: "format=html"},
      put_req_header(initial, "origin", "https://foreign.invalid"),
      put_req_header(initial, "x-requested-with", "XMLHttpRequest"),
      put_req_header(initial, "accept", "text/vnd.turbo-stream.html"),
      put_req_header(initial, "accept", "application/json"),
      put_req_header(initial, "accept", "text/html;q=0"),
      put_req_header(initial, "content-type", "multipart/form-data"),
      put_req_header(initial, "x-http-method-override", "POST"),
      put_req_header(initial, "x-dawarich-client", "mobile"),
      put_req_header(initial, "x-forwarded-for", "127.0.0.1"),
      delete_req_header(initial, "content-length"),
      put_req_header(initial, "content-length", "65537"),
      put_req_header(initial, "transfer-encoding", "chunked"),
      %{initial | req_headers: [{"accept", "text/html"} | initial.req_headers]},
      Plug.Test.put_req_cookie(initial, "_dawarich_session", "malformed"),
      put_req_header(
        initial,
        "cookie",
        hd(get_req_header(initial, "cookie")) <> "; _dawarich_session=other"
      ),
      Plug.Test.put_req_cookie(initial, "remember_user_token", "malformed")
    ]

    sessions = [
      Map.put(c.session, "invitation_token", "synthetic"),
      Map.put(c.session, "otp_user_id", @id),
      Map.put(c.session, "warden.user.user.key", [[@id], "synthetic"]),
      put_in(c.session, ["pending_oauth_link", "provider"], "github"),
      put_in(c.session, ["pending_oauth_link", "expires_at"], DateTime.to_unix(@now) - 1),
      put_in(c.session, ["pending_oauth_link", "user_id"], @id + 1)
    ]

    for conn <- refusals ++ Enum.map(sessions, &request(&1, raw(&1))) do
      response = call(conn, c.context)
      assert response.private[:rails_replay] == true and response.halted
      assert_receive {:replay, seen}
      assert seen.method == conn.method and seen.query_string == conn.query_string
      assert get_req_header(seen, "cookie") == get_req_header(conn, "cookie")

      assert (seen.private[:dawarich_raw_body] || elem(read_body(seen), 1)) ==
               elem(conn.adapter, 1).req_body

      assert snapshot() == before
      assert response.resp_cookies == %{}
    end

    for changes <- [
          [provider: "github"],
          [uid: "linked"],
          [status: 3],
          [locked_at: @now],
          [deleted_at: @now],
          [settings: %{"maps" => 1}]
        ] do
      user = Repo.get!(Account, @id)
      [[settings]] = Repo.query!("SELECT settings FROM users WHERE id=$1", [@id], log: false).rows
      user = %{user | settings: settings}
      seed(changes)
      changed = snapshot()
      assert call(initial, c.context).private[:rails_replay]
      assert_receive {:replay, _}
      assert snapshot() == changed
      seed(Map.new(changes, fn {k, _} -> {k, Map.fetch!(user, k)} end))
    end

    for path <-
          ~w(/auth/account_link /auth/account_link/email /users/auth/openid_connect /users/auth/openid_connect/callback) do
      refute Http.route?(%{initial | request_path: path})
    end

    broken = call(%{initial | adapter: {BrokenBody, elem(initial.adapter, 1)}}, c.context)
    assert broken.status == 400 and broken.halted
    refute_received {:replay, _}
    get = call(request(c.session, "", "GET"), c.context)

    assert get.status == 200 and
             get_resp_header(get, "x-dawarich-auth-owner") == ["native-account-link"]

    assert snapshot() == before
    seed(otp_required_for_login: true)
    assert call(initial, c.context).status == 302
    assert Repo.get!(Account, @id).sign_in_count == 0
    seed(provider: nil, uid: nil, otp_required_for_login: false)

    assert_raise RuntimeError, "a11e-terminal-callback", fn ->
      call(initial, Map.put(c.context, :repo, FailedRepo))
    end

    refute_received {:replay, _}
    assert Repo.get!(Account, @id).provider == "openid_connect"
  end

  test "pending GET hands non-string flash alerts to Rails before consuming session state", c do
    before = snapshot()

    for alert <- [0, true] do
      session = Map.put(c.session, "flash", %{"discard" => [], "flashes" => %{"alert" => alert}})
      conn = request(session, "", "GET")
      response = call(conn, c.context)
      assert response.private[:rails_replay] == true and response.halted
      assert_receive {:replay, seen}
      assert get_req_header(seen, "cookie") == get_req_header(conn, "cookie")
      assert seen.assigns.rails_session == session
      refute Map.has_key?(seen.assigns, :flash_messages)
      assert response.resp_cookies == %{}
      assert get_resp_header(response, "x-dawarich-auth-owner") == []
      assert snapshot() == before
    end

    session = Map.put(c.session, "flash", %{"discard" => [], "flashes" => %{"alert" => "retry"}})
    response = call(request(session, "", "GET"), c.context)
    assert response.status == 200
    assert get_resp_header(response, "x-dawarich-auth-owner") == ["native-account-link"]
    refute_received {:replay, _}
    assert snapshot() == before
  end

  test "first account-link counter failure hands unchanged bytes to Rails for its healthy IP limit",
       c do
    body = raw(c.session)
    conn = request(c.session, body)

    ip_key =
      Rules.key(c.context.rate_now, 900, "auth/account_link_challenge_ip", "198.51.100.233")

    State.increment(ScratchRepo, ip_key, 20, 901)
    before = snapshot()

    response =
      Http.call(conn,
        enabled: true,
        context: %{c.context | rate_repo: FirstFailedRepo},
        fallback: fn handed ->
          assert handed.private.dawarich_rate_limit == []
          assert handed.private.dawarich_raw_body == body
          assert get_req_header(handed, "cookie") == get_req_header(conn, "cookie")
          assert State.count(ScratchRepo, ip_key) == 20
          assert snapshot() == before
          assert State.increment(ScratchRepo, ip_key, 1, 901) == 21
          DawarichWeb.RateLimit.throttled(handed, %{period: 900}, c.context.rate_now, nil)
        end
      )

    assert response.status == 429 and response.resp_cookies == %{}
    assert get_resp_header(response, "x-dawarich-auth-owner") == []
    assert State.count(ScratchRepo, ip_key) == 21
    assert snapshot() == before
  end

  test "account-link success and fallback share source fixed-window counts without double counting",
       c do
    assert Code.ensure_loaded?(Http)
    conn = request(c.session, raw(c.session))
    session_key = Rules.key(c.context.rate_now, 900, "auth/account_link_challenge_session", @id)

    ip_key =
      Rules.key(c.context.rate_now, 900, "auth/account_link_challenge_ip", "198.51.100.233")

    wrong = call(request(c.session, raw(c.session, "wrong")), c.context)
    assert wrong.private[:rails_replay]
    assert_receive {:replay, _}
    assert State.count(ScratchRepo, session_key) == 0

    for n <- 1..5 do
      seed(provider: nil, uid: nil)
      assert call(conn, c.context).status == 302
      assert State.count(ScratchRepo, session_key) == n
      assert State.count(ScratchRepo, ip_key) == n
    end

    seed(provider: nil, uid: nil)
    before = snapshot()
    denied = call(conn, c.context)
    assert denied.status == 429
    assert Jason.decode!(denied.resp_body)["error"] == "rate_limit_exceeded"
    assert get_resp_header(denied, "retry-after") == ["900"]
    assert get_resp_header(denied, "cache-control") == ["no-store", "no-cache"]
    assert denied.resp_cookies == %{} and snapshot() == before
    assert State.count(ScratchRepo, session_key) == 6
    assert State.count(ScratchRepo, ip_key) == 5
    edge = %{c.context | rate_now: c.context.rate_now + 900}
    assert call(conn, edge).status == 302
    seed(provider: nil, uid: nil)
    edge_session = Rules.key(edge.rate_now, 900, "auth/account_link_challenge_session", @id)
    edge_ip = Rules.key(edge.rate_now, 900, "auth/account_link_challenge_ip", "198.51.100.233")
    State.increment(ScratchRepo, edge_ip, 19, 901)
    denied = call(conn, edge)
    assert denied.status == 429 and denied.resp_cookies == %{}
    assert State.count(ScratchRepo, edge_session) == 2
    assert State.count(ScratchRepo, edge_ip) == 21
    seed(provider: nil, uid: nil)
    State.increment(ScratchRepo, session_key, -6, 901)
    response = call(conn, %{c.context | rate_repo: PartialRepo})
    assert response.status == 302
    refute_received {:replay, _}
    assert response.private.dawarich_rate_limit == [{session_key, 901}]
    assert State.count(ScratchRepo, session_key) == 1
    assert Repo.get!(Account, @id).sign_in_count == 7
  end
end

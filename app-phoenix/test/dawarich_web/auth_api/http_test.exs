defmodule DawarichWeb.AuthApi.HttpTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import ExUnit.CaptureLog
  import Dawarich.Test.RawHTTP
  alias Dawarich.Auth.{Account, Api.ChallengeToken}
  alias Dawarich.Auth.TwoFactor.{Secret, Totp}
  alias Dawarich.{RailsCookies, RailsSecret, Redis, Repo, Test.RailsUser}
  alias DawarichWeb.AuthApi.Http
  @now ~U[2026-10-04 12:00:00.000000Z]
  @otp "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
  @hash Jason.decode!(File.read!("test/fixtures/auth/requests.json"))["login"]["user"][
          "encrypted_password"
        ]
  @crypto Jason.decode!(File.read!("test/fixtures/active_record_encryption.json"))
  @env Enum.find(@crypto["environments"], &(&1["name"] == "explicit keys"))["env"]
  @id 75_1010

  defmodule FailedRepo do
    defdelegate one(query, opts), to: Repo
    defdelegate query!(query, params, opts), to: Repo

    def update!(changeset, opts) do
      if Map.has_key?(changeset.changes, :failed_otp_attempts), do: raise("a11f-reset-terminal")
      Repo.update!(changeset, opts)
    end
  end

  defmodule BrokenBody do
    def read_req_body(_, _), do: {:error, :closed}
    defdelegate send_resp(state, status, headers, body), to: Plug.Adapters.Test.Conn
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    prior_level = Logger.level()
    Logger.configure(level: :info)
    for spec <- Redis.cache_child_specs(), do: start_supervised!(spec)
    old = Map.new(~w(SELF_HOSTED APPLICATION_PROTOCOL RAILS_ENV), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("APPLICATION_PROTOCOL", "http")
    System.put_env("RAILS_ENV", "test")
    upstream = listen()
    prior_upstream = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    jti = Ecto.UUID.generate()
    key = "otp_challenge:consumed:" <> jti

    on_exit(fn ->
      Logger.configure(level: prior_level)

      for {name, value} <- old,
          do: if(value, do: System.put_env(name, value), else: System.delete_env(name))

      Application.put_env(:dawarich, :rails_upstream, prior_upstream)
      :gen_tcp.close(upstream.listen)
      config = Application.fetch_env!(:dawarich, :redis)
      {:ok, conn} = Redix.start_link(config[:url], database: config[:cache_database])
      Redix.command(conn, ["DEL", key])
      GenServer.stop(conn)
    end)

    {:ok, cipher} = Secret.encrypt(@otp, @env)

    RailsUser.insert!(%{
      id: @id,
      email: "a11f-http@example.invalid",
      encrypted_password: @hash,
      otp_secret: cipher,
      otp_required_for_login: false,
      otp_backup_codes: [@hash],
      subscription_source: 0,
      active_until: nil,
      failed_attempts: 7,
      failed_otp_attempts: 3,
      settings: %{},
      api_key: "a11f-http-api-key-sentinel"
    })

    context = %{
      self_hosted: true,
      oidc: false,
      timezone: "Etc/UTC",
      env:
        Map.put(
          @env,
          "JWT_SECRET_KEY",
          Dawarich.Auth.TwoFactor.Totp.generate_secret("a11f signing fixture")
        ),
      clock: fn -> @now end,
      jti: fn -> jti end
    }

    {:ok, token} = ChallengeToken.issue(@id, context)
    %{context: context, token: token, key: key, upstream: upstream}
  end

  test "API auth HTTP owns supported successes and hands every refusal back before effects", c do
    original = login()
    before = snapshot()
    response = call(original, c.context)
    assert response.status == 200 and response.halted
    assert get_resp_header(response, "x-dawarich-auth-owner") == ["native-api-auth"]
    assert Jason.decode!(response.resp_body)["user_id"] == @id
    assert snapshot() == before
    assert response.resp_cookies == %{}
    assert Http.route?(original)
    refute Http.route?(%{original | method: "GET"})

    for conn <- [
          login("wrong"),
          login(nil),
          login("wrong" <> <<0>> <> "suffix"),
          login("safepassword12" <> <<0>> <> "suffix"),
          request(:login, %{"email" => "missing@example.invalid", "password" => "safepassword12"}),
          %{original | method: "GET"},
          %{original | request_path: "/api/v1/auth/login/"},
          %{original | request_path: "/api/v1/auth/login.json"},
          %{original | query_string: "client=ios"},
          request(:login, %{
            "email" => "a11f-http@example.invalid",
            "password" => "safepassword12",
            "extra" => "x"
          }),
          request(
            :login,
            ~s({"email":"a11f-http@example.invalid","password":"safepassword12","email":"duplicate"})
          ),
          put_req_header(original, "x-dawarich-client", "ios"),
          put_req_header(original, "x-dawarich-client", "android"),
          put_req_header(original, "x-requested-with", "XMLHttpRequest"),
          put_req_header(original, "content-length", "16385"),
          put_req_header(original, "transfer-encoding", "chunked")
        ] do
      assert_replay(conn, c.context, before)
    end

    assert_replay(original, %{c.context | self_hosted: false}, before)
    assert_replay(original, %{c.context | oidc: true}, before)
    response = Http.call(original, enabled: false, context: c.context, fallback: &fallback/1)
    assert response.private[:rails_replay]
    assert_receive {:replay, _}
    assert snapshot() == before

    for changes <- [
          %{provider: "openid_connect"},
          %{deleted_at: @now},
          %{settings: %{"maps" => 1}}
        ] do
      actor = Repo.get!(Account, @id)
      seed(changes)
      state = snapshot()
      assert_replay(original, c.context, state)
      seed(Map.take(Map.from_struct(actor), Map.keys(changes)))
    end

    seed(%{settings: %{}, otp_required_for_login: true})
    state = snapshot()
    assert_replay(original, %{c.context | env: %{}}, state)
    response = call(original, c.context)
    assert response.status == 202
    fields = Jason.decode!(response.resp_body)
    assert fields["challenge_token"] == c.token
    refute Map.has_key?(fields, "api_key")
    assert snapshot() == state

    for {token, code} <- [{"invalid", "012345"}, {c.token, "invalid"}, {c.token, nil}] do
      assert_replay(challenge(token, code), c.context, state)
    end

    code = Totp.at(@otp, DateTime.to_unix(@now))
    request = challenge(c.token, code)
    broken = %{request | adapter: {BrokenBody, elem(request.adapter, 1)}}
    assert %{status: 400, halted: true} = call(broken, c.context)
    refute_received {:replay, _}
    assert call(request, c.context).status == 200
    assert Repo.get!(Account, @id).failed_otp_attempts == 0
    assert Repo.get!(Account, @id).sign_in_count == 0

    assert_replay(
      challenge(c.token, Totp.at(@otp, DateTime.to_unix(@now) + 30)),
      c.context,
      snapshot()
    )

    reset(c.key)
    seed(%{otp_locked_at: DateTime.add(@now, -60), failed_otp_attempts: 10})
    assert call(challenge(c.token, "safepassword12"), c.context).status == 200
    assert Repo.get!(Account, @id).otp_backup_codes == []
    reset(c.key)

    assert_raise RuntimeError, "a11f-reset-terminal", fn ->
      call(request, Map.put(c.context, :repo, FailedRepo))
    end

    refute_received {:replay, _}
    assert Repo.get!(Account, @id).consumed_timestep == div(DateTime.to_unix(@now), 30)
    assert Repo.get!(Account, @id).failed_otp_attempts == 3
    assert {:ok, bytes} = Redis.cache_command(["GET", c.key])
    assert is_binary(bytes)
  end

  test "API auth HTTP initializes API framing for untouched endpoint success and fallback conns",
       c do
    assert call(login(), c.context).assigns.api_tag == "api"

    for conn <- [
          request(:login, "{"),
          put_req_header(login(), "accept", "application/xml, text/html")
        ] do
      before = snapshot()

      logs =
        capture_log([level: :info], fn ->
          result = proxied(conn, c)
          assert result.status == 209 and result.halted
          assert result.assigns.api_tag == "api"
        end)

      assert String.contains?(logs, "[api]")
      assert snapshot() == before
    end
  end

  test "API OTP challenge NUL inputs preserve original replay bytes without effects", c do
    seed(%{otp_required_for_login: true})
    before = snapshot()

    context =
      c.context
      |> Map.put(:repo, :must_not_load_actor)
      |> Map.put(:cache_command, fn _ -> raise "NUL HTTP challenge reached cache" end)

    for {token, code} <- [
          {c.token, "wrong" <> <<0>> <> "suffix"},
          {c.token, "safepassword12" <> <<0>> <> "suffix"},
          {c.token <> <<0>> <> "suffix", "safepassword12"}
        ] do
      assert_replay(challenge(token, code), context, before)

      form =
        request(:challenge, URI.encode_query(%{"challenge_token" => token, "otp_code" => code}))
        |> put_req_header("content-type", "application/x-www-form-urlencoded")

      assert_replay(form, context, before)
    end
  end

  test "API auth replays all session and remember cookies without credential or OTP effects", c do
    seed(%{otp_required_for_login: true})
    code = Totp.at(@otp, DateTime.to_unix(@now))

    sessions = [
      %{},
      %{"session_id" => "a11f-anonymous"},
      %{"invitation_token" => "synthetic"},
      %{"pending_import_ticket" => "synthetic"},
      %{"dawarich_client" => "ios"},
      %{"otp_user_id" => @id},
      %{"otp_challenge_at" => DateTime.to_unix(@now)},
      %{"otp_remember_me" => true},
      %{"otp_failed_attempts" => 2},
      %{
        "pending_oauth_link" => %{
          "user_id" => @id,
          "provider" => "google",
          "uid" => "synthetic",
          "issued_at" => DateTime.to_unix(@now)
        }
      },
      %{"pending_oauth_link_attempts" => 2},
      %{"warden.user.user.key" => [[@id], binary_part(@hash, 0, 29)]}
    ]

    for initial <- [login(), challenge(c.token, code)], session <- sessions do
      before = snapshot()
      cookie = RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())
      conn = Plug.Test.put_req_cookie(initial, "_dawarich_session", cookie)
      assert_replay(conn, c.context, before)
      assert {:ok, nil} = Redis.cache_command(["GET", c.key])
    end

    conn = Plug.Test.put_req_cookie(login(), "remember_user_token", "synthetic")
    assert_replay(conn, c.context, snapshot())
  end

  test "API auth captured logs exclude synthetic credentials on success replay and post-write error",
       c do
    previous = Logger.level()
    Logger.configure(level: :debug)

    try do
      logs =
        capture_log([level: :debug], fn ->
          assert call(login(), c.context).status == 200
          assert_replay(login("a11f-password-log-sentinel"), c.context, snapshot())
          seed(%{otp_required_for_login: true})
          assert call(login(), c.context).status == 202
          request = challenge(c.token, Totp.at(@otp, DateTime.to_unix(@now)))

          assert_raise RuntimeError, "a11f-reset-terminal", fn ->
            call(request, Map.put(c.context, :repo, FailedRepo))
          end

          refute_received {:replay, _}
        end)

      for value <- [
            "safepassword12",
            "a11f-password-log-sentinel",
            c.token,
            Totp.at(@otp, DateTime.to_unix(@now)),
            "a11f-http-api-key-sentinel"
          ] do
        refute String.contains?(logs, value)
      end
    after
      Logger.configure(level: previous)
    end
  end

  defp login(password \\ "safepassword12"),
    do: request(:login, %{"email" => "a11f-http@example.invalid", "password" => password})

  defp challenge(token, code),
    do: request(:challenge, %{"challenge_token" => token, "otp_code" => code})

  defp request(action, body) do
    raw = if is_map(body), do: Jason.encode!(body), else: body
    path = if action == :login, do: "/api/v1/auth/login", else: "/api/v1/auth/otp_challenge"

    Plug.Test.conn("POST", "http://localhost" <> path, raw)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("accept", "application/json")
  end

  defp fallback(conn) do
    send(self(), {:replay, conn})
    put_private(conn, :rails_replay, true)
  end

  defp call(conn, context),
    do: Http.call(conn, enabled: true, context: context, fallback: &fallback/1)

  defp assert_replay(conn, context, before) do
    result = call(conn, context)
    assert result.private[:rails_replay] and result.halted
    assert_receive {:replay, seen}
    assert seen.method == conn.method and seen.query_string == conn.query_string
    assert seen.req_headers == conn.req_headers
    raw = seen.private[:dawarich_raw_body] || elem(read_body(seen), 1)
    assert raw == elem(conn.adapter, 1).req_body
    unchanged = snapshot() == before
    assert unchanged
    assert result.resp_cookies == %{}
  end

  defp proxied(conn, c) do
    expected = elem(conn.adapter, 1).req_body

    peer =
      Task.async(fn ->
        socket = accept(c.upstream)
        {head, rest} = read_head(socket)

        raw =
          binary_part(read_at_least(socket, rest, byte_size(expected)), 0, byte_size(expected))

        assert raw == expected
        reply(socket, "HTTP/1.1 209 Source\r\nContent-Length: 4\r\n\r\npuma")
        :gen_tcp.close(socket)
        request_line(head)
      end)

    result = Http.call(conn, enabled: true, context: c.context)
    assert Task.await(peer) == "POST /api/v1/auth/login HTTP/1.1"
    result
  end

  defp snapshot,
    do: Repo.query!("SELECT to_jsonb(u) FROM users u ORDER BY id", [], log: false).rows

  defp seed(changes),
    do: Repo.get!(Account, @id) |> Ecto.Changeset.change(changes) |> Repo.update!(log: false)

  defp reset(key) do
    seed(%{
      consumed_timestep: nil,
      otp_locked_at: nil,
      failed_otp_attempts: 3,
      otp_backup_codes: [@hash]
    })

    Redis.cache_command(["DEL", key])
  end
end

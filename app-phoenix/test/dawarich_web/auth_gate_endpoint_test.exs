defmodule DawarichWeb.AuthGateEndpointTest do
  use Dawarich.IngestCase, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP

  alias Dawarich.{RailsCookies, RailsSecret}
  alias DawarichWeb.RailsCsrf

  @hash Jason.decode!(File.read!(Path.expand("../fixtures/auth/requests.json", __DIR__)))[
          "user_before"
        ]["encrypted_password"]
  @env ~w(SELF_HOSTED DAWARICH_RAILS_SLICES APPLICATION_PROTOCOL RAILS_ENV RACK_ENV OIDC_CLIENT_ID OIDC_CLIENT_SECRET
          OIDC_PKCE_ENABLED GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET)

  defmodule CommittedEndpoint do
    def init(opts), do: DawarichWeb.Endpoint.init(opts)

    def call(conn, opts) do
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Dawarich.Repo, fn ->
        Process.put(:a11e_request_index, Plug.Conn.get_req_header(conn, "x-request-id"))
        DawarichWeb.Endpoint.call(conn, opts)
      end)
    end
  end

  defmodule BarrierRepo do
    import ExUnit.Assertions
    alias Dawarich.Repo
    defdelegate one(query, opts), to: Repo
    defdelegate query!(sql, params, opts), to: Repo

    def update!(changeset, opts) do
      if Map.has_key?(changeset.changes, :provider) do
        [[backend]] = Repo.query!("SELECT pg_backend_pid()", [], log: false).rows
        visible = Repo.get!(Dawarich.Auth.Account, changeset.data.id)
        refute Repo.in_transaction?()

        send(
          Application.fetch_env!(:dawarich, :a11e_overlap_owner),
          {:http_prepared, Process.get(:a11e_request_index), self(), backend, visible.provider,
           changeset.data.sign_in_count}
        )

        receive do
          {:save, index} -> Process.put(:a11e_overlap_index, index)
        end
      end

      Repo.update!(changeset, opts)
    end
  end

  setup context do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    Dawarich.State.put_registration_enabled(Repo, false)
    previous = Map.new(@env, &{&1, System.get_env(&1)})
    Enum.each(@env, &System.delete_env/1)
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, nil)
      Application.delete_env(:dawarich, :phoenix_auth)

      for {name, value} <- previous,
          do: if(value, do: System.put_env(name, value), else: System.delete_env(name))
    end)

    bandit =
      start_supervised!(
        {Bandit,
         [
           plug:
             if(context[:account_link_committed],
               do: CommittedEndpoint,
               else: DawarichWeb.Endpoint
             )
         ] ++
           Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    %{port: port, upstream: upstream}
  end

  defp registration(name),
    do:
      Dawarich.State.put_registration_enabled(
        Repo,
        %{"true" => true, "false" => false, "nil" => nil}[name]
      )

  defp guest do
    session = %{"session_id" => "a11a-guest", "_csrf_token" => RailsCsrf.new_token()}

    {session,
     "_dawarich_session=" <>
       RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())}
  end

  defp get(path), do: "GET #{path} HTTP/1.1\r\nHost: a\r\n\r\n"

  defp form(method, path, cookie, body, extra \\ "") do
    "#{method} #{path} HTTP/1.1\r\nHost: a\r\nCookie: #{cookie}\r\n#{extra}" <>
      "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}"
  end

  defp exchange(ctx, request) do
    client = connect(ctx.port)
    send_raw(client, request)
    read_response(client)
  end

  defp to_puma(ctx, request) do
    client = connect(ctx.port)
    send_raw(client, request)
    puma = accept(ctx.upstream)
    {head, rest} = read_head(puma)
    length = head |> header("content-length") |> List.first("0") |> String.to_integer()
    body = binary_part(read_at_least(puma, rest, length), 0, length)
    reply(puma, "HTTP/1.1 200 OK\r\nSet-Cookie: rails=1; path=/\r\nContent-Length: 4\r\n\r\npuma")
    {status, headers, answer} = read_response(client)

    %{
      line: request_line(head),
      cookie: header(head, "cookie"),
      body: body,
      response:
        {status, values(headers, "set-cookie"), values(headers, "x-dawarich-auth-owner"), answer}
    }
  end

  defp no_puma(ctx), do: assert({:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 200))

  @tag account_link_committed: true, api_public_only: true
  test "independent native Endpoint confirmations match the Rails overlap oracle and OFF forwarding",
       ctx do
    source = Jason.decode!(File.read!("test/fixtures/auth/account_link/requests.json"))
    id = 911_457_001
    email = "a11e-endpoint-overlap@example.invalid"
    path = "/auth/account_link/challenge"
    now = DateTime.from_unix!(source["at"]) |> Map.put(:microsecond, {0, 6})
    at = source["at"]
    secret = RailsSecret.fetch()

    keys =
      for {name, value} <- [
            {"auth/account_link_challenge_session", id},
            {"auth/account_link_challenge_ip", "127.0.0.1"}
          ],
          do: DawarichWeb.RateLimit.Rules.key(at, 900, name, value)

    previous = Application.fetch_env(:dawarich, :account_link_context)
    Application.put_env(:dawarich, :a11e_overlap_owner, self())

    Application.put_env(:dawarich, :account_link_context, %{
      repo: BarrierRepo,
      clock: fn -> now end,
      rate_now: at
    })

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:dawarich, :account_link_context, value)
        :error -> Application.delete_env(:dawarich, :account_link_context)
      end

      Application.delete_env(:dawarich, :a11e_overlap_owner)
    end)

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      [[count]] =
        Repo.query!("SELECT count(*) FROM users WHERE id=$1 OR email=$2", [id, email], log: false).rows

      assert count == 0
      for key <- keys, do: assert(Dawarich.State.count(Dawarich.ScratchRepo, key) == 0)

      try do
        before = hd(source["overlap"]["responses"])["before"]

        Dawarich.Test.RailsUser.insert!(%{
          id: id,
          email: email,
          provider: nil,
          uid: nil,
          encrypted_password: before["encrypted_password"],
          settings: %{},
          sign_in_count: 0,
          failed_attempts: 2,
          failed_otp_attempts: 3,
          consumed_timestep: 42,
          remember_created_at: DateTime.from_iso8601(before["remember_created_at"]) |> elem(1)
        })

        [[observer]] = Repo.query!("SELECT pg_backend_pid()", [], log: false).rows
        refute Repo.in_transaction?()

        session =
          source["challenge_en"]["session"]
          |> put_in(["pending_oauth_link", "user_id"], id)
          |> put_in(["pending_oauth_link", "uid"], "a11e-endpoint-overlap")
          |> Map.put("_csrf_token", RailsCsrf.new_token())
          |> Map.put("session_id", "a11e-endpoint-overlap-session")

        cookie =
          "_dawarich_session=" <> RailsCookies.encrypt(session, "_dawarich_session", secret)

        body =
          URI.encode_query(%{
            "password" => "safepassword12",
            "authenticity_token" => RailsCsrf.masked_form_token(session, path, "POST")
          })

        request = form("POST", path, cookie, body)
        Application.put_env(:dawarich, :phoenix_auth, [])
        clients = for _ <- 1..2, do: connect(ctx.port)
        for client <- clients, do: send_raw(client, request)

        for _ <- clients do
          puma = accept(ctx.upstream)
          {head, rest} = read_head(puma)
          assert request_line(head) == "POST #{path} HTTP/1.1"
          assert header(head, "cookie") == [cookie]

          assert binary_part(read_at_least(puma, rest, byte_size(body)), 0, byte_size(body)) ==
                   body

          reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
          :gen_tcp.close(puma)
        end

        for client <- clients do
          assert {200, headers, "puma"} = read_response(client)
          assert values(headers, "x-dawarich-auth-owner") == []
          :gen_tcp.close(client)
        end

        for key <- keys, do: assert(Dawarich.State.count(Dawarich.ScratchRepo, key) == 0)
        assert Repo.get!(Dawarich.Auth.Account, id).provider == nil
        Application.put_env(:dawarich, :phoenix_auth, ["account_link"])

        first =
          Task.async(fn ->
            response =
              exchange(ctx, form("POST", path, cookie, body, "X-Request-ID: a11e-first\r\n"))

            receive do: (:response -> response)
          end)

        second =
          Task.async(fn ->
            response =
              exchange(ctx, form("POST", path, cookie, body, "X-Request-ID: a11e-second\r\n"))

            receive do: (:response -> response)
          end)

        Process.put(:a11e_http_workers, [first, second])
        assert_receive {:http_prepared, ["a11e-first"], one, backend_one, nil, 0}, 5_000
        Process.put(:a11e_http_prepared, [one])
        assert_receive {:http_prepared, ["a11e-second"], two, backend_two, nil, 0}, 5_000
        Process.put(:a11e_http_prepared, [one, two])
        assert MapSet.size(MapSet.new([observer, backend_one, backend_two])) == 3
        assert one != two
        send(one, {:save, 1})
        send(first.pid, :response)
        first_response = Task.await(first)
        send(two, {:save, 2})
        send(second.pid, :response)
        responses = [first_response, Task.await(second)]

        for {{status, headers, answer}, oracle} <-
              Enum.zip(responses, source["overlap"]["responses"]) do
          assert status == oracle["status"] and answer == ""
          assert values(headers, "x-dawarich-auth-owner") == ["native-account-link"]
          assert values(headers, "location") == ["http://a" <> oracle["location"]]
          for {name, value} <- oracle["headers"], do: assert(values(headers, name) == [value])

          wire =
            values(headers, "set-cookie")
            |> Enum.find(&String.starts_with?(&1, "_dawarich_session="))
            |> String.split(";")
            |> hd()
            |> String.split("=", parts: 2)
            |> List.last()

          {:ok, completed} = RailsCookies.decrypt(wire, "_dawarich_session", secret, now)
          assert completed["session_id"] != session["session_id"]
          assert completed["_csrf_token"] == session["_csrf_token"]

          normalized =
            completed
            |> Map.put("session_id", "SESSION_ID")
            |> Map.put("_csrf_token", "CSRF")
            |> Map.put("warden.user.user.key", [[oracle["before"]["id"]], "SYNTHETIC_BCRYPT_SALT"])

          assert completed["warden.user.user.key"] == [
                   [id],
                   binary_part(before["encrypted_password"], 0, 29)
                 ]

          assert normalized == oracle["session"]

          refute Enum.any?(
                   values(headers, "set-cookie"),
                   &String.starts_with?(&1, "remember_user_token=")
                 )
        end

        durable = Repo.get!(Dawarich.Auth.Account, id)
        oracle = List.last(source["overlap"]["responses"])["after"]
        assert durable.provider == oracle["provider"] and durable.uid == "a11e-endpoint-overlap"

        for field <- ~w(sign_in_count failed_attempts failed_otp_attempts consumed_timestep),
            do: assert(Map.fetch!(durable, String.to_existing_atom(field)) == oracle[field])

        for field <- ~w(current_sign_in_ip last_sign_in_ip),
            do: assert(Map.fetch!(durable, String.to_existing_atom(field)) == oracle[field])

        for field <- ~w(current_sign_in_at last_sign_in_at remember_created_at),
            do:
              assert(
                Map.fetch!(durable, String.to_existing_atom(field)) ==
                  DateTime.from_iso8601(oracle[field]) |> elem(1)
              )

        for key <- keys, do: assert(Dawarich.State.count(Dawarich.ScratchRepo, key) == 2)
        no_puma(ctx)
      after
        for pid <- Process.get(:a11e_http_prepared, []), do: send(pid, {:save, 0})
        for task <- Process.get(:a11e_http_workers, []), do: Task.shutdown(task, :brutal_kill)
        Repo.query!("DELETE FROM users WHERE id=$1 AND email=$2", [id, email], log: false)

        for key <- keys,
            do:
              Dawarich.ScratchRepo.query!("DELETE FROM phoenix.counters WHERE key=$1", [key],
                log: false
              )
      end
    end)
  end

  test "account_link opt-in owns challenge success while every provider and email route stays Rails",
       ctx do
    source = Jason.decode!(File.read!("test/fixtures/auth/account_link/requests.json"))
    path = "/auth/account_link/challenge"
    System.put_env("OIDC_CLIENT_ID", "a11e-endpoint-synthetic")
    System.put_env("OIDC_CLIENT_SECRET", "a11e-endpoint-synthetic")

    id =
      user!(%{email: "a11e-endpoint@example.invalid", encrypted_password: @hash, settings: %{}})

    {guest, _} = guest()
    now = System.os_time(:second)

    pending =
      source["challenge_en"]["session"]["pending_oauth_link"]
      |> Map.put("user_id", id)
      |> Map.put("expires_at", now + 900)

    session = Map.put(guest, "pending_oauth_link", pending)

    cookie =
      "_dawarich_session=" <>
        RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())

    good =
      URI.encode_query(%{
        "password" => "safepassword12",
        "authenticity_token" => RailsCsrf.masked_form_token(session, path, "POST")
      })

    keys =
      for at <- [now, now + 900],
          {name, value} <- [
            {"auth/account_link_challenge_session", id},
            {"auth/account_link_challenge_ip", "127.0.0.1"}
          ],
          do: DawarichWeb.RateLimit.Rules.key(at, 900, name, value)

    for key <- keys, do: assert(Dawarich.State.count(Dawarich.ScratchRepo, key) == 0)

    on_exit(fn ->
      for key <- keys,
          do:
            Dawarich.ScratchRepo.query!("DELETE FROM phoenix.counters WHERE key=$1", [key],
              log: false
            )
    end)

    Application.put_env(:dawarich, :phoenix_auth, [])
    off = to_puma(ctx, form("POST", path, cookie, good))
    assert off.body == good and off.cookie == [cookie]
    Application.put_env(:dawarich, :phoenix_auth, ["account_link"])
    assert {200, headers, html} = exchange(ctx, form("GET", path, cookie, ""))
    assert values(headers, "x-dawarich-auth-owner") == ["native-account-link"]
    no_puma(ctx)

    form_cookie =
      Enum.find(values(headers, "set-cookie"), &String.starts_with?(&1, "_dawarich_session="))
      |> String.split(";")
      |> hd()

    token =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(
        "form[action='/auth/account_link/challenge'] input[name=authenticity_token]"
      )
      |> LazyHTML.attribute("value")
      |> hd()

    rollback = URI.encode_query(%{"password" => "safepassword12", "authenticity_token" => token})
    Application.put_env(:dawarich, :phoenix_auth, [])
    assert to_puma(ctx, form("POST", path, form_cookie, rollback)).body == rollback
    Application.put_env(:dawarich, :phoenix_auth, ["account_link"])
    assert {302, headers, ""} = exchange(ctx, form("POST", path, cookie, good))
    assert values(headers, "x-dawarich-auth-owner") == ["native-account-link"]

    assert Repo.query!("SELECT provider,uid,sign_in_count FROM users WHERE id=$1", [id]).rows == [
             ["openid_connect", pending["uid"], 1]
           ]

    no_puma(ctx)
    replay = to_puma(ctx, form("POST", path, cookie, good))
    assert replay.body == good and replay.cookie == [cookie]
    assert Enum.at(source["sequential_replay"], 1)["status"] == 302
    Repo.query!("UPDATE users SET provider=NULL,uid=NULL WHERE id=$1", [id])
    wrong = URI.encode_query(%{"password" => "wrong", "authenticity_token" => token})
    assert to_puma(ctx, form("POST", path, form_cookie, wrong)).body == wrong

    for route <-
          ~w(/users/auth/openid_connect /users/auth/openid_connect/callback /users/auth/failure /auth/account_link /auth/account_link/email /api/v1/auth/google /users/sign_in /settings/two_factor /users/otp_challenge) do
      assert to_puma(ctx, form("POST", route, cookie, good)).body == good
    end

    for flows <- [~w(credentials two_factor otp), ~w(account_link)] do
      Application.put_env(:dawarich, :phoenix_auth, flows)
      assert to_puma(ctx, form("POST", "/users/sign_in", cookie, good)).body == good
    end

    System.put_env("SELF_HOSTED", "false")
    assert to_puma(ctx, form("POST", path, cookie, good)).body == good
    System.put_env("SELF_HOSTED", "true")
    Repo.query!("UPDATE users SET otp_required_for_login=true WHERE id=$1", [id])
    assert {302, headers, ""} = exchange(ctx, form("POST", path, cookie, good))
    assert values(headers, "location") == ["http://a/users/sign_in"]

    completed_cookie =
      Enum.find(values(headers, "set-cookie"), &String.starts_with?(&1, "_dawarich_session="))
      |> String.split(";")
      |> hd()

    [_, wire] = String.split(completed_cookie, "=", parts: 2)

    {:ok, completed} =
      RailsCookies.decrypt(wire, "_dawarich_session", RailsSecret.fetch(), DateTime.utc_now())

    refute Map.has_key?(completed, "warden.user.user.key")
    assert Repo.query!("SELECT sign_in_count FROM users WHERE id=$1", [id]).rows == [[1]]

    Repo.query!(
      "UPDATE users SET provider=NULL,uid=NULL,otp_required_for_login=false WHERE id=$1",
      [id]
    )

    newer = put_in(session, ["pending_oauth_link", "uid"], "a11e-superseded-new")

    newer_cookie =
      "_dawarich_session=" <>
        RailsCookies.encrypt(newer, "_dawarich_session", RailsSecret.fetch())

    assert {302, headers, ""} = exchange(ctx, form("POST", path, cookie, good))
    assert values(headers, "x-dawarich-auth-owner") == ["native-account-link"]
    assert to_puma(ctx, form("POST", path, newer_cookie, good)).cookie == [newer_cookie]
    assert Enum.at(source["superseded_collision"], 0)["status"] == 302
    Repo.query!("UPDATE users SET provider=NULL,uid=NULL WHERE id=$1", [id])
    assert {302, headers, ""} = exchange(ctx, form("POST", path, cookie, good))
    assert values(headers, "x-dawarich-auth-owner") == ["native-account-link"]
    assert source["transplant"]["status"] == 302
    no_puma(ctx)
    Application.put_env(:dawarich, :phoenix_auth, [])

    for saved <- [cookie, newer_cookie, cookie] do
      forwarded = to_puma(ctx, form("POST", path, saved, good))
      assert forwarded.cookie == [saved] and forwarded.body == good
    end
  end

  test "real endpoint supports native and Rails OTP phases without duplicate effects", ctx do
    names =
      ~w(OTP_ENCRYPTION_PRIMARY_KEY OTP_ENCRYPTION_DETERMINISTIC_KEY OTP_ENCRYPTION_KEY_DERIVATION_SALT)

    old = Map.new(names, &{&1, System.get_env(&1)})
    Enum.each(names, &System.put_env(&1, "a11d-endpoint-synthetic"))

    on_exit(fn ->
      for {k, v} <- old, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
    end)

    otp = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    {:ok, cipher} = Dawarich.Auth.TwoFactor.Secret.encrypt(otp)
    id = user!(%{email: "a11d-endpoint@dawarich.test", encrypted_password: @hash, settings: %{}})

    Repo.query!(
      "UPDATE users SET otp_required_for_login=true,otp_secret=$2 WHERE id=$1",
      [id, cipher],
      log: false
    )

    {session, cookie} = guest()

    login =
      URI.encode_query(%{
        "authenticity_token" => RailsCsrf.masked_token(session),
        "user[email]" => "a11d-endpoint@dawarich.test",
        "user[password]" => "safepassword12"
      })

    Application.put_env(:dawarich, :phoenix_auth, ~w(credentials otp))
    registration("false")

    peer =
      Task.async(fn ->
        case :gen_tcp.accept(ctx.upstream.listen, 200) do
          {:error, :timeout} ->
            :none

          {:ok, socket} ->
            read_head(socket)
            reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
            :puma
        end
      end)

    response =
      exchange(ctx, form("POST", "/users/sign_in", cookie, login, "Accept: text/html\r\n"))

    assert Task.await(peer) == :none
    assert {422, headers, _} = response
    assert values(headers, "x-dawarich-auth-owner") == ["native-otp"]

    pending_cookie =
      Enum.find(values(headers, "set-cookie"), &String.starts_with?(&1, "_dawarich_session="))
      |> String.split(";")
      |> hd()

    [_, value] = String.split(pending_cookie, "=", parts: 2)

    {:ok, pending} =
      RailsCookies.decrypt(value, "_dawarich_session", RailsSecret.fetch(), DateTime.utc_now())

    assert pending["otp_user_id"] == id and pending["warden.user.user.key"] == nil

    attempt =
      URI.encode_query(%{
        "authenticity_token" =>
          RailsCsrf.masked_form_token(pending, "/users/otp_challenge", "POST"),
        "otp_attempt" => "invalid"
      })

    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    seen = to_puma(ctx, form("POST", "/users/otp_challenge", pending_cookie, attempt))
    assert seen.body == attempt
    Application.put_env(:dawarich, :phoenix_auth, ["otp"])

    parsed =
      Plug.Test.conn("POST", "http://www.example.com/users/otp_challenge", attempt)
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> Plug.Conn.put_req_header("content-length", Integer.to_string(byte_size(attempt)))
      |> Plug.Test.put_req_cookie("_dawarich_session", value)

    DawarichWeb.AuthOtp.Http.call(parsed,
      enabled: true,
      fallback: fn conn ->
        preserved = conn.private[:dawarich_raw_body] == attempt
        assert preserved
        conn
      end
    )

    seen = to_puma(ctx, form("POST", "/users/otp_challenge", pending_cookie, attempt))
    assert seen.body == attempt and seen.response == {200, ["rails=1; path=/"], [], "puma"}

    assert Repo.query!(
             "SELECT sign_in_count,consumed_timestep,failed_otp_attempts FROM users WHERE id=$1",
             [id],
             log: false
           ).rows == [[0, nil, 0]]

    now = DateTime.utc_now() |> DateTime.to_unix()

    source_pending =
      Map.merge(session, %{
        "otp_user_id" => id,
        "otp_challenge_at" => now,
        "otp_remember_me" => false
      })

    source_cookie =
      "_dawarich_session=" <>
        RailsCookies.encrypt(source_pending, "_dawarich_session", RailsSecret.fetch())

    good =
      URI.encode_query(%{
        "authenticity_token" => RailsCsrf.masked_token(source_pending),
        "otp_attempt" => Dawarich.Auth.TwoFactor.Totp.at(otp, now)
      })

    Repo.query!("DELETE FROM phoenix.registration_setting", [], log: false)

    assert {302, headers, ""} =
             exchange(ctx, form("POST", "/users/otp_challenge", source_cookie, good))

    assert values(headers, "x-dawarich-auth-owner") == ["native-otp"]
    assert Repo.query!("SELECT sign_in_count FROM users WHERE id=$1", [id]).rows == [[1]]
    assert to_puma(ctx, form("POST", "/users/otp_challenge", source_cookie, good)).body == good

    for path <- ~w(/users/password /api/v1/auth/otp_challenge /users/auth/github /users/sign_in) do
      assert to_puma(ctx, form("POST", path, cookie, attempt)).body == attempt
    end

    no_puma(ctx)
  end

  test "endpoint management ownership and OTP login handback remain independent", ctx do
    names =
      ~w(OTP_ENCRYPTION_PRIMARY_KEY OTP_ENCRYPTION_DETERMINISTIC_KEY OTP_ENCRYPTION_KEY_DERIVATION_SALT)

    previous = Map.new(names, &{&1, System.get_env(&1)})
    Enum.each(names, &System.put_env(&1, "a11c-endpoint-synthetic-not-for-production"))

    on_exit(fn ->
      for {name, value} <- previous,
          do: if(value, do: System.put_env(name, value), else: System.delete_env(name))
    end)

    id = user!(%{email: "a11c-endpoint@dawarich.test", encrypted_password: @hash, settings: %{}})

    {session, _} =
      Dawarich.Auth.SessionCookie.for_form(%{"user_return_to" => "/stats"}, RailsSecret.fetch())

    session = Map.put(session, "warden.user.user.key", [[id], binary_part(@hash, 0, 29)])

    cookie =
      "_dawarich_session=" <>
        RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())

    path = "/settings/two_factor"
    token = RailsCsrf.masked_token(session)
    body = URI.encode_query(%{"authenticity_token" => token})

    for {method, target} <- [
          {"GET", path},
          {"POST", path},
          {"POST", path <> "/verify"},
          {"DELETE", path}
        ] do
      seen = to_puma(ctx, form(method, target, cookie, body))
      assert seen.body == body and seen.line == "#{method} #{target} HTTP/1.1"
      assert seen.response == {200, ["rails=1; path=/"], [], "puma"}
    end

    Application.put_env(:dawarich, :phoenix_auth, ["two_factor"])

    peer =
      Task.async(fn ->
        case :gen_tcp.accept(ctx.upstream.listen, 200) do
          {:error, :timeout} ->
            :none

          {:ok, socket} ->
            read_head(socket)
            reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
            :puma
        end
      end)

    assert {200, headers, _} = exchange(ctx, form("GET", path, cookie, ""))
    assert Task.await(peer) == :none
    assert values(headers, "x-dawarich-auth-owner") == ["native-two-factor"]
    assert {200, headers, _} = exchange(ctx, form("POST", path, cookie, body))
    assert values(headers, "x-dawarich-auth-owner") == ["native-two-factor"]
    assert [[ciphertext]] = Repo.query!("SELECT otp_secret FROM users WHERE id=$1", [id]).rows
    {:ok, secret} = Dawarich.Auth.TwoFactor.Secret.decrypt(ciphertext)
    now = DateTime.utc_now() |> DateTime.to_unix()

    verify =
      URI.encode_query(%{
        "authenticity_token" => token,
        "otp_attempt" => Dawarich.Auth.TwoFactor.Totp.at(secret, now)
      })

    assert {200, headers, _} = exchange(ctx, form("POST", path <> "/verify", cookie, verify))
    assert values(headers, "x-dawarich-auth-owner") == ["native-two-factor"]

    assert Repo.query!("SELECT otp_required_for_login,sign_in_count FROM users WHERE id=$1", [id]).rows ==
             [[true, 0]]

    no_puma(ctx)
    Application.put_env(:dawarich, :phoenix_auth, ~w(two_factor credentials))
    registration("false")

    login =
      URI.encode_query(%{
        "authenticity_token" => token,
        "user[email]" => "a11c-endpoint@dawarich.test",
        "user[password]" => "safepassword12"
      })

    assert to_puma(ctx, form("POST", "/users/sign_in", cookie, login)).body == login
    unsupported = body <> "&_method=patch"
    seen = to_puma(ctx, form("POST", path, cookie, unsupported))
    assert seen.body == unsupported and seen.line == "POST #{path} HTTP/1.1"
    assert seen.response == {200, ["rails=1; path=/"], [], "puma"}

    for target <- ~w(/users/otp_challenge /api/v1/auth/otp_challenge) do
      assert to_puma(ctx, form("POST", target, cookie, body)).body == body
    end

    System.put_env("DAWARICH_RAILS_SLICES", "api_account")

    for target <-
          ~w(/api/v1/users/me/two_factor/setup /api/v1/users/me/two_factor/confirm /api/v1/users/me/two_factor/backup_codes) do
      assert to_puma(ctx, form("POST", target, cookie, body)).body == body
    end

    assert to_puma(ctx, form("DELETE", "/api/v1/users/me/two_factor", cookie, body)).body == body
    System.delete_env("DAWARICH_RAILS_SLICES")

    disable =
      URI.encode_query(%{
        "authenticity_token" => token,
        "_method" => "delete",
        "password" => "safepassword12",
        "otp_attempt" => Dawarich.Auth.TwoFactor.Totp.at(secret, now + 30)
      })

    assert {302, headers, ""} = exchange(ctx, form("POST", path, cookie, disable))
    assert values(headers, "x-dawarich-auth-owner") == ["native-two-factor"]

    assert Repo.query!(
             "SELECT otp_required_for_login,otp_secret,otp_backup_codes,sign_in_count FROM users WHERE id=$1",
             [id]
           ).rows == [[false, nil, nil, 0]]

    no_puma(ctx)
  end

  test "disabled credentials flow leaves Rails request untouched while revised Rails reads PG registration",
       ctx do
    assert {:ok, false} = Dawarich.Auth.RegistrationSetting.fetch()

    claims =
      Repo.query!("SELECT key, expires_at FROM phoenix.once_claims ORDER BY key", [], log: false).rows

    {_session, cookie} = guest()
    body = "authenticity_token=x&user%5Bemail%5D=a%40dawarich.test&user%5Bpassword%5D=p"

    for {method, path} <- [
          {"POST", "/users/sign_in"},
          {"POST", "/users/sign_out"},
          {"POST", "/users/password"},
          {"PUT", "/users/password"},
          {"POST", "/users/unlock"}
        ] do
      seen = to_puma(ctx, form(method, path, cookie, body))
      assert seen.line == "#{method} #{path} HTTP/1.1"
      assert seen.cookie == [cookie]
      assert seen.body == body
      assert seen.response == {200, ["rails=1; path=/"], [], "puma"}
    end

    for path <-
          ~w(/users/sign_in /users/password/new /users/password/edit /users/unlock/new /users/unlock),
        do: assert(to_puma(ctx, get(path)).line == "GET #{path} HTTP/1.1")

    assert {:ok, false} = Dawarich.Auth.RegistrationSetting.fetch()

    assert Repo.query!("SELECT key, expires_at FROM phoenix.once_claims ORDER BY key", [],
             log: false
           ).rows == claims
  end

  test "credentials on: Phoenix answers the sign-in form with Rails' sign-up link rule", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    registration("false")

    assert {200, headers, body} = exchange(ctx, get("/users/sign_in"))
    assert values(headers, "x-dawarich-auth-owner") == ["native-credentials"]
    assert body =~ ~s(action="/users/sign_in")
    refute body =~ ~s(href="/users/sign_up")
    no_puma(ctx)

    registration("true")
    assert {200, _headers, body} = exchange(ctx, get("/users/sign_in"))
    assert body =~ ~s(href="/users/sign_up")
  end

  test "credentials on: a correct password signs in through Phoenix", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    registration("false")
    email = "a11a-#{System.unique_integer([:positive])}@dawarich.test"
    id = user!(%{email: email, encrypted_password: @hash})
    {session, cookie} = guest()

    body =
      URI.encode_query([
        {"authenticity_token", RailsCsrf.masked_token(session)},
        {"user[email]", email},
        {"user[password]", "safepassword12"},
        {"user[remember_me]", "0"}
      ])

    assert {303, headers, ""} = exchange(ctx, form("POST", "/users/sign_in", cookie, body))
    assert values(headers, "x-dawarich-auth-owner") == ["native-credentials"]
    assert values(headers, "location") == ["http://a/"]

    assert Enum.any?(
             values(headers, "set-cookie"),
             &String.starts_with?(&1, "_dawarich_session=")
           )

    assert Repo.query!("SELECT sign_in_count FROM users WHERE id = $1", [id]).rows == [[1]]
    no_puma(ctx)
  end

  test "nil or failed registration read retains each auth reader admission boundary", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ~w(credentials recovery))
    registration("nil")

    for path <- ["/users/sign_in", "/users/password/new"] do
      assert to_puma(ctx, get(path)).line == "GET #{path} HTTP/1.1"
    end

    Repo.query!(
      "ALTER TABLE phoenix.registration_setting RENAME COLUMN enabled TO unavailable",
      [],
      log: false
    )

    for path <- ["/users/sign_in", "/users/password/new"] do
      assert to_puma(ctx, get(path)).line == "GET #{path} HTTP/1.1"
    end
  end

  test "credentials on: what Phoenix cannot serve reaches Puma with the request intact", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    registration("false")
    {_session, cookie} = guest()

    body =
      "authenticity_token=forged&user%5Bemail%5D=a%40dawarich.test&user%5Bpassword%5D=p&user%5Bremember_me%5D=0"

    for extra <- ["", "X-Forwarded-For: 192.0.2.1\r\n"] do
      seen = to_puma(ctx, form("POST", "/users/sign_in", cookie, body, extra))
      assert seen.line == "POST /users/sign_in HTTP/1.1"
      assert seen.cookie == [cookie]
      assert seen.body == body
      assert seen.response == {200, ["rails=1; path=/"], [], "puma"}
    end

    registration("nil")
    assert to_puma(ctx, get("/users/sign_in")).line == "GET /users/sign_in HTTP/1.1"

    registration("false")
    System.put_env("SELF_HOSTED", "false")
    assert to_puma(ctx, get("/users/sign_in")).line == "GET /users/sign_in HTTP/1.1"
  end

  test "credentials on, not self-hosted: Puma answers before Phoenix's own SSL check can", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    registration("false")
    System.put_env("SELF_HOSTED", "false")
    System.put_env("APPLICATION_PROTOCOL", "https")
    System.put_env("RAILS_ENV", "production")

    seen = to_puma(ctx, get("/users/sign_in"))
    assert seen.line == "GET /users/sign_in HTTP/1.1"
    assert seen.response == {200, ["rails=1; path=/"], [], "puma"}
  end

  test "credentials on: the invitation variant of the sign-in page stays with Rails", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    registration("false")

    path = "/users/sign_in?invitation_token=abc"
    assert to_puma(ctx, get(path)).line == "GET #{path} HTTP/1.1"

    {session, _cookie} = guest()
    session = Map.put(session, "invitation_token", "abc")

    cookie =
      "_dawarich_session=" <>
        RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())

    request = "GET /users/sign_in HTTP/1.1\r\nHost: a\r\nCookie: #{cookie}\r\n\r\n"
    assert to_puma(ctx, request).line == "GET /users/sign_in HTTP/1.1"
  end

  describe "recovery" do
    setup do
      names = ~w(SMTP_FROM SMTP_SERVER E2E_SMTP_PORT DOMAIN SMTP_AUTHENTICATION)
      saved = for name <- names, value = System.get_env(name), do: {name, value}
      Enum.each(names, &System.delete_env/1)

      on_exit(fn ->
        Enum.each(names, &System.delete_env/1)
        Enum.each(saved, fn {name, value} -> System.put_env(name, value) end)
      end)

      registration("false")
      :ok
    end

    defp mail_setup do
      System.put_env("RAILS_ENV", "production")
      System.put_env("SMTP_FROM", "Dawarich <a11a@dawarich.test>")
      System.put_env("SMTP_SERVER", "smtp.example.test")
      System.put_env("DOMAIN", "dawarich.example.test")
    end

    defp recovery_post(email) do
      {session, cookie} = guest()

      body =
        URI.encode_query([
          {"authenticity_token", RailsCsrf.masked_token(session)},
          {"user[email]", email}
        ])

      {form("POST", "/users/password", cookie, body), body}
    end

    defp digest_of(id),
      do: Repo.query!("SELECT reset_password_token FROM users WHERE id = $1", [id]).rows

    test "recovery on: Phoenix answers the recovery forms; credentials alone leaves them to Puma",
         ctx do
      Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
      assert to_puma(ctx, get("/users/password/new")).line == "GET /users/password/new HTTP/1.1"

      Application.put_env(:dawarich, :phoenix_auth, ["recovery"])
      assert {200, headers, body} = exchange(ctx, get("/users/password/new"))
      assert values(headers, "x-dawarich-auth-owner") == ["native-recovery"]
      assert body =~ ~s(action="/users/password")
      no_puma(ctx)
      assert to_puma(ctx, get("/users/sign_in")).line == "GET /users/sign_in HTTP/1.1"
    end

    test "recovery on with a mail setup: Phoenix writes the digest and one mailers job, Puma never sees the post",
         ctx do
      Application.put_env(:dawarich, :phoenix_auth, ["recovery"])
      mail_setup()
      email = "a11a-#{System.unique_integer([:positive])}@dawarich.test"
      id = user!(%{email: email})
      {request, _body} = recovery_post(email)

      assert {303, headers, ""} = exchange(ctx, request)
      assert values(headers, "x-dawarich-auth-owner") == ["native-recovery"]
      assert values(headers, "location") == ["http://a/users/sign_in"]
      no_puma(ctx)

      assert [[digest]] = digest_of(id)
      assert is_binary(digest)

      assert Repo.query!("SELECT worker, args->>'digest' FROM oban.oban_jobs").rows == [
               ["Dawarich.Auth.Recovery.MailWorker", digest]
             ]
    end

    test "recovery on without a mail setup: the post reaches Puma with its body, nothing written",
         ctx do
      Application.put_env(:dawarich, :phoenix_auth, ["recovery"])
      email = "a11a-#{System.unique_integer([:positive])}@dawarich.test"
      id = user!(%{email: email})
      {request, body} = recovery_post(email)

      seen = to_puma(ctx, request)
      assert seen.body == body
      assert seen.response == {200, ["rails=1; path=/"], [], "puma"}
      assert digest_of(id) == [[nil]]
      assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[0]]
    end

    test "recovery on where Phoenix cannot mail as Rails does (development or unset RAILS_ENV, an SMTP authentication only Rails speaks): the post reaches Puma, nothing written",
         ctx do
      Application.put_env(:dawarich, :phoenix_auth, ["recovery"])
      email = "a11a-#{System.unique_integer([:positive])}@dawarich.test"
      id = user!(%{email: email})

      for {name, value} <- [
            {"RAILS_ENV", nil},
            {"RAILS_ENV", "development"},
            {"SMTP_AUTHENTICATION", "xoauth2"}
          ] do
        mail_setup()
        if value, do: System.put_env(name, value), else: System.delete_env(name)
        {request, body} = recovery_post(email)

        seen = to_puma(ctx, request)
        assert seen.body == body, "#{name}=#{inspect(value)}"
        assert seen.response == {200, ["rails=1; path=/"], [], "puma"}
      end

      assert digest_of(id) == [[nil]]
      assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[0]]
    end

    test "OIDC configured: neither the recovery forms nor the sign-in reach the native flows",
         ctx do
      Application.put_env(:dawarich, :phoenix_auth, ["credentials", "recovery"])
      mail_setup()
      System.put_env("OIDC_CLIENT_ID", "synthetic")
      System.put_env("OIDC_CLIENT_SECRET", "synthetic")

      assert to_puma(ctx, get("/users/password/new")).line == "GET /users/password/new HTTP/1.1"
      assert to_puma(ctx, get("/users/sign_in")).line == "GET /users/sign_in HTTP/1.1"

      {session, cookie} = guest()

      body =
        URI.encode_query([
          {"authenticity_token", RailsCsrf.masked_token(session)},
          {"user[email]", "oidc@dawarich.test"},
          {"user[password]", "synthetic-password"}
        ])

      assert to_puma(ctx, form("POST", "/users/sign_in", cookie, body)).body == body
    end
  end
end

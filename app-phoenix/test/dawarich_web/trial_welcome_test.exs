defmodule DawarichWeb.TrialWelcomeTest do
  use Dawarich.JobsCase, async: false
  import Plug.Conn
  alias Dawarich.RailsSecret
  alias Dawarich.ScratchRepo, as: Repo
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{TrialWelcome, WelcomeGate}
  alias __MODULE__.{ClaimFailureRepo, TrackFailureRepo}
  @now ~U[2026-10-04 10:00:00.000000Z]
  @jwt "synthetic-a10b-welcome-signing-phrase"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)

    RailsUser.insert!(
      %{
        id: 15611,
        email: "a10b-welcome-http@example.invalid",
        status: 2,
        active_until: ~N[2026-10-11 10:00:00.000000],
        settings: %{"locale" => "en", "timezone" => "UTC"}
      },
      Repo
    )

    RailsUser.insert!(%{
      id: 15611,
      email: "a13g-auth-http@example.invalid",
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    %{
      context: %{
        jwt_secret: @jwt,
        secret: RailsSecret.fetch(),
        env: %{},
        oidc: false,
        clock: fn -> @now end,
        repo: Repo
      }
    }
  end

  test "all native welcome outcomes retain no store no cache no referrer", c do
    assert Code.ensure_loaded?(TrialWelcome), "welcome HTTP handler must exist"
    assert Code.ensure_loaded?(WelcomeGate), "welcome gate must exist"

    for {{overrides, actor, outcome}, index} <-
          Enum.with_index([
            {%{}, nil, :fresh},
            {%{"purpose" => "invalid"}, nil, :rejected},
            {%{"exp" => DateTime.to_unix(@now)}, nil, :rejected},
            {%{"jti" => " "}, nil, :rejected},
            {%{"user_id" => 15999}, nil, :rejected},
            {%{}, 15611, :replay},
            {%{}, nil, :replay},
            {%{}, nil, :error}
          ]) do
      jti = "a13g-http-#{index}"
      overrides = Map.put_new(overrides, "jti", jti)

      if outcome == :replay,
        do:
          Dawarich.Trial.WelcomeClaim.claim(
            jti,
            DateTime.to_unix(@now) + 1800,
            DateTime.to_unix(@now),
            Repo
          )

      context = if outcome == :error, do: %{c.context | repo: ClaimFailureRepo}, else: c.context
      conn = request(overrides, actor)
      assert WelcomeGate.owned?(conn, %{}, context: context)
      conn = TrialWelcome.call(conn, context: context)
      assert conn.status in [302, 500] and conn.halted and conn.resp_body == ""
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert get_resp_header(conn, "pragma") == ["no-cache"]
      assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
      refute conn.resp_body =~ "token"
      if conn.status == 500, do: assert(get_resp_header(conn, "location") == [])
    end

    for {suffix, header} <- [
          {"&token=duplicate", nil},
          {"&referral=synthetic", nil},
          {"&token%5B%5D=x", nil},
          {"", "frame"}
        ] do
      original = request(%{}, nil)
      conn = %{original | query_string: original.query_string <> suffix}
      conn = if header, do: put_req_header(conn, "turbo-frame", header), else: conn
      refute WelcomeGate.owned?(conn, %{}, context: c.context)
    end
  end

  test "signed underscore expiry and not-before match Rails recordings before any claim", c do
    for {name, overrides} <- [
          {"underscore_future_nbf", %{"nbf" => "1_791_109_800"}},
          {"underscore_exp", %{"exp" => "1_791_109_800"}},
          {"underscore_past_nbf", %{"nbf" => "1_791_106_200"}}
        ] do
      oracle = File.read!("test/fixtures/welcome_home/#{name}.json") |> Jason.decode!()
      jti = "a13g-review-#{name}"

      key =
        "trial_welcome:consumed:sha256:" <>
          Base.encode16(:crypto.hash(:sha256, jti), case: :lower)

      [[before]] =
        Repo.query!("SELECT sign_in_count FROM users WHERE id=15611", [], log: false).rows

      conn = request(Map.put(overrides, "jti", jti), nil)
      assert WelcomeGate.owned?(conn, %{}, context: c.context)

      assert [] ==
               Repo.query!("SELECT key FROM phoenix.once_claims WHERE key=$1", [key], log: false).rows

      conn = TrialWelcome.call(conn, context: c.context)
      assert conn.status == oracle["status"]
      assert URI.parse(hd(get_resp_header(conn, "location"))).path == oracle["location"]

      {:ok, session} =
        Dawarich.RailsCookies.decrypt(
          conn.resp_cookies["_dawarich_session"].value,
          "_dawarich_session",
          RailsSecret.fetch(),
          @now
        )

      assert session["flash"]["flashes"] == oracle["flash"]

      assert get_in(session, ["warden.user.user.key", Access.at(0)]) == [15611] ==
               oracle["signed_in"]

      [[after_count]] =
        Repo.query!("SELECT sign_in_count FROM users WHERE id=15611", [], log: false).rows

      assert after_count - before == oracle["trackable"]["sign_in_count_delta"]

      rows =
        Repo.query!("SELECT key FROM phoenix.once_claims WHERE key=$1", [key], log: false).rows

      assert rows == [[key]] == oracle["claimed"]
      if name == "underscore_future_nbf", do: assert(rows == [] and after_count == before)

      for {header, value} <- oracle["headers"],
          String.downcase(header) in ["cache-control", "pragma", "referrer-policy"] do
        assert get_resp_header(conn, String.downcase(header)) == [value]
      end
    end
  end

  test "midnight notices use application timezone for guests and SafeSettings for actors", c do
    Repo.query!("UPDATE users SET active_until='2026-10-11 23:30:00' WHERE id=15611", [],
      log: false
    )

    for locale <- ~w(en de), actor <- [nil, 15611] do
      Repo.query!(
        "UPDATE users SET settings=$1 WHERE id=15611",
        [%{"locale" => locale, "timezone" => "UTC"}],
        log: false
      )

      Dawarich.Repo.query!(
        "UPDATE users SET settings=$1 WHERE id=15611",
        [%{"locale" => locale, "timezone" => "UTC"}],
        log: false
      )

      kind = if actor, do: "actor", else: "guest"

      oracle =
        File.read!("test/fixtures/welcome_home/midnight_#{kind}_#{locale}.json")
        |> Jason.decode!()

      conn =
        request(%{"jti" => "midnight-#{locale}-#{kind}"}, actor, locale)
        |> TrialWelcome.call(context: c.context)

      assert conn.status == 302

      {:ok, session} =
        Dawarich.RailsCookies.decrypt(
          conn.resp_cookies["_dawarich_session"].value,
          "_dawarich_session",
          RailsSecret.fetch(),
          @now
        )

      assert session["flash"]["flashes"]["notice"] == oracle["flash"]["notice"]
    end
  end

  test "failed sign-in leaves committed claim and terminal response with no upstream replay", c do
    parent = self()
    server = Dawarich.Test.RawHTTP.listen()
    old = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, server.port})

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, old)
      :gen_tcp.close(server.listen)
    end)

    start_supervised!(
      {Task,
       fn ->
         socket = Dawarich.Test.RawHTTP.accept(server)
         Dawarich.Test.RawHTTP.read_head(socket)
         send(parent, :upstream_replayed)

         Dawarich.Test.RawHTTP.reply(
           socket,
           "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
         )

         :gen_tcp.close(socket)
       end}
    )

    Process.put(:track_failure_observer, parent)
    conn = request(%{"jti" => "track-failure"}, nil)
    before = Repo.query!("SELECT sign_in_count FROM users WHERE id=15611", [], log: false).rows
    result = TrialWelcome.call(conn, context: %{c.context | repo: TrackFailureRepo})
    assert_receive :track_attempted
    assert result.status == 500 and result.halted and result.resp_body == ""
    assert result.resp_cookies == %{}
    refute_receive :upstream_replayed
    assert get_resp_header(result, "x-dawarich-rails-proxy") == []

    assert Repo.query!("SELECT sign_in_count FROM users WHERE id=15611", [], log: false).rows ==
             before

    key =
      "trial_welcome:consumed:sha256:" <>
        Base.encode16(:crypto.hash(:sha256, "track-failure"), case: :lower)

    assert [[^key]] =
             Repo.query!("SELECT key FROM phoenix.once_claims WHERE key=$1", [key], log: false).rows

    guest = TrialWelcome.call(conn, context: c.context)
    assert guest.status == 302 and hd(get_resp_header(guest, "location")) =~ "/users/sign_in"
  end

  defmodule TrackFailureRepo do
    def transaction(fun), do: Dawarich.ScratchRepo.transaction(fun)

    def query!(sql, params, opts) do
      if String.starts_with?(sql, "UPDATE users SET sign_in_count") do
        send(Process.get(:track_failure_observer), :track_attempted)
        raise "deterministic Trackable failure"
      end

      Dawarich.ScratchRepo.query!(sql, params, opts)
    end
  end

  test "claim connection error is not a consumed or successful welcome", c do
    parent = self()
    server = Dawarich.Test.RawHTTP.listen()
    old = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, server.port})

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, old)
      :gen_tcp.close(server.listen)
    end)

    start_supervised!(
      {Task,
       fn ->
         socket = Dawarich.Test.RawHTTP.accept(server)
         Dawarich.Test.RawHTTP.read_head(socket)
         send(parent, :upstream_replayed)

         Dawarich.Test.RawHTTP.reply(
           socket,
           "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
         )

         :gen_tcp.close(socket)
       end}
    )

    before = Repo.query!("SELECT sign_in_count FROM users WHERE id=15611", [], log: false).rows

    result =
      TrialWelcome.call(request(%{"jti" => "claim-error"}, nil),
        context: %{c.context | repo: ClaimFailureRepo}
      )

    assert result.status == 500 and result.halted and result.resp_body == ""
    assert result.resp_cookies == %{}
    refute_receive :upstream_replayed

    assert Repo.query!("SELECT sign_in_count FROM users WHERE id=15611", [], log: false).rows ==
             before

    assert [] = Repo.query!("SELECT key FROM phoenix.once_claims", [], log: false).rows
  end

  defmodule ClaimFailureRepo do
    def query!(sql, params, opts) do
      if String.starts_with?(sql, "INSERT INTO phoenix.once_claims"),
        do: raise("deterministic claim connection error")

      Dawarich.ScratchRepo.query!(sql, params, opts)
    end
  end

  defp request(overrides, actor, locale \\ "en") do
    payload =
      Map.merge(
        %{
          "purpose" => "trial_welcome",
          "user_id" => 15611,
          "exp" => DateTime.to_unix(@now) + 1800,
          "jti" => "a10b-http-jti"
        },
        overrides
      )

    input =
      Base.url_encode64(~s({"alg":"HS256"}), padding: false) <>
        "." <> Base.url_encode64(Jason.encode!(payload), padding: false)

    token =
      input <> "." <> Base.url_encode64(:crypto.mac(:hmac, :sha256, @jwt, input), padding: false)

    session = if actor, do: RailsUser.session(actor), else: %{}
    session = Map.put(session, "locale", locale)

    Plug.Test.conn("GET", "/trial/welcome?" <> URI.encode_query(%{"token" => token}))
    |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("accept", "text/html")
  end
end

defmodule DawarichWeb.TrialWelcomeTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Repo, RailsSecret}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{TrialWelcome, WelcomeGate}
  @now ~U[2026-10-04 10:00:00.000000Z]
  @jwt "synthetic-a10b-welcome-signing-phrase"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: 15611,
      email: "a10b-welcome-http@example.invalid",
      status: 2,
      active_until: ~N[2026-10-11 10:00:00.000000],
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    %{
      context: %{
        jwt_secret: @jwt,
        secret: RailsSecret.fetch(),
        env: %{},
        oidc: false,
        clock: fn -> @now end,
        cache_command: fn _ -> {:ok, "OK"} end
      }
    }
  end

  test "all native welcome outcomes retain no store no cache no referrer", c do
    assert Code.ensure_loaded?(TrialWelcome), "welcome HTTP handler must exist"
    assert Code.ensure_loaded?(WelcomeGate), "welcome gate must exist"

    for {overrides, actor, command} <- [
          {%{}, nil, fn _ -> {:ok, "OK"} end},
          {%{"purpose" => "invalid"}, nil, fn _ -> raise "must not claim" end},
          {%{"exp" => DateTime.to_unix(@now)}, nil, fn _ -> raise "must not claim" end},
          {%{"jti" => " "}, nil, fn _ -> raise "must not claim" end},
          {%{"user_id" => 15999}, nil, fn _ -> raise "must not claim" end},
          {%{}, 15611, fn _ -> {:ok, nil} end},
          {%{}, nil, fn _ -> {:ok, nil} end},
          {%{}, nil, fn _ -> {:error, :uncertain} end}
        ] do
      context = %{c.context | cache_command: command}
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

      kind = if actor, do: "actor", else: "guest"

      oracle =
        File.read!("test/fixtures/welcome_home/midnight_#{kind}_#{locale}.json")
        |> Jason.decode!()

      conn = request(%{}, actor, locale) |> TrialWelcome.call(context: c.context)
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

defmodule Dawarich.Trial.WelcomeTest do
  use Dawarich.JobsCase, async: false
  import Plug.Conn
  alias Dawarich.Trial.Welcome
  alias Dawarich.{RailsCookies, RailsSecret}
  alias Dawarich.ScratchRepo, as: Repo
  alias Dawarich.Test.RailsUser
  alias __MODULE__.ObservedRepo
  @now ~U[2026-10-04 10:00:00.000000Z]
  @jwt "synthetic-a10b-welcome-signing-phrase"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)

    for id <- [15601, 15602] do
      RailsUser.insert!(
        %{
          id: id,
          email: "a10b-welcome-#{id}@example.invalid",
          status: 2,
          active_until: ~N[2026-10-11 10:00:00.000000],
          settings: %{"locale" => "en", "timezone" => "UTC"}
        },
        Repo
      )

      RailsUser.insert!(%{
        id: id,
        email: "a13g-auth-#{id}@example.invalid",
        settings: %{"timezone" => "UTC"}
      })
    end

    %{
      context: %{
        jwt_secret: @jwt,
        secret: RailsSecret.fetch(),
        env: %{},
        oidc: false,
        repo: Repo,
        clock: fn -> @now end
      }
    }
  end

  test "mismatch and unsupported session reject before claim while replay preserves actor", c do
    assert Code.ensure_loaded?(Welcome), "welcome flow must exist"
    parent = self()

    Process.put(:claim_observer, parent)
    context = Map.put(c.context, :repo, ObservedRepo)

    assert {:ok, mismatch} =
             Welcome.prepare(conn(RailsUser.session(15602)), claims("mismatch"), context)

    assert {:ok, result} = Welcome.consume(mismatch, context)
    assert result.path == "/" and result.flash["alert"] =~ "Another user"
    refute_receive :claim_attempted
    refute Dawarich.State.claimed?(Repo, claim_key("a10b-flow-mismatch"))

    for {session, overrides} <- [
          {%{"opaque" => String.duplicate("x", 5000)}, %{}},
          {%{"devise.otp_user_id" => 15601}, %{}},
          {%{"invitation_token" => "synthetic-invitation"}, %{}},
          {%{}, %{oidc: true}}
        ] do
      assert {:handoff, _} =
               Welcome.prepare(conn(session), claims("mismatch"), Map.merge(context, overrides))

      refute_receive :claim_attempted
    end

    Repo.query!("UPDATE users SET otp_required_for_login=true WHERE id=15601", [], log: false)
    assert {:handoff, _} = Welcome.prepare(conn(%{}), claims("mismatch"), context)
    refute_receive :claim_attempted
    Repo.query!("UPDATE users SET otp_required_for_login=false WHERE id=15601", [], log: false)

    RailsUser.insert!(
      %{
        id: 0,
        email: "a10b-zero-id@example.invalid",
        settings: %{"timezone" => "UTC"}
      },
      Repo
    )

    for {params, key} <- [
          {%{"token" => "malformed"}, "link_invalid_or_expired_please_sign_in"},
          {claims("mismatch", %{"jti" => " "}), "link_invalid_please_sign_in"},
          {claims("mismatch", %{"user_id" => 15999}),
           "account_no_longer_exists_please_sign_up_again"},
          {claims("mismatch", %{"user_id" => nil}),
           "account_no_longer_exists_please_sign_up_again"},
          {claims("mismatch", %{"user_id" => "not-an-id"}),
           "account_no_longer_exists_please_sign_up_again"}
        ] do
      assert {:ok, prepared} = Welcome.prepare(conn(%{}), params, context)
      assert {:ok, result} = Welcome.consume(prepared, context)
      {:ok, message} = Dawarich.I18n.t("en", "controllers.trial.welcome." <> key)
      assert result.path == "/users/sign_in" and result.flash == %{"alert" => message}
      refute_receive :claim_attempted
    end

    assert {:ok, prepared} = Welcome.prepare(conn(%{}), claims("replay"), context)
    assert {:ok, _} = Welcome.consume(prepared, context)
    assert_receive :claim_attempted
    before = snapshot()

    assert {:ok, prepared} =
             Welcome.prepare(conn(RailsUser.session(15601)), claims("replay"), context)

    assert {:ok, %{path: "/map/v2", flash: nil, cookie: nil}} = Welcome.consume(prepared, context)
    assert_receive :claim_attempted
    assert snapshot() == before
    assert {:ok, prepared} = Welcome.prepare(conn(%{}), claims("replay"), context)
    assert {:ok, result} = Welcome.consume(prepared, context)
    assert_receive :claim_attempted
    assert result.path == "/users/sign_in" and result.flash["alert"] =~ "already been used"
    assert snapshot() == before
  end

  test "welcome consumes in supplied repo before Trackable and preserves cookie replay outcomes",
       c do
    assert Code.ensure_loaded?(Welcome), "welcome flow must exist"

    for {locale, suffix, actor} <- [
          {"en", "first", nil},
          {"de", "head", nil},
          {"en", "same", 15601}
        ] do
      session = %{
        "locale" => locale,
        "session_id" => "synthetic-session-before",
        "user_return_to" => "/retained-return"
      }

      session = if actor, do: Map.merge(session, RailsUser.session(actor)), else: session
      method = if suffix == "head", do: "HEAD", else: "GET"
      before = snapshot()
      assert {:ok, prepared} = Welcome.prepare(conn(session, method), claims(suffix), c.context)
      assert snapshot() == before
      assert {:ok, result} = Welcome.consume(prepared, c.context)
      key = claim_key("a10b-flow-" <> suffix)

      assert [[^key]] =
               Repo.query!("SELECT key FROM phoenix.once_claims WHERE key=$1", [key], log: false).rows

      assert [] =
               Dawarich.Repo.query!("SELECT key FROM phoenix.once_claims WHERE key=$1", [key],
                 log: false
               ).rows

      assert result.path == "/map/v2"
      {issued, cookie} = result.cookie

      assert {:ok, ^issued} =
               RailsCookies.decrypt(cookie, "_dawarich_session", c.context.secret, @now)

      assert issued["warden.user.user.key"] == RailsUser.session(15601)["warden.user.user.key"]
      assert issued["user_return_to"] == "/retained-return"
      assert issued["session_id"] != session["session_id"] == is_nil(actor)
      refute Map.has_key?(issued, "remember_user_token")
      oracle = File.read!("test/fixtures/welcome_home/valid_#{locale}.json") |> Jason.decode!()
      assert result.flash == oracle["flash"]
      after_row = snapshot()
      assert hd(hd(after_row)) - hd(hd(before)) == if(actor, do: 0, else: 1)

      if is_nil(actor) do
        assert [[_, current, _, "127.0.0.1", _, _]] = after_row
        assert current == DateTime.to_naive(@now)
      end
    end

    Repo.query!("UPDATE users SET active_until=NULL WHERE id=15601", [], log: false)

    assert {:ok, prepared} =
             Welcome.prepare(
               conn(%{}),
               claims("first", %{"jti" => "a10b-flow-nil-date"}),
               c.context
             )

    assert {:ok, result} = Welcome.consume(prepared, c.context)

    assert result.flash["notice"] =~ "activated"
  end

  defp conn(session, method \\ "GET") do
    Plug.Test.conn(method, "/trial/welcome")
    |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("accept", "text/html")
  end

  defp claims(suffix, overrides \\ %{}) do
    payload =
      Map.merge(
        %{
          "user_id" => 15601,
          "purpose" => "trial_welcome",
          "exp" => DateTime.to_unix(@now) + 1800,
          "jti" => "a10b-flow-" <> suffix
        },
        overrides
      )

    input =
      Base.url_encode64(~s({"alg":"HS256"}), padding: false) <>
        "." <> Base.url_encode64(Jason.encode!(payload), padding: false)

    %{
      "token" =>
        input <>
          "." <> Base.url_encode64(:crypto.mac(:hmac, :sha256, @jwt, input), padding: false)
    }
  end

  defp snapshot,
    do:
      Repo.query!(
        "SELECT sign_in_count,current_sign_in_at,last_sign_in_at,current_sign_in_ip,last_sign_in_ip,settings FROM users WHERE id=15601",
        [],
        log: false
      ).rows

  defmodule ObservedRepo do
    def query!(sql, params, opts) do
      if String.starts_with?(sql, "INSERT INTO phoenix.once_claims"),
        do: send(Process.get(:claim_observer), :claim_attempted)

      Dawarich.ScratchRepo.query!(sql, params, opts)
    end
  end

  defp claim_key(jti),
    do:
      "trial_welcome:consumed:sha256:" <> Base.encode16(:crypto.hash(:sha256, jti), case: :lower)
end

defmodule DawarichWeb.A12f3bD04Test do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{RailsAuth, TrialGate, TrialLiveAuth, TrialResumeStatus, TrialUpgrade}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    saved =
      Map.new(
        ~w(DAWARICH_RAILS SELF_HOSTED MANAGER_URL JWT_SECRET_KEY),
        &{&1, System.get_env(&1)}
      )

    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "false")
    System.put_env("MANAGER_URL", "https://manager.example.test")
    System.put_env("JWT_SECRET_KEY", "synthetic-trialhome-checkout")

    RailsUser.insert!(%{
      id: 18041,
      email: "trialhome@example.invalid",
      status: 3,
      settings: %{"timezone" => "Europe/Berlin"}
    })

    on_exit(fn ->
      for {key, value} <- saved,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    :ok
  end

  @tag a12f3b_case: "D04a"
  test "trial upgrade and resume resolve all source payment and session states" do
    for self_hosted <- ~w(true false),
        status <- [0, 1, 2, 3],
        plan <- [0, 1, 2],
        expiry <- [~N[2026-10-03 09:59:59], ~N[2026-10-03 10:00:00], ~N[3026-01-01 00:00:00]] do
      System.put_env("SELF_HOSTED", self_hosted)

      Repo.query!(
        "UPDATE users SET status=$1,plan=$2,active_until=$3 WHERE id=18041",
        [status, plan, expiry],
        log: false
      )

      conn = request("/trial/resume?client=ios&aff=partner&locale=de")
      assert TrialGate.resume?(conn, %{})

      result =
        conn
        |> RailsAuth.call([])
        |> DawarichWeb.TrialResumeHeaders.call([])
        |> TrialResumeStatus.call([])

      if status == 3 do
        refute result.halted
      else
        assert result.status == 302
        assert get_resp_header(result, "location") == ["http://www.example.com/"]
      end

      assert get_resp_header(result, "cache-control") == ["no-store"]
      assert get_resp_header(result, "pragma") == ["no-cache"]
      upgrade = request("/trial/upgrade?plan=lite&interval=monthly&client=ios")
      assert TrialGate.upgrade?(upgrade, %{})

      upgrade =
        upgrade
        |> RailsAuth.call([])
        |> TrialUpgrade.call(now: ~U[2026-10-03 10:00:00Z], jti: "checkout")

      [location] = get_resp_header(upgrade, "location")

      if self_hosted == "true" do
        assert location == "http://www.example.com/"
      else
        token = URI.decode_query(URI.parse(location).query)["token"]
        [_, payload, _] = String.split(token, ".")
        claims = payload |> Base.url_decode64!(padding: false) |> Jason.decode!()
        assert claims["plan"] == "lite" and claims["interval"] == "monthly"
        assert claims["exp"] == 1_791_021_600 + 1800
      end
    end

    Repo.query!("UPDATE users SET status=3 WHERE id=18041", [], log: false)

    pending =
      Phoenix.ConnTest.dispatch(
        RailsUser.signed_in(18041),
        DawarichWeb.Endpoint,
        :head,
        "/trial/resume",
        nil
      )

    assert pending.status == 200 and pending.resp_body == ""
    assert get_resp_header(pending, "cache-control") == ["no-store"]
    user = Accounts.get(18041)

    session = %{
      "rails_user_id" => user.id,
      "request_path" => "/trial/resume",
      "query_params" => %{},
      "locale" => "de"
    }

    assert {:cont, authorized} = TrialLiveAuth.on_mount(:default, %{}, session, socket(user))
    Repo.query!("UPDATE users SET status=1 WHERE id=18041", [], log: false)

    assert {:halt, refreshed} =
             Phoenix.LiveView.Lifecycle.handle_info(:navbar_refresh, authorized)

    assert refreshed.redirected == {:redirect, %{to: "/", status: 302}}
  end

  @tag a12f3b_case: "D04b"
  test "trial residual failure is native without manager callback replay" do
    System.delete_env("JWT_SECRET_KEY")
    assert TrialGate.upgrade?(request("/trial/upgrade"), %{})
    result = request("/trial/upgrade") |> RailsAuth.call([]) |> TrialUpgrade.call([])
    assert result.status == 503 and result.halted
    assert get_resp_header(result, "location") == []
    assert get_resp_header(result, "x-dawarich-rails-proxy") == []
    result = request("/trial/resume") |> RailsAuth.call([]) |> TrialResumeStatus.call([])
    assert result.status == 503 and result.halted
    assert get_resp_header(result, "location") == []
    assert get_resp_header(result, "cache-control") == ["no-store"]
    assert Repo.query!("SELECT count(*) FROM public.job_outbox", [], log: false).rows == [[0]]
  end

  defp request(path),
    do:
      Plug.Test.conn(:get, path)
      |> Plug.Test.put_req_cookie(
        "_dawarich_session",
        RailsUser.cookie(RailsUser.session(18041, %{"dawarich_client" => "ios"}))
      )

  defp socket(user) do
    %Phoenix.LiveView.Socket{
      router: DawarichWeb.Router,
      view: DawarichWeb.TrialLive.Resume,
      endpoint: DawarichWeb.Endpoint,
      transport_pid: self(),
      assigns: %{__changed__: %{}, current_user: user, flash: %{}},
      private: %{
        connect_info: %{session: %{"rails_user_id" => user.id}},
        lifecycle: %Phoenix.LiveView.Lifecycle{}
      }
    }
  end
end

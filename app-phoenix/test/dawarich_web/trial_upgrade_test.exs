defmodule DawarichWeb.TrialUpgradeTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test, only: [put_req_cookie: 3]
  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{RailsAuth, RequireUser, TrialGate, TrialUpgrade}

  @now ~U[2026-10-03 10:00:00Z]
  @jti "00000000-0000-4000-8000-000000010001"

  @tag a10_boundary: :upgrade
  test "upgrade GET uses Rails auth before redirect" do
    guest =
      Phoenix.ConnTest.dispatch(
        Phoenix.ConnTest.build_conn(),
        DawarichWeb.Endpoint,
        :get,
        "/trial/upgrade",
        nil
      )

    assert guest.status == 302
    assert get_resp_header(guest, "location") == ["http://www.example.com/users/sign_in"]
    System.put_env("SELF_HOSTED", "true")

    local =
      Phoenix.ConnTest.dispatch(
        RailsUser.signed_in(10001),
        DawarichWeb.Endpoint,
        :get,
        "/trial/upgrade",
        nil
      )

    assert local.status == 302
    assert get_resp_header(local, "location") == ["http://www.example.com/"]
    System.put_env("SELF_HOSTED", "false")

    cloud =
      Phoenix.ConnTest.dispatch(
        RailsUser.signed_in(10001),
        DawarichWeb.Endpoint,
        :get,
        "/trial/upgrade?plan=lite&interval=monthly",
        nil
      )

    assert cloud.status == 302
    [location] = get_resp_header(cloud, "location")
    token = URI.decode_query(URI.parse(location).query)["token"]
    [_, payload, _] = String.split(token, ".")
    claims = payload |> Base.url_decode64!(padding: false) |> Jason.decode!()

    assert Map.take(claims, ~w(plan interval purpose user_id)) == %{
             "plan" => "lite",
             "interval" => "monthly",
             "purpose" => "checkout",
             "user_id" => 10001
           }
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    previous_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous_level) end)
    keys = ~w(SELF_HOSTED MANAGER_URL JWT_SECRET_KEY)
    previous = Map.new(keys, &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "false")
    System.put_env("MANAGER_URL", "https://manager.example.test")
    System.put_env("JWT_SECRET_KEY", "a10-checkout-synthetic-signing-phrase-not-for-production")

    on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    RailsUser.insert!(%{
      id: 10001,
      email: "a10-checkout@example.invalid",
      settings: %{"timezone" => "Europe/Berlin", "onboarding_completed" => true}
    })

    :ok
  end

  @tag a10_trial: :self
  test "upgrade authenticates before self-hosted redirect and never issues local checkout" do
    System.put_env("SELF_HOSTED", "true")
    System.delete_env("JWT_SECRET_KEY")
    guest = Plug.Test.conn(:get, "/trial/upgrade") |> RailsAuth.call([]) |> assign(:locale, "en")
    assert true == TrialGate.upgrade?(guest, %{})
    guest = RequireUser.call(guest, []) |> TrialUpgrade.call(now: @now, jti: @jti)
    assert guest.status == 302
    assert get_resp_header(guest, "location") == ["http://www.example.com/users/sign_in"]

    log =
      capture_log([level: :info], fn ->
        conn = prepared("") |> RequireUser.call([]) |> TrialUpgrade.call(now: @now, jti: @jti)
        assert conn.status == 302
        assert conn.resp_body == ""
        assert get_resp_header(conn, "location") == ["http://www.example.com/"]
      end)

    refute log =~ "trial_upgrades_viewed"
  end

  @tag a10_trial: :cloud
  test "Cloud upgrade sanitizes both options and logs only event fields" do
    for {name, query} <- [
          {"upgrade_pro_annual", "plan=pro&interval=annual"},
          {"upgrade_lite_monthly", "plan=lite&interval=monthly"},
          {"upgrade_invalid", "plan=enterprise&interval=weekly"},
          {"upgrade_array", "plan[]=pro&interval[]=annual"}
        ] do
      state = fixture(name)
      conn = prepared(query)
      assert true == TrialGate.upgrade?(conn, %{})

      log =
        capture_log([level: :info], fn ->
          conn = RequireUser.call(conn, []) |> TrialUpgrade.call(now: @now, jti: @jti)
          assert conn.status == 302
          assert conn.resp_body == ""
          [location] = get_resp_header(conn, "location")
          assert URI.parse(location).host == "manager.example.test"
          assert URI.parse(location).path == "/auth/dawarich"
          token = URI.decode_query(URI.parse(location).query)["token"]
          [header, payload, signature] = String.split(token, ".")
          assert Base.url_decode64!(header, padding: false) == state["jwt"]["header_json"]
          assert Base.url_decode64!(payload, padding: false) == state["jwt"]["payload_json"]

          assert Base.encode16(Base.url_decode64!(signature, padding: false), case: :lower) ==
                   state["jwt"]["signature_hex"]
        end)

      [event] = Regex.scan(~r/\{"event".*\}/, log) |> List.flatten() |> Enum.map(&Jason.decode!/1)

      assert event == %{
               "event" => "trial_upgrades_viewed",
               "user_id" => 10001,
               "plan" => state["jwt"]["payload"]["plan"],
               "interval" => state["jwt"]["payload"]["interval"]
             }

      refute log =~ "token="
    end

    assert false == TrialGate.upgrade?(prepared("client=mobile"), %{})

    assert false ==
             TrialGate.upgrade?(prepared("") |> put_req_header("turbo-frame", "fixture"), %{})

    assert false == TrialGate.upgrade?(prepared("plan=pro&plan=lite"), %{})
    System.delete_env("JWT_SECRET_KEY")
    assert false == TrialGate.upgrade?(prepared(""), %{})
  end

  defp prepared(query) do
    url = "/trial/upgrade" <> if(query == "", do: "", else: "?" <> query)
    cookie = RailsUser.cookie(RailsUser.session(10001))

    Plug.Test.conn(:get, url)
    |> put_req_cookie("_dawarich_session", cookie)
    |> RailsAuth.call([])
    |> assign(:locale, "en")
  end

  defp fixture(name), do: Jason.decode!(File.read!("test/fixtures/trial_home/#{name}.json"))
end

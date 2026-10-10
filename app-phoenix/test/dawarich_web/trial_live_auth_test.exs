defmodule DawarichWeb.TrialLiveAuthTest do
  use ExUnit.Case, async: true
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.TrialLiveAuth

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: 10001,
      email: "a10-checkout@example.invalid",
      status: 3,
      settings: %{"timezone" => "Europe/Berlin"}
    })

    :ok
  end

  test "connected resume refuses a different or no-longer-pending account" do
    session = %{
      "rails_user_id" => 10001,
      "locale" => "en",
      "request_path" => "/trial/resume",
      "query_params" => %{}
    }

    stale = Accounts.get(10001)
    assert {:cont, _} = TrialLiveAuth.on_mount(:default, %{}, session, socket(stale, 10001))
    assert {:halt, changed} = TrialLiveAuth.on_mount(:default, %{}, session, socket(stale, 10002))
    assert changed.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}
    Repo.query!("UPDATE users SET status = 1 WHERE id = 10001", [], log: false)
    assert {:halt, active} = TrialLiveAuth.on_mount(:default, %{}, session, socket(stale, 10001))
    assert active.redirected == {:redirect, %{to: "/trial/resume", status: 302}}
    Repo.query!("UPDATE users SET status = 3 WHERE id = 10001", [], log: false)

    assert {:cont, authorized} =
             TrialLiveAuth.on_mount(:default, %{}, session, socket(stale, 10001))

    Repo.query!("UPDATE users SET status = 1 WHERE id = 10001", [], log: false)

    assert {:halt, refreshed} =
             Phoenix.LiveView.Lifecycle.handle_info(:navbar_refresh, authorized)

    assert refreshed.redirected == {:redirect, %{to: "/trial/resume", status: 302}}
  end

  defp socket(user, connected_id) do
    %Phoenix.LiveView.Socket{
      router: DawarichWeb.Router,
      view: DawarichWeb.TrialLive.Resume,
      endpoint: DawarichWeb.Endpoint,
      transport_pid: self(),
      assigns: %{__changed__: %{}, current_user: user, flash: %{}},
      private: %{
        connect_info: %{session: %{"rails_user_id" => connected_id}},
        lifecycle: %Phoenix.LiveView.Lifecycle{}
      }
    }
  end
end

defmodule DawarichWeb.AdminLiveAuthTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.AdminLiveAuth

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    original = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if original,
        do: System.put_env("SELF_HOSTED", original),
        else: System.delete_env("SELF_HOSTED")
    end)

    RailsUser.insert!(%{
      id: 10001,
      email: "a10-auth@example.invalid",
      admin: true,
      changelog_consent: 0,
      settings: %{"timezone" => "Europe/Berlin"}
    })

    :ok
  end

  test "admin LiveView reloads when the actor is demoted or deleted" do
    session = %{
      "rails_user_id" => 10001,
      "locale" => "en",
      "self_hosted" => true,
      "request_path" => "/settings/users",
      "query_params" => %{},
      "rails_csrf_token" => "CSRF",
      "base_url" => "http://www.example.com"
    }

    stale = Accounts.get(10001)
    Repo.query!("UPDATE users SET admin = false WHERE id = 10001", [], log: false)
    assert {:halt, socket} = AdminLiveAuth.on_mount(:admin, %{}, session, socket(stale))
    assert socket.redirected == {:redirect, %{to: "/settings/users", status: 302}}
    assert {:cont, background} = AdminLiveAuth.on_mount(:background, %{}, session, socket(stale))
    refute background.assigns.current_user.admin
    Repo.query!("UPDATE users SET admin = true WHERE id = 10001", [], log: false)

    assert {:cont, authorized} =
             AdminLiveAuth.on_mount(:admin, %{}, session, socket(Accounts.get(10001)))

    Repo.query!("UPDATE users SET admin = false WHERE id = 10001", [], log: false)

    assert {:halt, demoted} =
             Phoenix.LiveView.Lifecycle.handle_event(
               "changelog_consent",
               %{"decision" => "granted"},
               authorized
             )

    assert demoted.redirected == {:redirect, %{to: "/settings/users", status: 302}}

    assert Repo.query!("SELECT changelog_consent FROM users WHERE id = 10001", [], log: false).rows ==
             [[0]]

    Repo.query!("UPDATE users SET deleted_at = now() WHERE id = 10001", [], log: false)
    assert {:halt, deleted} = Phoenix.LiveView.Lifecycle.handle_info(:navbar_refresh, background)
    assert deleted.redirected == {:redirect, %{to: "/settings/users", status: 302}}
    assert {:halt, deleted_mount} = AdminLiveAuth.on_mount(:admin, %{}, session, socket(stale))
    assert deleted_mount.redirected == {:redirect, %{to: "/settings/users", status: 302}}
  end

  defp socket(user) do
    %Phoenix.LiveView.Socket{
      router: DawarichWeb.Router,
      view: DawarichWeb.AdminLive.Instance,
      endpoint: DawarichWeb.Endpoint,
      transport_pid: self(),
      assigns: %{__changed__: %{}, current_user: user, flash: %{}},
      private: %{
        connect_info: %{session: %{"rails_user_id" => 10001}},
        lifecycle: %Phoenix.LiveView.Lifecycle{}
      }
    }
  end
end

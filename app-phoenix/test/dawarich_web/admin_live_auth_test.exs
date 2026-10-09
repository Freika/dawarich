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
    assert socket.redirected == {:redirect, %{to: "/", status: 302}}
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

    assert demoted.redirected == {:redirect, %{to: "/", status: 302}}

    assert Repo.query!("SELECT changelog_consent FROM users WHERE id = 10001", [], log: false).rows ==
             [[0]]

    Repo.query!("UPDATE users SET deleted_at = now() WHERE id = 10001", [], log: false)
    assert {:halt, deleted} = Phoenix.LiveView.Lifecycle.handle_info(:navbar_refresh, background)
    assert deleted.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}
    assert {:halt, deleted_mount} = AdminLiveAuth.on_mount(:admin, %{}, session, socket(stale))
    assert deleted_mount.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}
  end

  test "refusals go to their own destination, never back to the same URL" do
    session = %{"rails_user_id" => 10001, "locale" => "en", "request_path" => "/admin/settings"}

    Repo.query!(
      "UPDATE users SET encrypted_password = 'changed-salt-0000000000000000000' WHERE id = 10001"
    )

    assert {:halt, stale} =
             AdminLiveAuth.on_mount(
               :admin,
               %{},
               session,
               socket(
                 Accounts.get(10001)
                 |> Map.put(:encrypted_password, "original-salt-000000000000000000")
               )
             )

    assert stale.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}

    Repo.query!(~s(UPDATE users SET settings = '{"timezone":"Not/AZone"}' WHERE id = 10001))
    current = Accounts.get(10001)
    assert {:halt, unsupported} = AdminLiveAuth.on_mount(:admin, %{}, session, socket(current))
    assert unsupported.redirected == {:redirect, %{to: "/settings/general", status: 302}}
  end

  test "native admin mode assigns a scope and drops an async result after demotion" do
    session = %{"rails_user_id" => 10001, "locale" => "en", "request_path" => "/admin/settings"}

    assert {:cont, socket} =
             AdminLiveAuth.on_mount(:native_admin, %{}, session, socket(Accounts.get(10001)))

    assert socket.assigns.native == true
    assert socket.assigns.current_scope.user.id == 10001

    Repo.query!("UPDATE users SET admin = false WHERE id = 10001", [], log: false)

    assert {:halt, dropped} =
             Phoenix.LiveView.Lifecycle.handle_async(:geocoding, {:ok, :done}, socket)

    assert dropped.redirected == {:redirect, %{to: "/", status: 302}}
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
        lifecycle: %Phoenix.LiveView.Lifecycle{},
        live_temp: %{}
      }
    }
  end
end

defmodule DawarichWeb.A12f3bD01Test do
  use ExUnit.Case, async: false
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.AdminLiveAuth

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    saved = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if saved, do: System.put_env("SELF_HOSTED", saved), else: System.delete_env("SELF_HOSTED")
    end)

    RailsUser.insert!(%{
      id: 31001,
      email: "admin-health@example.invalid",
      admin: true,
      settings: %{"timezone" => "UTC"}
    })

    :ok
  end

  @tag a12f3b_case: "D01b"
  test "job health connected event rejects changed eligibility" do
    user = Accounts.get(31001)

    session = %{
      "rails_user_id" => user.id,
      "locale" => "en",
      "self_hosted" => true,
      "request_path" => "/settings/background_jobs",
      "query_params" => %{},
      "rails_csrf_token" => "CSRF",
      "base_url" => "http://www.example.com"
    }

    socket = %Phoenix.LiveView.Socket{
      router: DawarichWeb.Router,
      view: DawarichWeb.SettingsLive.BackgroundJobs,
      endpoint: DawarichWeb.Endpoint,
      transport_pid: self(),
      assigns: %{__changed__: %{}, current_user: user, flash: %{}},
      private: %{
        connect_info: %{session: %{"rails_user_id" => user.id}},
        lifecycle: %Phoenix.LiveView.Lifecycle{}
      }
    }

    assert {:cont, mounted} = AdminLiveAuth.on_mount(:background, %{}, session, socket)
    assert {:ok, mounted} = DawarichWeb.SettingsLive.BackgroundJobs.mount(%{}, session, mounted)

    Repo.query!(
      "UPDATE users SET encrypted_password=$1 WHERE id=$2",
      ["$2a$04$" <> String.duplicate("rotated", 9), user.id],
      log: false
    )

    assert {:halt, revoked} = Phoenix.LiveView.Lifecycle.handle_info(:navbar_refresh, mounted)
    assert revoked.redirected == {:redirect, %{to: "/settings/background_jobs", status: 302}}
    assert revoked.assigns.health == nil
  end
end

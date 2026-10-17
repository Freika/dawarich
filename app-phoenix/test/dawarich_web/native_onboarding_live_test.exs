defmodule DawarichWeb.NativeOnboardingLiveTest do
  use Dawarich.DataCase, async: true
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Maps}
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  defmodule Host do
    use Phoenix.LiveView

    def mount(_params, %{"user_id" => id, "auto" => auto}, socket) do
      user = Accounts.get(id)
      navbar = Dawarich.Navbar.load(user, now: DateTime.utc_now(), self_hosted: true)

      {:ok,
       assign(socket,
         scope: Maps.principal(user, "en"),
         navbar: navbar,
         auto: auto
       )}
    end

    def render(assigns) do
      ~H"""
      <.live_component
        module={DawarichWeb.OnboardingLiveComponent}
        id="onboarding"
        scope={@scope}
        navbar={@navbar}
        locale="en"
        base_url="http://localhost"
        rails_csrf_token="token"
        auto_open={@auto}
      />
      """
    end
  end

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "onboard-live-#{id}@dawarich.test",
      api_key: "synthetic-onboard-key"
    })

    %{id: id}
  end

  test "auto-open close persists completion through the owner scope", %{id: id} do
    {:ok, view, html} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host,
        session: %{"user_id" => id, "auto" => true}
      )

    assert html =~ ~s(phx-hook="Onboarding")
    assert has_element?(view, "dialog#getting_started[data-auto='true']")
    refute render(view) =~ "synthetic-onboard-key"

    view |> element("dialog#getting_started") |> render_hook("onboarding:complete", %{})
    assert completed(id) == true
    refute has_element?(view, "dialog#getting_started[data-auto='true']")
  end

  test "manual-only pages never auto-open and revoked owners cannot complete", %{id: id} do
    {:ok, view, _} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host,
        session: %{"user_id" => id, "auto" => false}
      )

    assert has_element?(view, "dialog#getting_started[data-auto='false']")

    rows("UPDATE users SET encrypted_password=$1 WHERE id=$2", [
      String.duplicate("rotated", 10),
      id
    ])

    view |> element("dialog#getting_started") |> render_hook("onboarding:complete", %{})
    assert completed(id) == nil
  end

  defp completed(id),
    do:
      rows("SELECT settings->'onboarding_completed' FROM users WHERE id=$1", [id]) |> hd() |> hd()
end

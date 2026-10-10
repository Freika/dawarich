defmodule DawarichWeb.AdminUsersLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Repo, Accounts}
  alias Dawarich.Test.{NativeAdminUI, RailsUser}
  @endpoint DawarichWeb.Endpoint
  setup do
    NativeAdminUI.setup!()
  end

  test "search and pagination preserve URL state without resetting an open credential form", c do
    for id <- 10803..10829 do
      RailsUser.insert!(%{
        id: id,
        email: "tie-#{id}@example.invalid",
        created_at: ~N[2026-01-01 00:00:00]
      })
    end

    {:ok, view, _} = live(NativeAdminUI.conn(c.actor), "/settings/users")
    render_hook(view, "open_create", %{})

    form_id =
      view
      |> element("#create_user form")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("form")
      |> LazyHTML.attribute("id")

    view |> element("a[rel=next]", "»") |> render_click()
    assert_patch(view, "/settings/users?page=2")
    assert has_element?(view, "tr[data-user-id='10803']")
    assert :sys.get_state(view.pid).socket.assigns.create_open

    assert view
           |> element("#create_user form")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("form")
           |> LazyHTML.attribute("id") == form_id

    render_patch(view, "/settings/users")
    assert has_element?(view, "tr[data-user-id='10829']")
    view |> form("#users-search", %{"search" => "tie-10803"}) |> render_submit()
    assert_patch(view, "/settings/users?search=tie-10803")
    assert has_element?(view, "input[name=search][value='tie-10803']")
    assert has_element?(view, "tr[data-user-id='10803']")
    refute has_element?(view, "tr[data-user-id='10829']")
    view |> element("#clear-users-search") |> render_click()
    assert_patch(view, "/settings/users")
    RailsUser.insert!(%{id: 10830, email: "literal%_@example.invalid"})
    view |> form("#users-search", %{"search" => "%_"}) |> render_submit()
    assert has_element?(view, "tr[data-user-id='10830']")
    refute has_element?(view, "tr[data-user-id='10802']")
    assert NativeAdminUI.labels(render(view)) == []
  end

  test "registration event persists source value and existing notice", c do
    {:ok, view, _} = live(NativeAdminUI.conn(c.actor), "/settings/users")

    for {value, expected} <- [{"0", false}, {"1", true}] do
      html =
        view
        |> form("#phx-registration-settings")
        |> render_submit(%{"registration_enabled" => value})

      assert Dawarich.Auth.RegistrationSetting.fetch() == {:ok, expected}

      assert html =~
               NativeAdminUI.escaped(
                 "controllers.settings.users.user_registration_has_been_status",
                 %{status: if(expected, do: "enabled", else: "disabled")}
               )

      assert has_element?(
               view,
               "input[type=checkbox][value='1']#{if expected, do: "[checked]", else: ":not([checked])"}"
             )
    end
  end

  test "nil registration reads unchecked without rewriting and missing rows fail unavailable",
       c do
    Dawarich.State.put_registration_enabled(Repo, nil)
    {:ok, view, _} = live(NativeAdminUI.conn(c.actor), "/settings/users")
    assert has_element?(view, "input[type=checkbox]:not([checked])")
    assert Dawarich.Auth.RegistrationSetting.fetch() == {:ok, nil}
    Repo.query!("DELETE FROM phoenix.registration_setting")

    assert render_patch(view, "/settings/users?search=none") =~
             NativeAdminUI.escaped("controllers.application.admin_action_failed")
  end

  test "every users index event and parameter change refuses stale admin identity", c do
    for action <- [:search, :registration, :params, :dialog] do
      Repo.query!("UPDATE users SET admin=true WHERE id=$1", [c.actor.id])
      {:ok, view, _} = live(NativeAdminUI.conn(Accounts.get(c.actor.id)), "/settings/users")
      Repo.query!("UPDATE users SET admin=false WHERE id=$1", [c.actor.id])
      socket = :sys.get_state(view.pid).socket

      if action == :params do
        assert {:halt, _} =
                 Phoenix.LiveView.Lifecycle.handle_params(
                   %{"page" => "2"},
                   "http://www.example.com/settings/users?page=2",
                   socket
                 )
      else
        event =
          %{search: "search", registration: "update_registration", dialog: "open_create"}[action]

        assert {:halt, _} = Phoenix.LiveView.Lifecycle.handle_event(event, %{}, socket)
      end

      case action do
        :search ->
          render_hook(view, "search", %{"search" => "none"})

        :registration ->
          render_hook(view, "update_registration", %{"registration_enabled" => "0"})

        :params ->
          render_patch(view, "/settings/users?page=2")

        :dialog ->
          render_hook(view, "open_create", %{})
      end

      assert_redirect(view, "/")
      assert Dawarich.Auth.RegistrationSetting.fetch() == {:ok, true}
    end

    Repo.query!("UPDATE users SET admin=true WHERE id=$1", [c.actor.id])
    {:ok, view, _} = live(NativeAdminUI.conn(c.actor), "/settings/users")

    Repo.query!("UPDATE users SET encrypted_password='changed-salt-synthetic' WHERE id=$1", [
      c.actor.id
    ])

    render_hook(view, "open_create", %{})
    assert_redirect(view, "/users/sign_in")
  end

  test "users index mount counts are observable and bounded", c do
    {conn, static} =
      NativeAdminUI.queries(fn -> get(NativeAdminUI.conn(c.actor), "/settings/users") end)

    {{:ok, view, _}, connected} = NativeAdminUI.queries(fn -> live(conn) end)

    {_, event} =
      NativeAdminUI.queries(fn -> render_patch(view, "/settings/users?search=none") end)

    IO.puts(
      "users index queries static=#{length(static)} connected=#{length(connected)} params=#{length(event)}"
    )

    assert length(static) in 1..28
    assert length(connected) in 1..16
    assert length(event) in 1..12
    GenServer.stop(view.pid)
  end
end

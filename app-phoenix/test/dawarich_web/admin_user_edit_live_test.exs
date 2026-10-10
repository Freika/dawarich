defmodule DawarichWeb.AdminUserEditLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.NativeAdminUI
  @endpoint DawarichWeb.Endpoint
  setup do
    NativeAdminUI.setup!()
  end

  defp edit(c, id), do: live(NativeAdminUI.conn(c.actor), "/settings/users/#{id}/edit")

  test "edit values and exact translated status options preserve a blank password hash", c do
    {conn, static} =
      NativeAdminUI.queries(fn ->
        get(NativeAdminUI.conn(c.actor), "/settings/users/#{c.target.id}/edit")
      end)

    {{:ok, initial, _}, connected} = NativeAdminUI.queries(fn -> live(conn) end)
    IO.puts("user edit queries static=#{length(static)} connected=#{length(connected)}")
    assert length(static) in 1..14
    assert length(connected) in 1..9
    GenServer.stop(initial.pid)

    for {status, value} <- Enum.with_index(~w(inactive active trial pending_payment)) do
      Repo.query!("UPDATE users SET status=$2 WHERE id=$1", [c.target.id, value])
      {:ok, view, html} = edit(c, c.target.id)
      assert :sys.get_state(view.pid).socket.assigns.native

      options =
        html |> LazyHTML.from_fragment() |> LazyHTML.query("select[name='user[status]'] option")

      assert LazyHTML.attribute(options, "value") == ~w(inactive active trial pending_payment)

      assert Enum.map(options, &(LazyHTML.text(&1) |> String.trim())) == [
               "Inactive",
               "Active",
               "Trial",
               "Pending payment"
             ]

      assert has_element?(view, "option[value='#{status}'][selected]")
      assert NativeAdminUI.labels(html) == []
      GenServer.stop(view.pid)
    end

    {:ok, view, _} = edit(c, c.target.id)
    hash = Accounts.get(c.target.id).encrypted_password
    before = Accounts.get(c.actor.id)

    html =
      view
      |> form("form.edit_user")
      |> render_submit(%{
        "user" => %{
          "email" => "updated-ui@example.invalid",
          "password" => "",
          "admin" => "0",
          "status" => "active"
        }
      })

    assert Accounts.get(c.target.id).encrypted_password == hash
    assert Accounts.get(c.target.id).email == "updated-ui@example.invalid"
    assert Accounts.get(c.target.id).status == 1
    assert Accounts.get(c.actor.id) == before

    assert html =~
             NativeAdminUI.escaped("controllers.settings.users.user_was_successfully_updated")
  end

  test "edit event never keeps the password after failure or success", c do
    {:ok, view, _} = edit(c, c.target.id)

    for email <- ["bad", "changed-ui@example.invalid"] do
      before = :sys.get_state(view.pid).socket.assigns.form_version

      render_hook(view, "update_user", %{
        "user" => %{"email" => email, "password" => "synthetic-edit-password"}
      })

      assert String.contains?(
               inspect(:sys.get_state(view.pid), limit: :infinity),
               "synthetic-edit-password"
             ) == false

      assert String.contains?(NativeAdminUI.html(view), "synthetic-edit-password") == false
      assert has_element?(view, "input[type=password][value='']")
      refute has_element?(view, "form.edit_user[phx-change]")
      assert :sys.get_state(view.pid).socket.assigns.form_version > before
      assert has_element?(view, "input[name='user[email]'][value='#{email}']")
    end

    assert Accounts.get(c.target.id).email == "changed-ui@example.invalid"
    assert Accounts.get(c.target.id).encrypted_password != c.target.encrypted_password
  end

  test "self password update signs the actor out instead of keeping the socket", c do
    {:ok, view, _} = edit(c, c.actor.id)
    {:ok, other, _} = live(NativeAdminUI.conn(c.actor), "/settings/users")
    render_hook(view, "update_user", %{"user" => %{"password" => "synthetic-self-password"}})
    assert_redirect(view, "/users/sign_in")
    assert Accounts.get(c.actor.id).encrypted_password != c.actor.encrypted_password
    render_hook(other, "open_create", %{})
    assert_redirect(other, "/users/sign_in")
  end

  test "permitted self demotion cannot perform another admin action", c do
    Repo.query!("UPDATE users SET admin=true WHERE id=$1", [c.target.id])
    {:ok, view, _} = edit(c, c.actor.id)
    {:ok, other, _} = live(NativeAdminUI.conn(c.actor), "/settings/users")
    render_hook(view, "update_user", %{"user" => %{"admin" => "0"}})
    assert_redirect(view, "/")
    refute Accounts.get(c.actor.id).admin

    render_hook(other, "create_user", %{
      "user" => %{
        "email" => "blocked-ui@example.invalid",
        "password" => "synthetic-blocked-password"
      }
    })

    assert_redirect(other, "/")
    assert Repo.query!("SELECT count(*) FROM users").rows == [[2]]
  end

  test "sole admin role and status changes stay blocked with Rails alerts", c do
    {:ok, view, _} = edit(c, c.actor.id)

    for {params, key} <- [
          {%{"admin" => "0"}, "cannot_remove_last_admin_role"},
          {%{"status" => "inactive"}, "cannot_disable_last_admin"}
        ] do
      html = render_hook(view, "update_user", %{"user" => params})
      assert html =~ NativeAdminUI.escaped("controllers.settings.users." <> key)
      assert Accounts.get(c.actor.id).admin
      assert Accounts.get(c.actor.id).status == 1
      assert Process.alive?(view.pid)
    end
  end

  test "OIDC native user writes refuse clearly while reads stay available", c do
    previous = Map.new(~w(OIDC_CLIENT_ID OIDC_CLIENT_SECRET), &{&1, System.get_env(&1)})
    System.put_env("OIDC_CLIENT_ID", "synthetic-oidc")
    System.put_env("OIDC_CLIENT_SECRET", "synthetic-oidc-secret")

    on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    {:ok, index, _} = live(NativeAdminUI.conn(c.actor), "/settings/users")
    alert = NativeAdminUI.escaped("controllers.application.admin_writes_unavailable_with_oidc")

    assert render_hook(index, "create_user", %{
             "user" => %{
               "email" => "oidc-refused@example.invalid",
               "password" => "synthetic-oidc-password"
             }
           }) =~ alert

    assert render_hook(index, "update_registration", %{"registration_enabled" => "0"}) =~ alert
    render_hook(index, "open_delete", %{"id" => to_string(c.target.id)})
    assert render_hook(index, "delete_user", %{}) =~ alert
    {:ok, show, _} = live(NativeAdminUI.conn(c.actor), "/settings/users/#{c.target.id}")
    render_hook(show, "open_rotate", %{})
    assert render_hook(show, "rotate_api_key", %{}) =~ alert
    assert render_hook(show, "send_password_reset", %{}) =~ alert
    {:ok, edit, _} = edit(c, c.target.id)

    assert render_hook(edit, "update_user", %{
             "user" => %{"email" => "blocked-oidc@example.invalid"}
           }) =~ alert

    assert Accounts.get(c.target.id).email == c.target.email
    assert Accounts.get(c.target.id).api_key == c.target.api_key
    assert Repo.query!("SELECT count(*) FROM users").rows == [[2]]
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
    assert Dawarich.Auth.RegistrationSetting.fetch() == {:ok, true}
  end

  test "edit handler crashes produce a generic alert without logging submitted values", c do
    {:ok, view, _} = edit(c, c.target.id)

    Application.put_env(:dawarich, Dawarich.Admin.Users, %{
      repo: Dawarich.Test.CredentialCrashRepo
    })

    on_exit(fn -> Application.put_env(:dawarich, Dawarich.Admin.Users, %{}) end)

    logs =
      capture_log(fn ->
        assert render_hook(view, "update_user", %{
                 "user" => %{
                   "email" => "synthetic-edit-crash@example.invalid",
                   "password" => "synthetic-edit-crash-password"
                 }
               }) =~ NativeAdminUI.escaped("controllers.application.admin_action_failed")
      end)

    assert logs =~ "admin users call failed: ArgumentError"
    refute logs =~ "synthetic-edit-crash"
    refute inspect(:sys.get_state(view.pid), limit: :infinity) =~ "synthetic-edit-crash-password"
  end
end

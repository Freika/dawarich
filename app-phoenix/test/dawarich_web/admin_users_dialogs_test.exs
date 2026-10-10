defmodule Dawarich.Test.LastAdminUIProbe do
  alias Dawarich.Repo
  defdelegate transaction(fun), to: Repo
  defdelegate rollback(reason), to: Repo

  def query!(sql, params, opts \\ []) do
    if sql == "SELECT admin FROM users WHERE id=$1 AND deleted_at IS NULL" and params == [10802] do
      Repo.query!("UPDATE users SET admin=false WHERE id=10801", [], log: false)
    end

    Repo.query!(sql, params, opts)
  end
end

defmodule DawarichWeb.AdminUsersDialogsTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Admin.Users
  alias Dawarich.Test.NativeAdminUI
  @endpoint DawarichWeb.Endpoint

  setup do
    c = NativeAdminUI.setup!()
    previous = Application.get_env(:dawarich, Users)
    Application.put_env(:dawarich, Users, %{})

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, Users, previous),
        else: Application.delete_env(:dawarich, Users)
    end)

    Dawarich.Jobs.Ownership.put!(Repo, "command:users.destroy", :oban)
    c
  end

  test "create dialog submits credentials as one event and never keeps the password", c do
    {:ok, view, _} = live(NativeAdminUI.conn(c.actor), "/settings/users")
    render_hook(view, "open_create", %{})
    before = :sys.get_state(view.pid).socket.assigns.form_version

    for email <- ["bad", "new-ui@example.invalid"] do
      render_hook(view, "create_user", %{
        "user" => %{"email" => email, "password" => "synthetic-create-password"}
      })

      assert String.contains?(
               inspect(:sys.get_state(view.pid), limit: :infinity),
               "synthetic-create-password"
             ) == false

      assert String.contains?(NativeAdminUI.html(view), "synthetic-create-password") == false
      assert has_element?(view, "#create-user-password[value='']")
      refute has_element?(view, "#create_user form[phx-change]")
    end

    assert :sys.get_state(view.pid).socket.assigns.form_version > before

    assert render(view) =~
             NativeAdminUI.escaped("controllers.settings.users.user_was_successfully_created")

    assert has_element?(view, "tbody", "new-ui@example.invalid")
    assert_push_event(view, "close-dialog", %{id: "create_user"})
  end

  test "create validation errors stay in the open dialog with the email kept and passwords empty",
       c do
    {:ok, view, _} = live(NativeAdminUI.conn(c.actor), "/settings/users")
    render_hook(view, "open_create", %{})

    html =
      view
      |> form("#create_user form")
      |> render_submit(%{"user" => %{"email" => c.target.email, "password" => "short"}})

    assert html =~ "already been taken"
    assert has_element?(view, "#create-user-email[value='#{c.target.email}']")
    assert has_element?(view, "#create-user-password[value='']")
    assert :sys.get_state(view.pid).socket.assigns.create_open
    assert Repo.query!("SELECT count(*) FROM users").rows == [[2]]
  end

  test "cancel delete queues nothing", c do
    {:ok, view, _} = live(NativeAdminUI.conn(c.actor), "/settings/users")
    render_hook(view, "open_delete", %{"id" => to_string(c.target.id)})
    view |> element("#cancel-delete") |> render_click()
    assert Accounts.get(c.target.id) != nil
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
    assert :sys.get_state(view.pid).socket.assigns.delete_id == nil
  end

  test "delete confirmation soft-deletes only the selected target and queues one durable cleanup",
       c do
    {:ok, view, _} = live(NativeAdminUI.conn(c.actor), "/settings/users")
    render_hook(view, "open_delete", %{"id" => to_string(c.target.id)})
    html = view |> element("#confirm-delete") |> render_click()
    assert Accounts.get(c.target.id) == nil
    assert Accounts.get(c.actor.id) != nil

    assert Repo.query!("SELECT command_type,payload FROM job_outbox").rows == [
             ["users.destroy", %{"user_id" => c.target.id}]
           ]

    assert html =~
             NativeAdminUI.escaped(
               "controllers.settings.users.user_deletion_has_been_initiated_the_account_will_be_fully"
             )

    render_hook(view, "delete_user", %{"id" => to_string(c.actor.id)})
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[1]]
    render_hook(view, "open_delete", %{"id" => to_string(c.target.id)})
    assert_redirect(view, "/settings/users")
  end

  test "deleting yourself or the last active admin is refused without effects", c do
    Repo.query!("UPDATE users SET admin=true WHERE id=$1", [c.target.id])
    {:ok, view, _} = live(NativeAdminUI.conn(c.actor), "/settings/users")
    render_hook(view, "open_delete", %{"id" => to_string(c.actor.id)})
    html = render_hook(view, "delete_user", %{"id" => to_string(c.actor.id)})

    assert html =~
             NativeAdminUI.escaped(
               "controllers.application.you_are_not_authorized_to_perform_this_action"
             )

    assert Accounts.get(c.actor.id) != nil
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
    Repo.query!("UPDATE users SET admin=true WHERE id=$1", [c.target.id])
    Application.put_env(:dawarich, Users, %{repo: Dawarich.Test.LastAdminUIProbe})
    render_hook(view, "open_delete", %{"id" => to_string(c.target.id)})
    html = render_hook(view, "delete_user", %{})

    assert html =~
             NativeAdminUI.escaped(
               "controllers.application.you_are_not_authorized_to_perform_this_action"
             )

    assert Process.alive?(view.pid)
    assert Accounts.get(c.target.id) != nil
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
  end

  test "family deletion refusal stays in place and failed enqueue can retry", c do
    Dawarich.Test.RailsUser.insert!(%{id: 10803, email: "family-member@example.invalid"})

    Repo.query!(
      "INSERT INTO families(id,creator_id,name,created_at,updated_at) VALUES(10802,10802,'Synthetic',now(),now())"
    )

    Repo.query!(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES(10802,10802,0,now(),now()),(10802,10803,1,now(),now())"
    )

    {:ok, view, _} = live(NativeAdminUI.conn(c.actor), "/settings/users")
    render_hook(view, "open_delete", %{"id" => to_string(c.target.id)})
    html = render_hook(view, "delete_user", %{})

    assert html =~
             NativeAdminUI.escaped(
               "controllers.settings.users.cannot_delete_account_while_being_owner_of_a_family_which"
             )

    assert Accounts.get(c.target.id) != nil
    Repo.query!("DELETE FROM family_memberships WHERE user_id=10803")
    Application.put_env(:dawarich, Users, %{enqueue_destroy: fn _ -> {:error, :failed} end})

    assert render_hook(view, "delete_user", %{}) =~
             NativeAdminUI.escaped("controllers.application.admin_action_failed")

    assert Accounts.get(c.target.id) != nil
    Application.put_env(:dawarich, Users, %{})
    render_hook(view, "delete_user", %{})
    assert Accounts.get(c.target.id) == nil
  end

  test "credential handler crashes produce a generic alert without logging submitted values",
       c do
    {:ok, view, _} = live(NativeAdminUI.conn(c.actor), "/settings/users")
    Application.put_env(:dawarich, Users, %{repo: Dawarich.Test.CredentialCrashRepo})
    render_hook(view, "open_create", %{})

    logs =
      capture_log(fn ->
        assert render_hook(view, "create_user", %{
                 "user" => %{
                   "email" => "synthetic-crash@example.invalid",
                   "password" => "synthetic-crash-password"
                 }
               }) =~ NativeAdminUI.escaped("controllers.application.admin_action_failed")
      end)

    assert logs =~ "admin users call failed: ArgumentError"
    refute logs =~ "synthetic-crash"
    refute inspect(:sys.get_state(view.pid), limit: :infinity) =~ "synthetic-crash-password"
  end

  test "open create and delete dialogs have exactly one label per control" do
    html =
      render_component(&DawarichWeb.AdminUserDialogs.dialogs/1,
        locale: "en",
        rows: [%{id: 10802, email: "synthetic@example.invalid"}],
        create_email: "",
        form_version: 0,
        delete_id: 10802,
        open: true
      )

    assert Enum.count(LazyHTML.query(LazyHTML.from_fragment(html), "dialog[open]")) == 2
    assert NativeAdminUI.labels(html) == []
  end
end

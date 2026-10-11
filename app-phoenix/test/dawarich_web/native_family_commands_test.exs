defmodule DawarichWeb.NativeFamilyCommandsTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    id = System.unique_integer([:positive])

    for user <- [id, id + 1, id + 2] do
      RailsUser.insert!(%{
        id: user,
        email: "family-command-#{user}@dawarich.test",
        settings: %{"timezone" => "UTC"}
      })
    end

    at = NaiveDateTime.utc_now()

    Repo.insert_all("families", [
      %{id: id, creator_id: id, name: "Native command family", created_at: at, updated_at: at}
    ])

    Repo.insert_all(
      "family_memberships",
      for(
        {user, role} <- [{id, 0}, {id + 1, 1}],
        do: %{id: user, family_id: id, user_id: user, role: role, created_at: at, updated_at: at}
      )
    )

    %{id: id}
  end

  test "native family sharing updates only owned consent and refuses a withdrawn membership", %{
    id: id
  } do
    {:ok, view, _} = open(id)
    assert has_element?(view, "#native-family-sharing")

    view
    |> form("#native-family-sharing",
      sharing: %{enabled: "true", duration: "1h", share_history: "true", history_window: "7d"}
    )
    |> render_change()

    sharing = Dawarich.Accounts.get(id).settings["family"]["location_sharing"]
    assert sharing["enabled"] == true
    assert sharing["share_history"] == true
    assert sharing["history_window"] == "7d"
    refute Dawarich.Accounts.get(id + 1).settings["family"]

    assert has_element?(
             view,
             "#native-family-sharing input[name='sharing[enabled]'][type=checkbox][checked]"
           )

    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [id], log: false)
    render_change(view, "family:sharing", %{"sharing" => %{"enabled" => "false"}})
    assert Dawarich.Accounts.get(id).settings["family"]["location_sharing"]["enabled"] == true
    refute has_element?(view, "#family-shell")
  end

  test "successive native consent changes own distinct flash identities after dismissal", %{
    id: id
  } do
    {:ok, view, _} = open(id)
    render_change(view, "family:sharing", %{"sharing" => %{"enabled" => "true"}})

    first =
      render(view)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#flash-messages [role=alert]")
      |> LazyHTML.attribute("id")

    assert [first_id] = first
    assert has_element?(view, "##{first_id}", "Location sharing enabled")
    render_click(view, "lv:clear-flash", %{"key" => "success"})
    refute has_element?(view, "##{first_id}")
    render_change(view, "family:sharing", %{"sharing" => %{"enabled" => "false"}})

    assert [second_id] =
             render(view)
             |> LazyHTML.from_document()
             |> LazyHTML.query("#flash-messages [role=alert]")
             |> LazyHTML.attribute("id")

    refute second_id == first_id
    assert has_element?(view, "##{second_id}", "Location sharing disabled")
    assert Dawarich.Accounts.get(id).settings["family"]["location_sharing"]["enabled"] == false
  end

  test "native map family confirmation consumes one admitted action and cancellation has no effects",
       %{id: id} do
    {:ok, view, _} = open(id)
    view |> element("[data-family-action=remove_member]") |> render_click()
    assert has_element?(view, "#family-confirm[data-pending=true]", "family-command-#{id + 1}")
    render_click(view, "family_cancel_confirm", %{})
    render_click(view, "family_confirm", %{})
    assert count("family_memberships", "user_id", id + 1) == 1
    view |> element("[data-family-action=remove_member]") |> render_click()
    render_click(view, "family_confirm", %{})
    render_click(view, "family_confirm", %{})
    assert count("family_memberships", "user_id", id + 1) == 0
    refute has_element?(view, "#family-confirm[data-pending=true]")
    assert_push_event(view, "close-dialog", %{id: "family-confirm"})
    assert has_element?(view, "[role=alert]", "removed")
  end

  test "native family member removal preserves foreign memberships and refuses nonowner effects",
       %{id: id} do
    at = NaiveDateTime.utc_now()

    Repo.insert_all("families", [
      %{id: id + 2, creator_id: id + 2, name: "Foreign family", created_at: at, updated_at: at}
    ])

    Repo.insert_all("family_memberships", [
      %{id: id + 2, family_id: id + 2, user_id: id + 2, role: 0, created_at: at, updated_at: at}
    ])

    {:ok, member, _} = open(id + 1)
    render_click(member, "family:member", %{"id" => to_string(id)})
    assert count("family_memberships", "user_id", id) == 1
    {:ok, owner, _} = open(id)
    assert has_element?(owner, "[data-family-action=remove_member]")
    render_click(owner, "family:member", %{"id" => to_string(id + 2)})
    assert count("family_memberships", "user_id", id + 2) == 1
    render_click(owner, "family:member", %{"id" => to_string(id + 1)})
    assert count("family_memberships", "user_id", id + 1) == 0
    refute has_element?(owner, "[data-family-member-id='#{id + 1}']")
    assert has_element?(owner, "[role=alert]", "removed")
  end

  test "native family invitations create cancel and refuse invalid owner drafts", %{id: id} do
    Dawarich.Jobs.Ownership.put!(Repo, "command:mail.family_invitation", :oban)
    {:ok, view, _} = open(id)
    assert has_element?(view, "#native-family-invite")

    view
    |> form("#native-family-invite", family_invitation: %{email: "new-family@example.test"})
    |> render_submit()

    [[invitation_id, token]] =
      Repo.query!("SELECT id,token FROM family_invitations WHERE family_id=$1", [id], log: false).rows

    assert has_element?(view, "#native-family-invitations", "new-family@example.test")
    assert count("job_outbox", "command_type", "mail.family_invitation") == 1
    render_click(view, "family:cancel", %{"id" => "999999999999"})

    assert Repo.query!("SELECT status FROM family_invitations WHERE token=$1", [token],
             log: false
           ).rows == [[0]]

    render_click(view, "family:cancel", %{"id" => to_string(invitation_id)})

    assert Repo.query!("SELECT status FROM family_invitations WHERE token=$1", [token],
             log: false
           ).rows == [[3]]

    view |> form("#native-family-invite", family_invitation: %{email: "bad"}) |> render_submit()
    assert count("family_invitations", "family_id", id) == 1
    assert has_element?(view, "[role=alert]")
  end

  test "native family location requests keep cooldown ownership and local refusal feedback", %{
    id: id
  } do
    Dawarich.Jobs.Ownership.put!(Repo, "command:mail.family_location_request", :oban)
    {:ok, view, _} = open(id)
    assert has_element?(view, "[phx-click='family:request'][phx-value-id='#{id + 1}']")
    render_click(view, "family:request", %{"id" => to_string(id + 2)})
    assert count("family_location_requests", "family_id", id) == 0
    render_click(view, "family:request", %{"id" => to_string(id + 1)})
    assert count("family_location_requests", "family_id", id) == 1
    render_click(view, "family:request", %{"id" => to_string(id + 1)})
    assert count("family_location_requests", "family_id", id) == 1
    assert has_element?(view, "[role=alert]")
    assert :sys.get_state(view.pid).socket.assigns.flash["error"] != ""
  end

  test "native family departure and deletion retain confirmation refusal and navigation", %{
    id: id
  } do
    {:ok, owner, _} = open(id)
    assert has_element?(owner, "[data-family-action=delete]")
    render_click(owner, "family:destroy", %{})
    assert count("families", "id", id) == 1
    assert has_element?(owner, "[role=alert]", "members")
    {:ok, member, _} = open(id + 1)

    assert has_element?(
             member,
             "[data-family-action=remove_member]"
           )

    render_click(member, "family:member", %{"id" => to_string(id + 1)})
    assert_redirect(member, "/family/new")
    assert count("family_memberships", "user_id", id + 1) == 0
    render_click(owner, "family:destroy", %{})
    assert_redirect(owner, "/family/new")
    assert count("families", "id", id) == 0
  end

  test "native family commands refuse malformed payloads without effects or owner loss", %{id: id} do
    {:ok, view, _} = open(id)
    render_click(view, "family_unknown", %{})

    for payload <- ["malformed", nil, false, []] do
      render_change(view, "family:sharing", %{"sharing" => payload})
      assert has_element?(view, "#family-shell")
      refute Dawarich.Accounts.get(id).settings["family"]
      render_submit(view, "family:invite", %{"family_invitation" => payload})
      assert has_element?(view, "[role=alert]")
      assert count("family_invitations", "family_id", id) == 0
      render_click(view, "family:cancel", %{"token" => payload})
      assert has_element?(view, "#family-shell")
    end
  end

  defp count(table, column, value),
    do:
      Repo.query!("SELECT count(*) FROM #{table} WHERE #{column}=$1", [value], log: false).rows
      |> hd()
      |> hd()

  defp open(id) do
    RailsUser.signed_in(id)
    |> RailsUser.connecting_as(id)
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
    |> Map.merge(%{request_path: "/family", path_info: ["family"], query_string: ""})
    |> Plug.Conn.fetch_query_params()
    |> Dawarich.Test.NativeM6IntegrationRouter.call([])
    |> live()
  end
end

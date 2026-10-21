defmodule DawarichWeb.NativeFamilyPresentationTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    id = System.unique_integer([:positive])

    for user <- [id, id + 1] do
      RailsUser.insert!(%{
        id: user,
        email: "native-family-#{user}@dawarich.test",
        api_key: "synthetic-family-private-key",
        settings: %{"timezone" => "UTC"}
      })
    end

    stamp = NaiveDateTime.utc_now()

    Repo.insert_all("families", [
      %{id: id, creator_id: id, name: "Family <admitted>", created_at: stamp, updated_at: stamp}
    ])

    Repo.insert_all(
      "family_memberships",
      for(
        {user, role} <- [{id, 0}, {id + 1, 1}],
        do: %{
          id: user,
          family_id: id,
          user_id: user,
          role: role,
          created_at: stamp,
          updated_at: stamp
        }
      )
    )

    %{id: id}
  end

  test "native family host preserves admitted members map chrome and fresh membership refusal", %{
    id: id
  } do
    {:ok, view, html} = open(id)
    assert has_element?(view, "#family-shell h1", "Family <admitted>")
    assert has_element?(view, "#native-family-map[phx-hook=Family]")

    assert has_element?(
             view,
             "[data-native-family-member-id='#{id + 1}']",
             "native-family-#{id + 1}@dawarich.test"
           )

    assert has_element?(view, "#mobile-navigation-menu")
    refute String.contains?(html, "synthetic-family-private-key")

    refute has_element?(
             view,
             "[data-controller], [data-action], turbo-frame, turbo-cable-stream-source"
           )

    Repo.query!("UPDATE families SET name=$1 WHERE id=$2", ["Family updated", id], log: false)
    render_hook(view, "map:ready", %{})
    assert has_element?(view, "#family-shell h1", "Family updated")
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [id], log: false)
    render_hook(view, "map:ready", %{})
    refute has_element?(view, "#family-shell")
    refute has_element?(view, "#mobile-navigation-menu")
    assert_push_event(view, "map:clear", %{code: "not_found"})
    assert :sys.get_state(view.pid).socket.assigns.page_title == nil
  end

  @tag family_application_shell: true
  test "family application chrome and footer disappear with fresh membership refusal", %{id: id} do
    {:ok, view, _} = open(id)
    assert :sys.get_state(view.pid).socket.assigns.body_class == "min-h-screen flex flex-col"

    assert :sys.get_state(view.pid).socket.assigns.viewport ==
             "width=device-width,initial-scale=1"

    assert has_element?(view, ".container.mx-auto.flex.flex-col.flex-1 > .navbar")
    assert has_element?(view, ".container > .w-full.px-4 > .flex > #family-shell.contents")
    assert has_element?(view, ".container > .mt-auto footer")
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [id], log: false)
    render_hook(view, "map:ready", %{})
    refute has_element?(view, ".container, .navbar, footer, #native-family-map, #getting_started")
  end

  @tag family_unique_inputs: true
  test "native family onboarding and sidebar have distinct invitation email controls", %{id: id} do
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [id + 1], log: false)
    {:ok, view, _} = open(id)
    assert has_element?(view, "#native-family-onboarding-email[name='family_invitation[email]']")
    assert has_element?(view, "#family_invitation_email[name='family_invitation[email]']")
  end

  test "native family setup guidance follows fresh invitations and sharing with one editor", %{
    id: id
  } do
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [id + 1], log: false)
    Dawarich.Jobs.Ownership.put!(Repo, "command:mail.family_invitation", :oban)
    {:ok, view, _} = open(id)
    assert has_element?(view, "#native-family-onboarding-invite input[type=submit][value=Invite]")

    assert render(view)
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#native-family-invite")
           |> Enum.count() == 1

    view
    |> form("#native-family-invite", family_invitation: %{email: "family-setup@example.test"})
    |> render_submit()

    assert has_element?(view, "#family-getting-started", "sharing")

    view
    |> render_hook("family:sharing", %{sharing: %{enabled: "true", duration: "permanent"}})

    refute has_element?(view, "#family-getting-started")

    view
    |> render_hook("family:sharing", %{sharing: %{enabled: "false", duration: "permanent"}})

    assert has_element?(view, "#family-getting-started", "sharing")
  end

  test "native family trial guidance retains the source expiry date for an admitted trial", %{
    id: id
  } do
    until = DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second)

    Repo.query!(
      "UPDATE users SET status=2,active_until=$2 WHERE id=$1",
      [id, DateTime.to_naive(until)],
      log: false
    )

    {:ok, view, _} = open(id)
    date = DawarichWeb.LocalizedDate.l("en", DateTime.to_date(until), "long")

    expected =
      DawarichWeb.Translate.t("en", "families.getting_started.trial_ends_on", %{date: date})

    assert has_element?(view, "#family-getting-started", expected)
    Repo.query!("UPDATE users SET status=1 WHERE id=$1", [id], log: false)
    render_hook(view, "map:ready", %{})
    refute has_element?(view, "#family-getting-started", expected)
  end

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

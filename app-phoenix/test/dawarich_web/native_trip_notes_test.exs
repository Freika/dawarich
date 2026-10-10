defmodule DawarichWeb.NativeTripNotesTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "native-trip-notes-#{id}@dawarich.test",
      settings: %{"timezone" => "UTC"}
    })

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      started_at: ~N[2026-06-01 12:00:00],
      ended_at: ~N[2026-06-03 12:00:00]
    })

    %{id: id}
  end

  test "native trip notes create edit cancel and delete through admitted day controls", %{id: id} do
    {:ok, view, _} = open(id)
    assert has_element?(view, "#native-trip-day-2026-06-02 [phx-click='trip:note:edit']")
    view |> element("#native-trip-day-2026-06-02 [phx-click='trip:note:edit']") |> render_click()

    view
    |> form("#native-trip-note-form", %{"note" => %{"body" => "Coffee <outside>"}})
    |> render_submit()

    assert has_element?(view, "#native-trip-day-2026-06-02", "Coffee <outside>")
    refute has_element?(view, "#native-trip-note-form")

    assert [[note_id, "Coffee <outside>"]] =
             Repo.query!(
               "SELECT id,body FROM notes WHERE attachable_type='Trip' AND attachable_id=$1",
               [id * 10],
               log: false
             ).rows

    view |> element("#native-trip-day-2026-06-02 [phx-click='trip:note:edit']") |> render_click()
    assert has_element?(view, "#native-trip-note-form textarea", "Coffee <outside>")
    view |> element("#native-trip-note-form [phx-click='trip:note:cancel']") |> render_click()
    refute has_element?(view, "#native-trip-note-form")

    assert [["Coffee <outside>"]] =
             Repo.query!("SELECT body FROM notes WHERE id=$1", [note_id], log: false).rows

    view |> element("#native-trip-day-2026-06-02 [phx-click='trip:note:edit']") |> render_click()

    view
    |> form("#native-trip-note-form", %{"note" => %{"body" => "Later coffee"}})
    |> render_submit()

    assert [["Later coffee"]] =
             Repo.query!("SELECT body FROM notes WHERE id=$1", [note_id], log: false).rows

    view
    |> element("#native-trip-day-2026-06-02 [phx-click='trip:note:delete'][data-confirm]")
    |> render_click()

    assert Repo.query!("SELECT id FROM notes WHERE id=$1", [note_id], log: false).rows == []
    refute has_element?(view, "#native-trip-day-2026-06-02", "Later coffee")

    refute has_element?(
             view,
             "[data-controller], turbo-frame, #trip-shell [name=authenticity_token]"
           )
  end

  test "native trip note validation preserves its editor and resource refusal writes nothing", %{
    id: id
  } do
    {:ok, view, _} = open(id)
    assert has_element?(view, "#native-trip-day-2026-06-01 [phx-click='trip:note:edit']")
    render_click(view, "trip:note:edit", %{"day" => "2026-06-01"})
    view |> form("#native-trip-note-form", %{"note" => %{"body" => ""}}) |> render_submit()
    assert has_element?(view, "#native-trip-note-form [role=alert]", "blank")

    assert Repo.query!("SELECT id FROM notes WHERE attachable_id=$1", [id * 10], log: false).rows ==
             []

    render_click(view, "trip:note:edit", %{"day" => "2026-06-30"})
    refute has_element?(view, "#native-trip-note-form")

    render_click(view, "trip:note:save", %{
      "note" => %{"body" => "forged", "date" => "2026-06-02"}
    })

    assert Repo.query!("SELECT id FROM notes WHERE attachable_id=$1", [id * 10], log: false).rows ==
             []

    render_click(view, "trip:note:edit", %{"day" => "2026-06-02"})
    other = id + 1_000_000_000
    RailsUser.insert!(%{id: other, email: "other-trip-notes-#{other}@dawarich.test"})
    Repo.query!("UPDATE trips SET user_id=$1 WHERE id=$2", [other, id * 10], log: false)
    render_click(view, "trip:note:save", %{"note" => %{"body" => "withdrawn"}})
    assert_push_event(view, "map:clear", %{})
    refute has_element?(view, "#trip-shell")
    assert :sys.get_state(view.pid).socket.assigns.note_editor == nil

    assert Repo.query!("SELECT id FROM notes WHERE attachable_id=$1", [id * 10], log: false).rows ==
             []
  end

  test "native trip note validation bounds a forged oversized draft without persisting it", %{
    id: id
  } do
    {:ok, view, _} = open(id)
    render_click(view, "trip:note:edit", %{"day" => "2026-06-02"})
    render_submit(view, "trip:note:save", %{"note" => %{"body" => String.duplicate("🙂", 10_001)}})
    editor = :sys.get_state(view.pid).socket.assigns.note_editor
    assert length(String.codepoints(editor.body)) == 10_000
    assert editor.errors != []

    assert Repo.query!("SELECT id FROM notes WHERE attachable_id=$1", [id * 10], log: false).rows ==
             []
  end

  defp open(id, resource \\ nil) do
    path = "/trips/#{resource || id * 10}"

    RailsUser.signed_in(id)
    |> RailsUser.connecting_as(id)
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
    |> Map.merge(%{
      request_path: path,
      path_info: ["trips", to_string(resource || id * 10)],
      query_string: ""
    })
    |> Plug.Conn.fetch_query_params()
    |> Dawarich.Test.NativeM6IntegrationRouter.call([])
    |> live()
  end
end

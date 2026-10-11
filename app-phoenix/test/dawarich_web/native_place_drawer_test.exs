defmodule DawarichWeb.NativePlaceDrawerTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    id = System.unique_integer([:positive])

    user =
      RailsUser.insert!(%{
        id: id,
        email: "drawer-#{id}@example.invalid",
        settings: %{"timezone" => "UTC"}
      })

    scope = Dawarich.Accounts.Scope.for_user(user, "en")

    {:ok, place} =
      Dawarich.Places.create(scope, %{
        "name" => "Owned <place>",
        "latitude" => "52",
        "longitude" => "13",
        "note" => "Original"
      })

    %{id: id, place: place.id}
  end

  test "native place deep link keeps source and repeat note-only saves", %{id: id, place: place} do
    {:ok, view, _} = open(id, place)
    assert has_element?(view, "#native-place-drawer h2", "Owned <place>")
    assert has_element?(view, "#native-place-drawer", "Manual")

    before =
      rows("SELECT name,latitude,longitude,source,name_locked_at FROM places WHERE id=$1", [place])

    for note <- ["<script>plain text</script>", "Second note"] do
      view |> form("#native-place-note", place: %{note: note}) |> render_submit()
      assert rows("SELECT note FROM places WHERE id=$1", [place]) == [[note]]
      assert has_element?(view, "#native-place-note textarea", note)

      assert rows(
               "SELECT name,latitude,longitude,source,name_locked_at FROM places WHERE id=$1",
               [place]
             ) == before
    end

    render_click(view, "place:detail:close")
    assert_patch(view, "/map/v2")
    refute has_element?(view, "#native-place-drawer")
  end

  test "native map place selection edits refresh and deletion clear the drawer", %{
    id: id,
    place: place
  } do
    {:ok, view, _} = open(id, nil)
    render_hook(view, "map:select", %{"kind" => "place", "id" => place})
    assert_patch(view, "/map/v2?place_id=#{place}")
    render_click(view, "place:edit", %{"id" => place})

    view
    |> form("#native-place-form", place: %{name: "Renamed", note: "Edited"})
    |> render_submit()

    assert has_element?(view, "#native-place-drawer h2", "Renamed")
    render_click(view, "place:detail:delete")
    assert_patch(view, "/map/v2")
    assert rows("SELECT count(*) FROM places WHERE id=$1", [place]) == [[0]]
    refute has_element?(view, "#native-place-drawer")
    assert_push_event(view, "map:invalidate", %{resource: "places"})
  end

  test "foreign and deleted place deep links never expose or mutate a drawer", %{
    id: id,
    place: place
  } do
    other = System.unique_integer([:positive])
    RailsUser.insert!(%{id: other, email: "drawer-other-#{other}@example.invalid"})
    {:ok, foreign, _} = open(other, place)
    refute has_element?(foreign, "#native-place-drawer")
    {:ok, owned, _} = open(id, place)
    assert has_element?(owned, "#native-place-drawer")
    Repo.query!("DELETE FROM places WHERE id=$1", [place], log: false)
    render_click(owned, "place:detail:save", %{"place" => %{"note" => "Lost"}})
    refute has_element?(owned, "#native-place-drawer")
  end

  defp open(id, place) do
    path = if place, do: "/map/v2?place_id=#{place}", else: "/map/v2"
    live(RailsUser.signed_in(id) |> RailsUser.connecting_as(id), path)
  end
end

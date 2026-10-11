defmodule DawarichWeb.NativeM6TripIndexTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "preview-route-#{id}@dawarich.test",
      api_key: "synthetic-preview-key",
      settings: %{"timezone" => "UTC"}
    })

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      name: "Owned preview",
      path: [[13, 52], [14, 53]],
      started_at: ~N[2026-06-01 12:00:00],
      ended_at: ~N[2026-06-03 12:00:00]
    })

    %{id: id}
  end

  test "canonical native trip index owns bounded previews and refuses a revoked session", %{
    id: id
  } do
    conn = RailsUser.signed_in(id) |> RailsUser.connecting_as(id) |> get("/trips")
    {:ok, view, html} = live(conn)
    assert has_element?(view, "#mobile-navigation-menu a[href='/map/v2']")
    assert has_element?(view, "#native-trip-preview-#{id * 10}[phx-hook=MapPreview]")
    assert has_element?(view, "a[href='/trips/#{id * 10}']", "Owned preview")
    refute has_element?(view, "[data-controller], [data-action], turbo-frame")
    refute String.contains?(html, "synthetic-preview-key")
    entries = :sys.get_state(view.pid).socket.assigns.entries

    assert Enum.all?(
             entries,
             &(not Map.has_key?(&1, :path_json) and not Map.has_key?(&1, :plan_json))
           )

    Repo.query!(
      "UPDATE users SET encrypted_password=$2 WHERE id=$1",
      [id, "synthetic-revoked-password"],
      log: false
    )

    render_patch(view, "/trips?page=2")
    assert_redirect(view, "/users/sign_in")
    refute Process.alive?(view.pid)
  end
end

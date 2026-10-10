defmodule DawarichWeb.TripFormNavigationTest do
  use Dawarich.IngestCase, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.FormIsolation
  alias Dawarich.Test.{RailsUser, TripsSeeds}

  @endpoint DawarichWeb.Endpoint

  test "trip editors submit a browser document instead of a Turbo fetch that can lose the notice" do
    user = RailsUser.insert!(%{id: 7593, email: "trip-navigation@example.test"})
    TripsSeeds.trip!(%{id: 759_301, user_id: user.id, name: "Synthetic trip"})

    for path <- ["/trips/new", "/trips/759301/edit"] do
      {:ok, view, _html} =
        live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

      assert_form_isolated(render(view), "#trip-form-shell form")

      assert has_element?(
               view,
               ~s(#trip-form-shell[data-turbo="true"] form[data-turbo="false"][method="post"])
             )
    end
  end
end

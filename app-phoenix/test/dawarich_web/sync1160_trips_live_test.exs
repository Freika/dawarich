defmodule DawarichWeb.Sync1160TripsLiveTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  test "native filter submission patches normalized state and pagination retains filters in every locale" do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "trip-filter-#{id}@example.invalid",
      settings: %{"timezone" => "UTC"}
    })

    for n <- 1..7,
        do:
          TripsSeeds.trip!(%{
            id: System.unique_integer([:positive]),
            user_id: id,
            name: "Beach #{n}"
          })

    for locale <- ~w(en ca de es fr pl zh) do
      conn =
        RailsUser.signed_in(id) |> RailsUser.connecting_as(id) |> get("/trips?locale=#{locale}")

      {:ok, view, html} = live(conn)
      refute html =~ "translation_missing"
      assert has_element?(view, "#native-trip-filters input[name='q']")
      refute has_element?(view, "#native-trip-filters[phx-change]")

      view
      |> form("#native-trip-filters", %{"q" => " Beach ", "sort" => "name"})
      |> render_submit()

      assert_patch(view, "/trips?q=Beach&sort=name")
      assert has_element?(view, "a[href='/trips?page=2&q=Beach&sort=name']")
      render_patch(view, "/trips?q=absent&year=2030&country=Atlantis")
      assert has_element?(view, "[data-testid=trips-no-matches]")
      assert has_element?(view, "option[value='2030'][selected]")
      assert has_element?(view, "option[value='Atlantis'][selected]")
      assert has_element?(view, "a[href='/trips']")
    end
  end
end

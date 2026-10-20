defmodule DawarichWeb.TripFormNavigationTest do
  use Dawarich.IngestCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}

  @endpoint DawarichWeb.Endpoint

  test "native trip editors validate in place and save with a visible notice" do
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Repo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)
    Dawarich.Jobs.Ownership.put!(Repo, "command:trips.calculate", :oban)
    user = RailsUser.insert!(%{id: 7593, email: "trip-navigation@example.test"})
    TripsSeeds.trip!(%{id: 759_301, user_id: user.id, name: "Synthetic trip"})

    for {path, name} <- [{"/trips/new", "Created trip"}, {"/trips/759301/edit", "Edited trip"}] do
      conn = RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id)
      {:ok, view, _html} = live(conn, path)
      assert has_element?(view, "#native-trip-form[phx-submit=save][phx-change=validate]")

      refute has_element?(
               view,
               "[data-controller], turbo-frame"
             )

      before =
        Repo.query!("SELECT id,name FROM trips WHERE user_id=$1 ORDER BY id", [user.id]).rows

      assert has_element?(view, "#native-trip-form input[name=authenticity_token][value='']")
      view |> form("#native-trip-form", trip: %{name: ""}) |> render_submit()
      assert has_element?(view, "#error_explanation[role=alert]", "Name can't be blank")

      assert Repo.query!("SELECT id,name FROM trips WHERE user_id=$1 ORDER BY id", [user.id]).rows ==
               before

      result =
        view
        |> form("#native-trip-form",
          trip: %{
            name: name,
            started_at: "2026-05-09T06:00",
            ended_at: "2026-05-12T20:00"
          }
        )
        |> render_submit()

      [[id]] =
        Repo.query!("SELECT id FROM trips WHERE user_id=$1 AND name=$2", [user.id, name]).rows

      assert_redirect(view, "/trips/#{id}")
      assert {:ok, detail, html} = follow_redirect(result, conn)
      assert has_element?(detail, "#trip-shell h1", name)
      assert html =~ "Trip was successfully"
    end
  end
end

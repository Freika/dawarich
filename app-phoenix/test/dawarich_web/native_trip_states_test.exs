defmodule DawarichWeb.NativeTripStatesTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "trip-states-#{id}@dawarich.test",
      api_key: "synthetic-state-key",
      settings: %{"timezone" => "UTC"}
    })

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      path: [[13, 52], [14, 53]],
      started_at: ~N[2026-06-01 12:00:00],
      ended_at: ~N[2026-06-03 12:00:00]
    })

    %{id: id}
  end

  test "native trip map states disable path-only studios and preserve empty future and calculation feedback",
       %{id: id} do
    {:ok, view, _} = open(id)
    assert has_element?(view, "[data-testid=map-button-poster]:not([disabled])")
    TripsSeeds.empty_path!(id * 10)
    render_patch(view, "/trips/#{id * 10}?empty=1")
    assert has_element?(view, "[data-testid=map-button-poster][disabled]")
    assert has_element?(view, "[data-testid=map-button-video][disabled]")

    assert has_element?(
             view,
             "[data-trip-map-state=empty][role=status]",
             "No locations were recorded"
           )

    refute has_element?(view, "[data-map-replay-open]")

    Repo.query!(
      "UPDATE trips SET started_at=$1, ended_at=$2,source_identifier='planned' WHERE id=$3",
      [~N[2030-06-01 12:00:00], ~N[2030-06-03 12:00:00], id * 10],
      log: false
    )

    render_patch(view, "/trips/#{id * 10}?future=1")
    assert has_element?(view, "[data-trip-map-state=future][role=status]", "has not started")

    TripsSeeds.point!(%{
      id: id * 100,
      user_id: id,
      timestamp: DateTime.to_unix(~U[2026-06-01 13:00:00Z]),
      at: [13, 52]
    })

    Repo.query!(
      "UPDATE trips SET started_at=$1, ended_at=$2,path=NULL WHERE id=$3",
      [~N[2026-06-01 12:00:00], ~N[2026-06-03 12:00:00], id * 10],
      log: false
    )

    render_patch(view, "/trips/#{id * 10}?calculating=1")

    assert has_element?(
             view,
             "[data-trip-map-state=calculating][role=status]",
             "being calculated"
           )
  end

  test "native trip navigation keeps owned chrome and consent effects and clears it on refusal",
       %{id: id} do
    {:ok, view, html} = open(id)
    assert has_element?(view, "#mobile-navigation-menu a[href$='/trips']")
    refute String.contains?(html, "synthetic-state-key")
    render_hook(view, "changelog_consent", %{"decision" => "granted"})

    assert Repo.query!("SELECT changelog_consent FROM users WHERE id=$1", [id], log: false).rows ==
             [[1]]

    Repo.query!("DELETE FROM trips WHERE id=$1", [id * 10], log: false)
    render_hook(view, "changelog_consent", %{"decision" => "declined"})

    assert Repo.query!("SELECT changelog_consent FROM users WHERE id=$1", [id], log: false).rows ==
             [[1]]

    refute has_element?(view, "#mobile-navigation-menu")
  end

  defp open(id),
    do: live(RailsUser.signed_in(id) |> RailsUser.connecting_as(id), "/trips/#{id * 10}")
end

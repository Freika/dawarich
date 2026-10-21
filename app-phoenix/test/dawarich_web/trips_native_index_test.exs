defmodule DawarichWeb.TripsNativeIndexTest do
  use Dawarich.DataCase, async: true

  import Phoenix.LiveViewTest

  alias Dawarich.Test.{TripsNativeUI, TripsSeeds}

  @path [[12.5, 51.25], [12.373468123456789, 51.34]]

  defp trips!(user_id, from, count, attrs \\ %{}) do
    for n <- 1..count do
      TripsSeeds.trip!(
        Map.merge(
          %{
            id: from + n,
            user_id: user_id,
            started_at: NaiveDateTime.add(~N[2025-06-01 08:00:00], n * 86_400),
            ended_at: NaiveDateTime.add(~N[2025-06-01 18:00:00], n * 86_400)
          },
          attrs
        )
      )
    end
  end

  defp family!(owner, viewer) do
    [[family]] =
      rows(
        "INSERT INTO families(name,creator_id,access_until,created_at,updated_at) VALUES('Synthetic family',$1,'3026-01-01',now(),now()) RETURNING id",
        [owner]
      )

    for id <- [owner, viewer],
        do:
          rows(
            "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,1,now(),now())",
            [family, id]
          )

    family
  end

  defp share!(owner, family, trip_id),
    do:
      rows(
        "INSERT INTO shared_links(name,resource_type,resource_id,user_id,settings,created_at,updated_at) VALUES('Family',0,$1,$2,$3,now(),now()) RETURNING id::text",
        [trip_id, owner, %{"audience" => "family", "family_id" => family}]
      )

  defp family(view),
    do:
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-testid='family-trip-card'] h3")
      |> Enum.map(&String.trim(LazyHTML.text(&1)))

  defp ids(view, selector),
    do:
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute("data-trip-id")

  setup do
    TripsSeeds.user!(9_901)
    TripsSeeds.user!(9_902)
    :ok
  end

  test "own and family trip pagination preserve each other's URL state" do
    family = family!(9_902, 9_901)
    trips!(9_901, 990_100, 7)

    for id <- trips!(9_902, 990_200, 7), do: share!(9_902, family, id)

    {:ok, view, _html} = TripsNativeUI.live_as(9_901, "/trips?family_page=2")
    assert length(ids(view, "#trips [data-trip-id]")) == 6
    assert family(view) == ["trip 990201"]

    html = render_patch(view, "/trips?page=2&family_page=2")
    assert ids(view, "#trips [data-trip-id]") == ["990101"]
    assert family(view) == ["trip 990201"]
    assert html =~ ~s(href="/trips?family_page=2")
    assert html =~ ~s(href="/trips?page=2")
  end

  test "a revoked family card is cleared on params or update" do
    family = family!(9_902, 9_901)
    [[share]] = share!(9_902, family, hd(trips!(9_902, 990_300, 1)))

    {:ok, view, _html} = TripsNativeUI.live_as(9_901, "/trips")
    assert has_element?(view, "a[href='/s/#{share}'] [data-testid='family-trip-card']")

    rows("DELETE FROM family_memberships WHERE user_id=$1", [9_902])
    render_patch(view, "/trips?family_page=1")
    refute has_element?(view, "[data-testid='family-trip-card']")

    rows("UPDATE users SET encrypted_password=$2 WHERE id=$1", [9_901, String.duplicate("y", 60)])
    assert {:error, {:redirect, %{to: "/users/sign_in"}}} = render_patch(view, "/trips?page=1")
  end

  test "trip list projections stay bounded across repeated navigation" do
    trips!(9_901, 990_400, 13, %{path: @path})
    {:ok, view, _html} = TripsNativeUI.live_as(9_901, "/trips")

    for path <- ~w(/trips?page=2 /trips?page=3 /trips?page=1 /trips?page=2) do
      render_patch(view, path)
      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.entries) <= 6
      assert length(ids(view, "#trips [data-trip-id]")) <= 6
    end

    assert length(ids(view, "#trips [data-trip-id]")) == 6
    state = inspect(:sys.get_state(view.pid).socket.assigns, limit: :infinity)
    refute state =~ "12.37346"
    refute state =~ "a8-k-9901"
    refute render(view) =~ "trip-maplibre-preview"
  end

  test "cards keep source dates, units, countries, previews and the empty state" do
    {:ok, empty, html} = TripsNativeUI.live_as(9_901, "/trips")
    assert html =~ "No trips yet"
    assert has_element?(empty, "#trips a[href='/trips/new']")
    refute has_element?(empty, "[role='navigation']")

    TripsSeeds.trip!(%{
      id: 990_501,
      user_id: 9_901,
      path: @path,
      distance: 12_345,
      started_at: ~N[2026-05-09 06:00:00],
      ended_at: ~N[2026-05-10 06:00:01]
    })

    TripsSeeds.trip!(%{
      id: 990_502,
      user_id: 9_901,
      distance: nil,
      started_at: ~N[2025-01-01 08:00:00],
      ended_at: ~N[2025-01-01 18:00:00]
    })

    TripsSeeds.trip!(%{
      id: 990_503,
      user_id: 9_901,
      distance: 0,
      visited_countries: [],
      started_at: ~N[2024-01-01 08:00:00],
      ended_at: ~N[2024-01-01 18:00:00]
    })

    {:ok, view, _html} = TripsNativeUI.live_as(9_901, "/trips")
    card = view |> element("#trip-990501") |> render()
    assert card =~ "12 km"
    assert card =~ "1 country"
    assert card =~ "2 days"
    assert card =~ ~r/9 May 2026\s+–\s+10 May 2026/
    assert has_element?(view, "a[href='/trips/990501'] #trip-990501 [data-trip-preview='path']")
    assert view |> element("#trip-990502") |> render() =~ "Calculating..."
    assert view |> element("#trip-990503") |> render() =~ "No points found"
  end

  test "unsupported trip settings show the generic alert without trips" do
    rows("UPDATE users SET settings=$2 WHERE id=$1", [
      9_901,
      %{"maps" => %{"distance_unit" => "parsecs"}}
    ])

    TripsSeeds.trip!(%{id: 990_601, user_id: 9_901})
    {:ok, view, _html} = TripsNativeUI.live_as(9_901, "/trips")
    assert has_element?(view, "[role='alert']")
    refute has_element?(view, "#trip-990601")
  end

  test "a visitor is sent to sign in" do
    assert {:error, {:redirect, %{to: "/users/sign_in"}}} = TripsNativeUI.live_as(nil, "/trips")
  end
end

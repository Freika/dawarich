defmodule DawarichWeb.NativeMapVisitPlacesTest do
  use Dawarich.DataCase, async: true
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Maps}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.MapLive.EntityCommands
  @endpoint DawarichWeb.Endpoint

  defmodule Host do
    use Phoenix.LiveView

    def mount(_params, session, socket) do
      {:ok,
       assign(socket,
         current_scope: Maps.principal(Accounts.get(session["user_id"]), "en"),
         visit_places_loader: session["loader"] && Agent.get(session["loader"], & &1)
       )}
    end

    def handle_event(event, params, socket),
      do: EntityCommands.handle_event(event, params, socket)

    def handle_async(name, result, socket), do: EntityCommands.handle_async(name, result, socket)

    def render(assigns) do
      ~H"""
      <DawarichWeb.NativeMapVisit.dialog dialog={assigns[:visit_dialog]} locale="en" />
      """
    end
  end

  setup do
    [id, other] =
      for _ <- 1..2 do
        id = System.unique_integer([:positive])

        RailsUser.insert!(%{
          id: id,
          email: "visit-places-#{id}@dawarich.test",
          settings: %{"timezone" => "UTC"}
        })

        id
      end

    %{id: id, other: other}
  end

  test "visit place search keeps the newest result and picks a saved place, area or external match",
       c do
    home = place!(c.id, "Home", 13.4, 52.5)
    cafe = place!(c.id, "Cafe", 13.4005, 52.5005)
    area = area!(c.id, "Office")
    visit = visit!(c.id, home)
    test_pid = self()

    loader = fn _scope, _visit, query ->
      send(test_pid, {:searching, query, hd(Process.get(:"$callers"))})
      if query == "old", do: receive(do: (:release -> :ok))

      {:ok,
       %{
         "places" => [
           %{"id" => cafe, "name" => "Cafe", "latitude" => 52.5005, "longitude" => 13.4005},
           %{
             "id" => nil,
             "name" => "Bakery #{query}",
             "latitude" => 52.501,
             "longitude" => 13.401,
             "osm_id" => "77"
           }
         ],
         "areas" => [%{"id" => area, "name" => "Office"}]
       }}
    end

    view = open(c, loader)
    render_hook(view, "visit:edit", %{"id" => to_string(visit)})
    render_hook(view, "visit:place_search", %{"q" => "old"})
    assert_receive {:searching, "old", slow}
    render_hook(view, "visit:place_search", %{"q" => "new"})
    assert_receive {:searching, "new", _fast}
    assert render_async(view, 5_000) =~ "Bakery new"
    refute Process.alive?(slow)
    refute render(view) =~ "Bakery old"

    view |> element("#native-visit-place-results [data-pick='place-0']") |> render_click()
    assert attached(visit) == [cafe, nil, 1]

    render_hook(view, "visit:edit", %{"id" => to_string(visit)})
    render_hook(view, "visit:place_search", %{"q" => "new"})
    assert_receive {:searching, "new", _}
    render_async(view, 5_000)
    view |> element("#native-visit-place-results [data-pick='area-0']") |> render_click()
    assert attached(visit) == [cafe, area, 1]

    render_hook(view, "visit:edit", %{"id" => to_string(visit)})
    render_hook(view, "visit:place_search", %{"q" => "new"})
    assert_receive {:searching, "new", _}
    render_async(view, 5_000)
    view |> element("#native-visit-place-results [data-pick='place-1']") |> render_click()

    [[place, name]] =
      rows(
        "SELECT v.place_id, p.name FROM visits v JOIN places p ON p.id=v.place_id WHERE v.id=$1",
        [visit]
      )

    assert name == "Bakery new"
    refute place in [home, cafe]
    refute has_element?(view, "#native-visit-dialog")
  end

  test "visit place pick refuses a foreign area or stale index without changing the visit", c do
    home = place!(c.id, "Home", 13.4, 52.5)
    foreign = area!(c.other, "Secret")
    visit = visit!(c.id, home)

    loader = fn _scope, _visit, _query ->
      {:ok, %{"places" => [], "areas" => [%{"id" => foreign, "name" => "Secret"}]}}
    end

    view = open(c, loader)
    render_hook(view, "visit:place_pick", %{"kind" => "area", "index" => "0"})
    render_hook(view, "visit:edit", %{"id" => to_string(visit)})
    render_hook(view, "visit:place_pick", %{"kind" => "place", "index" => "0"})
    render_hook(view, "visit:place_search", %{"q" => "se"})
    render_async(view, 5_000)
    render_hook(view, "visit:place_pick", %{"kind" => "area", "index" => "5"})
    refute has_element?(view, "#native-visit-dialog [role=alert]")
    view |> element("#native-visit-place-results [data-pick='area-0']") |> render_click()
    assert has_element?(view, "#native-visit-dialog [role=alert]")
    assert attached(visit) == [home, nil, 1]
  end

  defp open(c, loader) do
    {:ok, agent} = Agent.start_link(fn -> loader end)

    {:ok, view, _} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host,
        session: %{"user_id" => c.id, "loader" => agent}
      )

    view
  end

  defp attached(visit),
    do: hd(rows("SELECT place_id, area_id, status FROM visits WHERE id=$1", [visit]))

  defp place!(user, name, lon, lat),
    do:
      hd(
        hd(
          rows(
            "INSERT INTO places(user_id,name,latitude,longitude,lonlat,source,created_at,updated_at) VALUES($1,$2,$4::numeric,$3::numeric,ST_SetSRID(ST_MakePoint($3::float8,$4::float8),4326)::geography,0,now(),now()) RETURNING id",
            [user, name, lon, lat]
          )
        )
      )

  defp area!(user, name),
    do:
      hd(
        hd(
          rows(
            "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,$2,52.5,13.4,100,now(),now()) RETURNING id",
            [user, name]
          )
        )
      )

  defp visit!(user, place),
    do:
      hd(
        hd(
          rows(
            "INSERT INTO visits(user_id,place_id,name,started_at,ended_at,duration,status,demo,created_at,updated_at) VALUES($1,$2,'Stay','2024-01-01 08:00:00','2024-01-01 09:00:00',60,1,false,now(),now()) RETURNING id",
            [user, place]
          )
        )
      )
end

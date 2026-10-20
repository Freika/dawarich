defmodule DawarichWeb.NativeMapEntitiesTest do
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
         nearby_loader: session["nearby"] && Agent.get(session["nearby"], & &1)
       )}
    end

    def handle_event(event, params, socket),
      do: EntityCommands.handle_event(event, params, socket)

    def handle_async(name, result, socket), do: EntityCommands.handle_async(name, result, socket)

    def render(assigns) do
      ~H"""
      <DawarichWeb.NativeMapPlace.dialog dialog={assigns[:place_dialog]} locale="en" />
      """
    end
  end

  setup do
    [id, other] =
      for _ <- 1..2 do
        id = System.unique_integer([:positive])

        RailsUser.insert!(%{
          id: id,
          email: "entity-#{id}@dawarich.test",
          settings: %{"timezone" => "UTC"}
        })

        id
      end

    %{id: id, other: other}
  end

  test "foreign place or visit modal refuses without changing data", c do
    place = place!(c.other)
    visit = visit!(c.other, place)
    before = snapshot(c.other)
    view = open(c)

    render_hook(view, "place:edit", %{"id" => to_string(place)})
    refute has_element?(view, "#native-place-dialog")
    render_hook(view, "place:delete", %{"id" => to_string(place)})
    assert_reply(view, %{error: "not_found"})
    render_hook(view, "visit:status", %{"id" => to_string(visit), "status" => "confirmed"})
    assert_reply(view, %{error: _})
    render_hook(view, "visit:delete", %{"id" => to_string(visit)})
    assert_reply(view, %{error: _})
    assert snapshot(c.other) == before
  end

  test "successful create closes dialog and refreshes enabled layer", c do
    view = open(c)
    render_hook(view, "place:new", %{"latitude" => 52.52, "longitude" => 13.405})
    assert has_element?(view, "#native-place-dialog")

    view
    |> form("#native-place-form", place: %{name: ""})
    |> render_submit()

    assert has_element?(view, "#native-place-dialog [role=alert]")

    view |> form("#native-place-form", place: %{name: "Bakery"}) |> render_submit()
    refute has_element?(view, "#native-place-dialog")
    assert_push_event(view, "map:layer", %{layer: "places", enabled: true})
    assert_push_event(view, "map:invalidate", %{resource: "places", id: id})
    assert rows("SELECT name, user_id FROM places WHERE id=$1", [id]) == [["Bakery", c.id]]
  end

  test "place dialog saves note and owned tags only", c do
    [own, foreign] =
      for {user, name} <- [{c.id, "Food"}, {c.other, "Secret"}] do
        hd(
          hd(
            rows(
              "INSERT INTO tags(user_id,name,icon,color,created_at,updated_at) VALUES($1,$2,'🍕','#ff0000',now(),now()) RETURNING id",
              [user, name]
            )
          )
        )
      end

    view = open(c)
    render_hook(view, "place:new", %{"latitude" => 52.52, "longitude" => 13.405})
    assert has_element?(view, "#native-place-form input[name='place[tag_ids][]'][value='#{own}']")
    refute has_element?(view, "#native-place-form input[value='#{foreign}']")

    render_hook(view, "place:save", %{
      "place" => %{
        "name" => "Pizzeria",
        "note" => "Thin crust",
        "tag_ids" => [to_string(own), to_string(foreign)]
      }
    })

    refute has_element?(view, "#native-place-dialog")

    assert rows(
             "SELECT p.note, p.name_locked_at IS NOT NULL, array_agg(g.tag_id) FROM places p JOIN taggings g ON g.taggable_id=p.id AND g.taggable_type='Place' WHERE p.user_id=$1 GROUP BY p.note, p.name_locked_at",
             [c.id]
           ) == [["Thin crust", true, [own]]]
  end

  test "nearby search changed during reply keeps newest result", c do
    test_pid = self()

    nearby = fn _scope, %{"latitude" => lat} ->
      send(test_pid, {:nearby, lat, hd(Process.get(:"$callers"))})
      if lat == "1.0", do: receive(do: (:release -> :ok))
      {:ok, [%{"name" => "Spot #{lat}"}]}
    end

    agent = start_supervised!({Agent, fn -> nearby end})
    view = open(c, agent)
    render_hook(view, "place:new", %{"latitude" => 52.52, "longitude" => 13.405})
    render_hook(view, "place:nearby", %{"latitude" => "1.0", "longitude" => "1.0"})
    assert_receive {:nearby, "1.0", slow}
    render_hook(view, "place:nearby", %{"latitude" => "2.0", "longitude" => "2.0"})
    assert_receive {:nearby, "2.0", fast}
    finished(fast)
    assert render(view) =~ "Spot 2.0"
    finished(slow)
    html = render(view)
    assert html =~ "Spot 2.0"
    refute html =~ "Spot 1.0"
  end

  test "late nearby completion preserves the current place draft before submit", c do
    test_pid = self()

    nearby = fn _scope, _params ->
      send(test_pid, {:draft_nearby, self()})

      receive do
        :release -> {:ok, [%{"name" => "Nearby result"}]}
      end
    end

    agent = start_supervised!({Agent, fn -> nearby end})
    view = open(c, agent)
    render_hook(view, "place:new", %{"latitude" => 52.52, "longitude" => 13.405})
    render_hook(view, "place:nearby", %{"latitude" => "52.52", "longitude" => "13.405"})
    assert_receive {:draft_nearby, pending}

    view
    |> form("#native-place-form", place: %{name: "Typed name", note: "Typed note"})
    |> render_change()

    send(pending, :release)
    render_async(view)
    assert has_element?(view, "#native-place-form input[name='place[name]'][value='Typed name']")
    assert has_element?(view, "#native-place-form textarea", "Typed note")
    assert has_element?(view, "#native-place-form", "Nearby result")
    view |> form("#native-place-form") |> render_submit()

    assert rows("SELECT name,note FROM places WHERE user_id=$1", [c.id]) == [
             ["Typed name", "Typed note"]
           ]
  end

  test "picking a nearby suggestion fills the place like the Rails modal and load more widens the radius",
       c do
    test_pid = self()

    nearby = fn _scope, params ->
      send(test_pid, {:radius, params["radius"]})

      {:ok,
       [%{"name" => "Cafe Rot", "latitude" => 52.53, "longitude" => 13.41, "street" => "Main 1"}]}
    end

    agent = start_supervised!({Agent, fn -> nearby end})
    view = open(c, agent)
    render_hook(view, "place:new", %{"latitude" => 52.52, "longitude" => 13.405})
    assert has_element?(view, "#native-place-form", "Open modal to load nearby suggestions")
    render_hook(view, "place:nearby", %{"latitude" => "52.52", "longitude" => "13.405"})
    assert_receive {:radius, nil}
    render_async(view)

    view |> element("#native-place-form .card[phx-value-index='0']") |> render_click()
    assert has_element?(view, "#native-place-form input[name='place[name]'][value='Cafe Rot']")
    assert has_element?(view, "#native-place-form input[name='place[latitude]'][value='52.53']")

    view |> element("#native-place-form a[phx-click='place:nearby']") |> render_click()
    assert_receive {:radius, 1.0}
  end

  test "unchecking every tag clears the place tags", c do
    [[tag]] =
      rows(
        "INSERT INTO tags(user_id,name,created_at,updated_at) VALUES($1,'Food',now(),now()) RETURNING id",
        [c.id]
      )

    view = open(c, nil)
    render_hook(view, "place:new", %{"latitude" => 52.52, "longitude" => 13.405})

    view
    |> form("#native-place-form", place: %{name: "Tagged", tag_ids: [to_string(tag)]})
    |> render_change()

    assert has_element?(view, "input[name='place[tag_ids][]'][value='#{tag}'][checked]")
    render_hook(view, "place:change", %{"place" => %{"name" => "Tagged"}})
    refute has_element?(view, "input[name='place[tag_ids][]'][value='#{tag}'][checked]")
  end

  test "malformed place draft fields leave the owned form usable", c do
    view = open(c)
    render_hook(view, "place:new", %{"latitude" => 52.52, "longitude" => 13.405})

    view
    |> form("#native-place-form", place: %{name: "Kept draft", note: "Kept note"})
    |> render_change()

    render_hook(view, "place:change", %{
      "place" => %{
        "name" => %{"nested" => "invalid"},
        "note" => ["invalid"],
        "tag_ids" => %{"invalid" => "shape"}
      }
    })

    assert has_element?(view, "#native-place-form input[name='place[name]'][value='Kept draft']")
    assert has_element?(view, "#native-place-form textarea", "Kept note")
    view |> form("#native-place-form") |> render_submit()

    assert rows("SELECT name,note FROM places WHERE user_id=$1", [c.id]) == [
             ["Kept draft", "Kept note"]
           ]
  end

  defp finished(pid) do
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2_000
  end

  defp open(c, nearby \\ nil) do
    {:ok, view, _} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host,
        session: %{"user_id" => c.id, "nearby" => nearby}
      )

    view
  end

  defp snapshot(user) do
    for table <- ~w(places visits),
        do:
          rows("SELECT row_to_json(t)::text FROM #{table} t WHERE user_id=$1 ORDER BY id", [user])
  end

  defp place!(user),
    do:
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,lonlat,source,created_at,updated_at) VALUES($1,'Foreign',52.5,13.4,ST_SetSRID(ST_MakePoint(13.4,52.5),4326)::geography,0,now(),now()) RETURNING id",
        [user]
      )
      |> hd()
      |> hd()

  defp visit!(user, place),
    do:
      rows(
        "INSERT INTO visits(user_id,place_id,name,started_at,ended_at,duration,status,demo,created_at,updated_at) VALUES($1,$2,'V','2024-01-01','2024-01-01 01:00:00',3600,0,false,now(),now()) RETURNING id",
        [user, place]
      )
      |> hd()
      |> hd()
end

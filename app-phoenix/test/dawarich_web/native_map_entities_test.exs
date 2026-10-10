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

  test "nearby search changed during reply keeps newest result", c do
    test_pid = self()

    nearby = fn _scope, %{"latitude" => lat} ->
      send(test_pid, {:nearby, lat, self()})
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
    send(slow, :release)
    finished(slow)
    html = render(view)
    assert html =~ "Spot 2.0"
    refute html =~ "Spot 1.0"
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

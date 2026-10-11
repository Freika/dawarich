defmodule DawarichWeb.NativeMapVisitsTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Maps}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.MapLive.EntityCommands
  @endpoint DawarichWeb.Endpoint

  defmodule Host do
    use Phoenix.LiveView

    def mount(_params, session, socket) do
      {:ok, assign(socket, current_scope: Maps.principal(Accounts.get(session["user_id"]), "en"))}
    end

    def handle_event(event, params, socket),
      do: EntityCommands.handle_event(event, params, socket)

    def render(assigns) do
      ~H"""
      <DawarichWeb.NativeMapVisit.dialog dialog={assigns[:visit_dialog]} locale="en" />
      <DawarichWeb.NativePointAddress.drawer address={assigns[:point_address]} locale="en" />
      """
    end
  end

  setup do
    [id, other] =
      for _ <- 1..2 do
        id = System.unique_integer([:positive])

        RailsUser.insert!(%{
          id: id,
          email: "visit-#{id}@dawarich.test",
          settings: %{"timezone" => "Europe/Berlin"}
        })

        id
      end

    %{id: id, other: other}
  end

  test "map Visit commands use M5 bigint admission without effects", c do
    scope = Maps.principal(Accounts.get(c.id), "en")
    before = rows("SELECT count(*) FROM visits WHERE user_id=$1", [c.id])

    assert {:error, :invalid_input} =
             Dawarich.Maps.VisitEditing.update(scope, String.duplicate("9", 128), %{
               "name" => "Refused"
             })

    assert rows("SELECT count(*) FROM visits WHERE user_id=$1", [c.id]) == before
  end

  test "native Visit creation enables the saved layer only after successful creation", c do
    rows("UPDATE users SET settings=$2::jsonb WHERE id=$1", [
      c.id,
      %{"timezone" => "Europe/Berlin", "enabled_map_layers" => ["Points"]}
    ])

    {:ok, view, _} =
      RailsUser.signed_in(c.id)
      |> RailsUser.connecting_as(c.id)
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
      |> Map.merge(%{request_path: "/map/v2", path_info: ["map", "v2"], query_string: ""})
      |> Plug.Conn.fetch_query_params()
      |> Dawarich.Test.NativeM6IntegrationRouter.call([])
      |> live()

    render_hook(view, "visit:new", %{"latitude" => 52.5, "longitude" => 13.4})

    view
    |> form("#native-visit-form",
      visit: %{name: "Cafe", started_at: "2024-06-15T13:00", ended_at: "2024-06-15T12:00"}
    )
    |> render_submit()

    assert Accounts.get(c.id).settings["enabled_map_layers"] == ["Points"]

    view
    |> form("#native-visit-form",
      visit: %{name: "Cafe", started_at: "2024-06-15T12:00", ended_at: "2024-06-15T13:00"}
    )
    |> render_submit()

    assert Accounts.get(c.id).settings["enabled_map_layers"] == ["Points", "Visits"]
    assert Accounts.get(c.id).settings["timezone"] == "Europe/Berlin"
    assert_push_event(view, "map:config", %{"visitsEnabled" => true})
    [[visit]] = rows("SELECT id FROM visits WHERE user_id=$1", [c.id])
    render_hook(view, "settings:map_layers", %{"layers" => ["Points"]})
    render_hook(view, "visit:edit", %{"id" => to_string(visit)})

    view
    |> form("#native-visit-form",
      visit: %{name: "Office", started_at: "2024-06-15T12:00", ended_at: "2024-06-15T14:00"}
    )
    |> render_submit()

    assert Accounts.get(c.id).settings["enabled_map_layers"] == ["Points"]
    assert name_and_place(visit) |> hd() == "Office"
  end

  test "visit dialog creates in the profile zone and enables the visits layer", c do
    view = open(c)
    render_hook(view, "visit:new", %{"latitude" => 52.52, "longitude" => 13.405})
    assert has_element?(view, "#native-visit-dialog")

    view
    |> form("#native-visit-form",
      visit: %{name: "Cafe", started_at: "2024-03-31T03:30", ended_at: "2024-03-31T04:30"}
    )
    |> render_submit()

    refute has_element?(view, "#native-visit-dialog")
    assert_push_event(view, "map:layer", %{layer: "visits", enabled: true})
    assert_push_event(view, "map:invalidate", %{resource: "visits"})

    assert rows(
             "SELECT name, started_at::text, ended_at::text, status FROM visits WHERE user_id=$1",
             [c.id]
           ) == [["Cafe", "2024-03-31 01:30:00", "2024-03-31 02:30:00", 1]]
  end

  test "search result opens a visit dialog prefilled in the profile zone", c do
    view = open(c)

    render_hook(view, "visit:new", %{
      "latitude" => 52.51,
      "longitude" => 13.41,
      "name" => "Cafe <b>",
      "started_at" => "2024-03-31T00:30:00Z",
      "ended_at" => "not a time"
    })

    assert has_element?(view, "#native-visit-form input[name='visit[name]'][value='Cafe <b>']")

    assert has_element?(
             view,
             "#native-visit-form input[name='visit[started_at]'][value='2024-03-31T01:30']"
           )

    assert has_element?(
             view,
             "#native-visit-form input[name='visit[ended_at]'][value='2024-03-31T03:30']"
           )
  end

  test "visit edit renames and attaches only owned or candidate places", c do
    home = place!(c.id, "Home")
    office = place!(c.id, "Office")
    foreign = place!(c.other, "Foreign")
    visit = visit!(c.id, home, "Stay")
    view = open(c)

    render_hook(view, "visit:edit", %{"id" => to_string(visit)})
    assert has_element?(view, "#native-visit-form input[name='visit[started_at]']")
    view |> form("#native-visit-form", visit: %{name: "Renamed"}) |> render_submit()
    assert name_and_place(visit) == ["Renamed", home]

    render_hook(view, "visit:edit", %{"id" => to_string(visit)})
    render_hook(view, "visit:place", %{"place_id" => to_string(foreign)})
    assert has_element?(view, "#native-visit-dialog [role=alert]")
    assert name_and_place(visit) == ["Renamed", home]

    render_hook(view, "visit:place", %{"place_id" => to_string(office)})
    refute has_element?(view, "#native-visit-dialog")
    assert name_and_place(visit) == ["Office", office]
  end

  test "visit merge combines owned visits and refuses foreign or noted sets", c do
    place = place!(c.id, "Home")
    first = visit!(c.id, place, "A", "2024-01-01 08:00:00", "2024-01-01 09:00:00")
    second = visit!(c.id, place, "B", "2024-01-01 10:00:00", "2024-01-01 11:00:00")
    foreign = visit!(c.other, place!(c.other, "F"), "F")
    view = open(c)

    render_hook(view, "visits:merge", %{"ids" => [to_string(first), to_string(foreign)]})
    assert_reply(view, %{error: _})
    assert count(c.id) == 2

    noted = visit!(c.id, place, "N", "2024-01-01 12:00:00", "2024-01-01 13:00:00")
    note!(c.id, noted)
    render_hook(view, "visits:merge", %{"ids" => [to_string(second), to_string(noted)]})
    assert_reply(view, %{error: "invalid_input"})
    assert count(c.id) == 3

    render_hook(view, "visits:merge", %{"ids" => [to_string(first), to_string(second)]})
    assert_reply(view, %{ok: true})
    assert_push_event(view, "map:invalidate", %{resource: "visits"})

    assert rows("SELECT id, ended_at::text FROM visits WHERE user_id=$1 AND id<>$2", [
             c.id,
             noted
           ]) == [[first, "2024-01-01 11:00:00"]]

    Dawarich.Jobs.Ownership.put!(Dawarich.Repo, "command:visits.suggest", :oban)
    render_hook(view, "visits:merge", %{"ids" => [to_string(first), to_string(noted)]})
    assert_reply(view, %{ok: true})
    assert count(c.id) == 1
    assert rows("SELECT count(*) FROM notes WHERE attachable_id=$1", [noted]) == [[0]]
  end

  test "visit notes are listed and added only for the open owned visit", c do
    visit = visit!(c.id, place!(c.id, "Home"), "Stay")
    foreign = visit!(c.other, place!(c.other, "F"), "F")
    view = open(c)

    render_hook(view, "note:add", %{"note" => %{"body" => "orphan"}})
    assert rows("SELECT count(*) FROM notes", []) == [[0]]

    render_hook(view, "visit:edit", %{"id" => to_string(visit)})

    view
    |> form("#native-visit-note-form", note: %{body: "Lunch <b>here</b>"})
    |> render_submit(%{"visit_id" => to_string(foreign)})

    assert render(view) =~ "Lunch &lt;b&gt;here&lt;/b&gt;"

    assert rows("SELECT attachable_type, attachable_id, body FROM notes", []) == [
             ["Visit", visit, "Lunch <b>here</b>"]
           ]

    render_hook(view, "note:add", %{"note" => %{"body" => " "}})
    assert has_element?(view, "#native-visit-note-form [role=alert]")

    stale = visit!(c.id, place!(c.id, "Gone"), "Gone")
    render_hook(view, "visit:edit", %{"id" => to_string(stale)})
    rows("UPDATE visits SET deleted_at=now() WHERE id=$1", [stale])
    render_hook(view, "note:add", %{"note" => %{"body" => "after delete"}})
    assert rows("SELECT count(*) FROM notes", []) == [[1]]
  end

  test "point address drawer shows only an owned point address", c do
    own = point!(c.id, %{"street" => "Main St", "city" => "Berlin", "country" => "Germany"})

    foreign =
      point!(c.other, %{"street" => "Secret Rd", "city" => "Paris", "country" => "France"})

    view = open(c)

    render_hook(view, "address:open", %{"id" => to_string(foreign)})
    refute has_element?(view, "#native-point-address")
    render_hook(view, "address:open", %{"id" => to_string(own)})
    assert has_element?(view, "#native-point-address", "Main St, Berlin, Germany")
    assert :sys.get_state(view.pid).socket.assigns.point_address |> Map.keys() == [:id, :text]
    render_hook(view, "address:close", %{})
    refute has_element?(view, "#native-point-address")
  end

  defp open(c) do
    {:ok, view, _} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host, session: %{"user_id" => c.id})

    view
  end

  defp name_and_place(visit),
    do: hd(rows("SELECT name, place_id FROM visits WHERE id=$1", [visit]))

  defp count(user), do: hd(hd(rows("SELECT count(*) FROM visits WHERE user_id=$1", [user])))

  defp place!(user, name),
    do:
      hd(
        hd(
          rows(
            "INSERT INTO places(user_id,name,latitude,longitude,lonlat,source,created_at,updated_at) VALUES($1,$2,52.5,13.4,ST_SetSRID(ST_MakePoint(13.4,52.5),4326)::geography,0,now(),now()) RETURNING id",
            [user, name]
          )
        )
      )

  defp visit!(
         user,
         place,
         name,
         from \\ "2024-01-01 08:00:00",
         to \\ "2024-01-01 09:00:00"
       ),
       do:
         hd(
           hd(
             rows(
               "INSERT INTO visits(user_id,place_id,name,started_at,ended_at,duration,status,demo,created_at,updated_at) VALUES($1,$2,$3,$4::text::timestamp,$5::text::timestamp,60,1,false,now(),now()) RETURNING id",
               [user, place, name, from, to]
             )
           )
         )

  defp note!(user, visit),
    do:
      rows(
        "INSERT INTO notes(user_id,body,attachable_type,attachable_id,noted_at,created_at,updated_at) VALUES($1,'kept','Visit',$2,now(),now(),now())",
        [user, visit]
      )

  defp point!(user, props),
    do:
      hd(
        hd(
          rows(
            "INSERT INTO points(user_id,timestamp,lonlat,geodata,created_at,updated_at) VALUES($1,$2,ST_SetSRID(ST_MakePoint(13.4,52.5),4326)::geography,$3,now(),now()) RETURNING id",
            [user, System.unique_integer([:positive]), %{"properties" => props}]
          )
        )
      )
end

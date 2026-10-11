defmodule DawarichWeb.NativeAreaDialogTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Areas, Maps}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    Ownership.put!(Repo, "command:areas.relabel_visits", :oban)
    [actor, other] = for _ <- 1..2, do: account!()
    %{actor: actor, other: other, scope: Maps.principal(actor, "en")}
  end

  test "native Area creation enables its layer only after successful save and retains other preferences",
       c do
    rows("UPDATE users SET settings=$2::jsonb WHERE id=$1", [
      c.actor.id,
      %{"timezone" => "UTC", "enabled_map_layers" => ["Points"]}
    ])

    view = open(c.actor, Dawarich.Test.NativeM6IntegrationRouter)
    render_hook(view, "area:new", %{"latitude" => 52.5, "longitude" => 13.4})
    view |> form("#native-area-form", area: %{name: "Home", radius: "-5"}) |> render_submit()
    assert Accounts.get(c.actor.id).settings["enabled_map_layers"] == ["Points"]
    view |> form("#native-area-form", area: %{name: "Home", radius: "100"}) |> render_submit()
    assert Accounts.get(c.actor.id).settings["enabled_map_layers"] == ["Points", "Areas"]
    assert Accounts.get(c.actor.id).settings["timezone"] == "UTC"
    [[id]] = rows("SELECT id FROM areas WHERE user_id=$1", [c.actor.id])
    assert_push_event(view, "map:config", %{"areasEnabled" => true})
    render_hook(view, "settings:map_layers", %{"layers" => ["Points"]})
    render_hook(view, "area:edit", %{"id" => to_string(id)})
    view |> form("#native-area-form", area: %{name: "Office", radius: "250"}) |> render_submit()
    assert Accounts.get(c.actor.id).settings["enabled_map_layers"] == ["Points"]
    render_hook(view, "area:delete", %{"id" => to_string(id)})
    assert Accounts.get(c.actor.id).settings["enabled_map_layers"] == ["Points"]
    assert rows("SELECT count(*) FROM areas WHERE user_id=$1", [c.actor.id]) == [[0]]
  end

  test "Area invalid radius keeps dialog and no row", c do
    view = open(c.actor)
    render_hook(view, "area:new", %{"latitude" => 52.52, "longitude" => 13.405})
    assert has_element?(view, "#native-area-dialog input[name='area[latitude]'][value='52.52']")

    html =
      view
      |> form("#native-area-form", area: %{name: "Home", radius: "-5"})
      |> render_submit()

    assert html =~ "Radius must be greater than 0"
    assert has_element?(view, "#native-area-dialog input[name='area[radius]'][value='-5']")
    assert rows("SELECT count(*) FROM areas WHERE user_id=$1", [c.actor.id]) == [[0]]
    refute_push_event(view, "map:invalidate", %{})

    render_hook(view, "area:close", %{})
    refute has_element?(view, "#native-area-dialog")
  end

  test "Area edit persists name radius and coordinates", c do
    {:ok, %{"id" => id}} =
      Areas.create_area(c.scope, %{
        "name" => "Home",
        "latitude" => "52.5",
        "longitude" => "13.4",
        "radius" => "100"
      })

    view = open(c.actor)
    render_hook(view, "area:edit", %{"id" => to_string(id)})
    assert has_element?(view, "#native-area-dialog input[name='area[name]'][value='Home']")

    view
    |> form("#native-area-form", area: %{name: "Office", radius: "250"})
    |> render_submit(%{"area" => %{"latitude" => "52.51", "longitude" => "13.41"}})

    refute has_element?(view, "#native-area-dialog")
    assert_push_event(view, "map:invalidate", %{resource: "areas", id: ^id})

    assert rows("SELECT name, radius, latitude::text, longitude::text FROM areas WHERE id=$1", [
             id
           ]) ==
             [["Office", 250, "52.510000", "13.410000"]]
  end

  test "delete refusal keeps area visible", c do
    {:ok, %{"id" => id}} =
      Areas.create_area(c.scope, %{
        "name" => "Shared",
        "latitude" => "52.5",
        "longitude" => "13.4",
        "radius" => "100"
      })

    [[place]] =
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,source,created_at,updated_at) VALUES($1,'Foreign',52.5,13.4,1,now(),now()) RETURNING id",
        [c.other.id]
      )

    rows(
      "INSERT INTO visits(user_id,area_id,place_id,name,started_at,ended_at,duration,status,demo,created_at,updated_at) VALUES($1,$2,$3,'V','2024-01-01','2024-01-01 01:00:00',3600,1,false,now(),now())",
      [c.actor.id, id, place]
    )

    view = open(c.actor)
    render_hook(view, "area:edit", %{"id" => to_string(id)})
    assert view |> element("#native-area-delete") |> render() =~ "Delete"
    html = view |> element("#native-area-delete") |> render_click()

    assert html =~ "Failed to delete area"
    assert has_element?(view, "#native-area-dialog")
    assert rows("SELECT count(*) FROM areas WHERE id=$1", [id]) == [[1]]
    refute_push_event(view, "map:invalidate", %{})

    [[foreign]] =
      rows(
        "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'X',1,1,10,now(),now()) RETURNING id",
        [c.other.id]
      )

    render_hook(view, "area:close", %{})
    render_hook(view, "area:edit", %{"id" => to_string(foreign)})
    refute has_element?(view, "#native-area-dialog")
    render_hook(view, "area:delete", %{"id" => to_string(foreign)})
    assert rows("SELECT count(*) FROM areas WHERE id=$1", [foreign]) == [[1]]
  end

  defp open(user, router \\ Dawarich.Test.NativeMapShellRouter) do
    {:ok, view, _} =
      RailsUser.signed_in(user.id)
      |> RailsUser.connecting_as(user.id)
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
      |> Map.merge(%{request_path: "/map/v2", path_info: ["map", "v2"], query_string: ""})
      |> Plug.Conn.fetch_query_params()
      |> router.call([])
      |> live()

    view
  end

  defp account! do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "area-dialog-#{id}@dawarich.test",
      settings: %{"timezone" => "UTC"}
    })

    Accounts.get(id)
  end
end

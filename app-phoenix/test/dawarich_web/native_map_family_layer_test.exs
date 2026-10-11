defmodule DawarichWeb.NativeMapFamilyLayerTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  test "main native map keeps Family Members layer settings without projecting locations or credentials" do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "family-layer-#{id}@dawarich.test",
      api_key: "synthetic-family-layer-key",
      settings: %{"timezone" => "UTC"}
    })

    conn = RailsUser.signed_in(id) |> RailsUser.connecting_as(id) |> get("/map/v2?panel=layers")
    {:ok, view, html} = live(conn)
    assert has_element?(view, "#native-map-layers input[value='Family Members']")

    view
    |> form("#native-map-layers", %{"layers" => ["Points", "Family Members"]})
    |> render_change()

    assert "Family Members" in Dawarich.Accounts.get(id).settings["enabled_map_layers"]

    config =
      render(view)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#native-map")
      |> LazyHTML.attribute("data-map-config")
      |> hd()
      |> Jason.decode!()

    assert config["familyEnabled"] == true
    refute Map.has_key?(config, "locations")
    refute Map.has_key?(config, "api_key")
    refute html =~ "synthetic-family-layer-key"
    assert has_element?(view, "#native-family-members[phx-update=ignore]")
    view |> form("#native-map-layers", %{"layers" => ["Points"]}) |> render_change()
    refute "Family Members" in Dawarich.Accounts.get(id).settings["enabled_map_layers"]
    render_async(view, 5000)
  end
end

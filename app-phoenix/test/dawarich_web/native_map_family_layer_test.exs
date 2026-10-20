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

    [[family]] =
      Repo.query!(
        "INSERT INTO families(name,creator_id,created_at,updated_at) VALUES('Synthetic',$1,now(),now()) RETURNING id",
        [id]
      ).rows

    Repo.query!(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,1,now(),now())",
      [family, id]
    )

    conn = RailsUser.signed_in(id) |> RailsUser.connecting_as(id) |> get("/map/v2?panel=family")
    {:ok, view, html} = live(conn)
    assert has_element?(view, "input[form=native-map-family-layer][type=checkbox]")

    view
    |> form("#native-map-family-layer", %{"enabled" => "true"})
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
    assert has_element?(view, "#native-family-list[phx-update=ignore] #native-family-members")
    view |> form("#native-map-family-layer", %{"enabled" => "false"}) |> render_change()
    refute "Family Members" in Dawarich.Accounts.get(id).settings["enabled_map_layers"]
    render_async(view, 5000)
  end
end

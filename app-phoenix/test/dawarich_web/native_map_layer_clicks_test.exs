defmodule DawarichWeb.NativeMapLayerClicksTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "layer-click-#{id}@example.invalid",
      settings: %{"timezone" => "UTC", "enabled_map_layers" => ["Points", "Tracks"]}
    })

    {:ok, view, _} =
      RailsUser.signed_in(id)
      |> RailsUser.connecting_as(id)
      |> get("/map/v2?panel=layers")
      |> live()

    %{id: id, view: view}
  end

  test "layer commands save the browser choice without flipping duplicate values", %{
    id: id,
    view: view
  } do
    for enabled <- [false, false, true, true] do
      render_hook(view, "settings:layer", %{"layer" => "Points", "enabled" => enabled})
      layers = Dawarich.Accounts.get(id).settings["enabled_map_layers"]
      assert "Points" in layers == enabled
      assert "Tracks" in layers
      assert has_element?(view, "[data-testid=map-layer-points][checked]") == enabled
    end

    render_hook(view, "settings:layer", %{"layer" => "Points", "enabled" => "invalid"})
    assert "Points" in Dawarich.Accounts.get(id).settings["enabled_map_layers"]
  end

  test "flight commands save the browser choice without flipping duplicate values", %{view: view} do
    for enabled <- [false, false, true, true] do
      render_hook(view, "map:flights", %{"enabled" => enabled})

      assert_push_event(view, "map:config", %{
        "flightsPreferred" => ^enabled,
        "flightsEnabled" => false
      })
    end
  end
end

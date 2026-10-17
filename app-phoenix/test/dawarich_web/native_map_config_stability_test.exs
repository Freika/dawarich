defmodule DawarichWeb.NativeMapConfigStabilityTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  test "map readiness and unrelated events do not republish unchanged configuration" do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "map-stability-#{id}@example.invalid",
      settings: %{"timezone" => "UTC", "enabled_map_layers" => ["Points", "Tracks"]}
    })

    {:ok, view, _} =
      RailsUser.signed_in(id)
      |> RailsUser.connecting_as(id)
      |> get("/map/v2")
      |> live()

    assert_push_event(view, "map:config", %{})
    drain_configs()
    render_hook(view, "map:ready", %{"revision" => 1})
    refute_receive {_, {:push_event, "map:config", _}}
    render_hook(view, "map:failed", %{"code" => "synthetic"})
    refute_receive {_, {:push_event, "map:config", _}}
    assert has_element?(view, "[data-testid=map-button-timeline]")
  end

  defp drain_configs do
    receive do
      {_, {:push_event, "map:config", _}} -> drain_configs()
    after
      0 -> :ok
    end
  end
end

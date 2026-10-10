defmodule DawarichWeb.PublicDeliveryInventoryTest do
  use ExUnit.Case, async: true

  test "every route without mandatory user admission is in the public delivery inventory" do
    routes =
      DawarichWeb.Router.__routes__()
      |> Enum.map(fn route ->
        Phoenix.Router.route_info(
          DawarichWeb.Router,
          route.verb |> Atom.to_string() |> String.upcase(),
          route.path,
          "www.example.com"
        )
        |> Map.merge(Map.take(route, [:verb, :path]))
      end)
      |> Enum.reject(
        &Enum.any?(&1.pipe_through, fn pipeline ->
          pipeline in [
            :rails_user,
            :native_family_user,
            :rails_frame,
            :insights,
            :api_account,
            :api_account_destroy,
            :api_visits,
            :api_notes,
            :api_ingest,
            :api_foundation,
            :api_stats,
            :api_tiles,
            :api_places,
            :api_locations_photos,
            :api_family
          ]
        end)
      )
      |> Enum.map(&{&1.verb, &1.path, &1.plug, &1.pipe_through})
      |> Enum.sort()

    {inventory, _} =
      Code.eval_file(Path.expand("public_delivery_routes.exs", __DIR__))

    assert routes == Enum.sort(inventory)
  end
end

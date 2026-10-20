defmodule DawarichWeb.NativeMapLabelsPluralTest do
  use ExUnit.Case, async: true

  test "count labels carry a singular form the map client picks for one" do
    labels = DawarichWeb.NativeMapLabels.labels("en")
    assert labels["selection.delete_points"] == "Delete {count} Points"
    assert labels["selection.delete_points.one"] == "Delete 1 Point"
    assert labels["search.no_locations"] != "search.no_locations"
    assert labels["map_info.duration_hours_minutes"] =~ "{hours}"
  end

  test "info card labels resolve the Rails map_info, action and confirm texts" do
    labels = DawarichWeb.NativeMapLabels.labels("de")

    for key <-
          ~w(map_info.location_point map_info.coordinates map_info.time map_info.battery map_info.altitude map_info.speed map_info.radius map_info.center map_info.place map_info.area map_info.place_name_locked messages.edit messages.delete messages.anomaly_point map.confirm_delete_point_permanently points.address.address),
        do: assert(labels[key] not in [nil, key], key)

    assert labels["areas.confirm_delete_named"] =~ "{name}"
  end
end

defmodule DawarichWeb.NativeMapLabelsPluralTest do
  use ExUnit.Case, async: true

  test "count labels carry a singular form the map client picks for one" do
    labels = DawarichWeb.NativeMapLabels.labels("en")
    assert labels["selection.delete_points"] == "Delete {count} Points"
    assert labels["selection.delete_points.one"] == "Delete 1 Point"
    assert labels["search.no_locations"] != "search.no_locations"
    assert labels["map_info.duration_hours_minutes"] =~ "{hours}"
  end
end

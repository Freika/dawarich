defmodule DawarichWeb.NativeTripComponentTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  test "trip map insertion is keyed to its resource and excludes bulk geometry" do
    html = render_component(&DawarichWeb.NativeTripMapPanel.panel/1, locale: "de", config: %{"tripId" => 884101, "revision" => 1, "title" => "Trip", "api_key" => "synthetic-secret", "path" => [[13,52]], "deviceWindows" => [[1,2,3]], "routeOptions" => %{"distanceThresholdMeters" => 500, "secret" => "synthetic-secret"}})
    assert html =~ "id=\"native-trip-map-884101\""
    assert html =~ "phx-hook=\"Trip\""
    assert html =~ "distanceThresholdMeters"
    refute html =~ "synthetic-secret"
    refute html =~ "deviceWindows"
    refute html =~ "path"
  end
end

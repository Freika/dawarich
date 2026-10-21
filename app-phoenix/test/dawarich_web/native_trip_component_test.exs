defmodule DawarichWeb.NativeTripComponentTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  test "trip map insertion is keyed to its resource and excludes bulk geometry" do
    html =
      render_component(&DawarichWeb.NativeTripMapPanel.panel/1,
        locale: "de",
        config: %{
          "tripId" => 884_101,
          "revision" => 1,
          "title" => "Trip",
          "api_key" => "synthetic-secret",
          "path" => [[13, 52]],
          "deviceWindows" => [[1, 2, 3]],
          "routeOptions" => %{"distanceThresholdMeters" => 500, "secret" => "synthetic-secret"}
        }
      )

    html =
      html <>
        render_component(&DawarichWeb.NativeTripToolbar.toolbar/1,
          page: %{
            presentation: %{
              id: 884_101,
              settings: %{photos: false, airtrail: false},
              plan_toggle: false,
              recalculating: false
            },
            config: %{}
          },
          expanded: false,
          locale: "de"
        )

    assert html =~ "id=\"native-trip-map-884101\""
    assert html =~ "phx-hook=\"Trip\""
    assert html =~ "data-map-replay-open"
    assert html =~ "replay-density-container"
    assert html =~ "replay-day-nav"
    assert html =~ "distanceThresholdMeters"
    refute html =~ "synthetic-secret"
    refute html =~ "deviceWindows"

    [config] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[phx-hook=Trip]")
      |> LazyHTML.attribute("data-map-config")

    payload = Jason.decode!(config)
    refute Map.has_key?(payload, "path")
    refute Map.has_key?(payload, "deviceWindows")
  end
end

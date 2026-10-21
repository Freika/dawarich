defmodule DawarichWeb.TripSharedComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias DawarichWeb.MapReplay

  defp elements(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  test "map replay defaults keep the map controller and omit day navigation" do
    html = render_component(&MapReplay.replay_panel/1, locale: "en")
    assert html =~ ~s(data-maps--maplibre-target="replayPanel")

    assert LazyHTML.attribute(elements(html, "button.replay-close"), "data-action") == [
             "click->maps--maplibre#toggleReplay"
           ]

    refute html =~ "replayPrevDayButton"
    refute html =~ "replayNextDayButton"
    refute html =~ "trip-maplibre"
  end

  test "trip replay has both day navigation buttons and only trip targets" do
    html =
      render_component(&MapReplay.replay_panel/1,
        locale: "en",
        stimulus: "trip-maplibre",
        show_day_nav: true
      )

    assert html =~ ~s(data-trip-maplibre-target="replayPanel")

    assert LazyHTML.attribute(
             elements(html, "[data-trip-maplibre-target=replayPrevDayButton]"),
             "data-action"
           ) == ["click->trip-maplibre#replayPrevDay"]

    assert LazyHTML.attribute(
             elements(html, "[data-trip-maplibre-target=replayNextDayButton]"),
             "data-action"
           ) == ["click->trip-maplibre#replayNextDay"]

    assert html =~ ~s(data-trip-maplibre-target="replayPrevDayButton")
    assert html =~ ~s(data-trip-maplibre-target="replayNextDayButton")
    refute html =~ "maps--maplibre"
  end
end

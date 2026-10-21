defmodule DawarichWeb.MapStimulusTest do
  use ExUnit.Case, async: true

  alias Dawarich.Test.MapStimulus

  @map """
  <html><body><div id="map-shell" data-turbo="true" data-controller="maps--maplibre">
  <button data-action="click->maps--maplibre#toggleReplay"></button>
  </div></body></html>
  """

  test "the default comparator keeps A6 map controllers and actions" do
    assert MapStimulus.attributes(@map) == [
             {"#map-shell", "div", [{"data-controller", "maps--maplibre"}]},
             {"#map-shell", "button", [{"data-action", "click->maps--maplibre#toggleReplay"}]}
           ]
  end

  test "a scoped trip comparison keeps controller values and replay actions" do
    html = """
    <html><body><div id="trip-shell" data-turbo="true">
      <div data-controller="trip-maplibre" data-trip-maplibre-meters-between-routes-value="750">
        <button data-trip-maplibre-target="replayPrevDayButton" data-action="click->trip-maplibre#replayPrevDay"></button>
      </div>
    </div></body></html>
    """

    assert MapStimulus.attributes(html, ["#trip-shell"]) == [
             {"#trip-shell", "div",
              [
                {"data-controller", "trip-maplibre"},
                {"data-trip-maplibre-meters-between-routes-value", "750"}
              ]},
             {"#trip-shell", "button",
              [
                {"data-action", "click->trip-maplibre#replayPrevDay"},
                {"data-trip-maplibre-target", "replayPrevDayButton"}
              ]}
           ]
  end
end

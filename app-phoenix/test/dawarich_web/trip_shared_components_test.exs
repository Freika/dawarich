defmodule DawarichWeb.TripSharedComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias DawarichWeb.{MapReplay, PosterStudio}

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

  test "poster studio keeps map date controls by default and accepts the trip static range" do
    page = %{
      themes: [],
      posters: [],
      posters_stream: "signed",
      print_order_url: "https://prints.dawarich.app/api/orders"
    }

    options = [page: page, locale: "en", rails_csrf_token: "csrf"]
    map = render_component(&PosterStudio.poster_studio/1, options)

    assert LazyHTML.attribute(
             elements(map, "input[type=datetime-local]"),
             "data-poster-studio-editor-target"
           ) == ["dateStart", "dateEnd"]

    assert map =~ ~s(data-action="poster-studio-editor#applyDates")

    trip =
      render_component(
        &PosterStudio.poster_studio/1,
        options ++ [date_range_label: "9 May 2026 – 12 May 2026"]
      )

    assert trip =~ "9 May 2026 – 12 May 2026"
    assert Enum.empty?(elements(trip, "input[type=datetime-local]"))
    refute trip =~ "poster-studio-editor#applyDates"
  end
end

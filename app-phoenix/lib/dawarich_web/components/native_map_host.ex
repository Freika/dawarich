defmodule DawarichWeb.NativeMapHost do
  @moduledoc false
  use Phoenix.Component

  @fields ~w(namespace revision title styleUrl range mapOptions epoch pointsEnabled tracksEnabled heatmapEnabled trackColor styleName flightsEnabled fogEnabled fogMode fogRadius hexagonsEnabled scratchEnabled photosEnabled visitsEnabled placesEnabled areasEnabled anomaliesEnabled placesTagFilters tripId planEnabled routeOptions shareId publicType routeEnabled validUntil byDay)
  @range ~w(startAt endAt importId timezone)
  @options ~w(center zoom minZoom maxZoom bearing pitch projection interactive attributionControl)

  attr :id, :string, required: true
  attr :config, :map, required: true
  attr :hook, :string, default: "Map"
  attr :locale, :string, default: "en"
  attr :class, :string, default: "relative min-w-0 h-full w-full"

  def map_host(assigns) do
    locale =
      if assigns.locale in Dawarich.I18n.available_locales(), do: assigns.locale, else: "en"

    {:ok, label} = Dawarich.I18n.t(locale, "javascript.hexagons.points", %{"count" => "{count}"})

    photo_labels =
      Map.new(
        ~w(common.unknown search.unknown_location map_info.video map_info.photo map_info.coordinates map_info.source),
        fn key ->
          {:ok, value} = Dawarich.I18n.t(locale, "javascript." <> key)
          {key, value}
        end
      )

    entity_labels =
      Map.new(
        ~w(map_info.time map_info.reason map_info.start map_info.end anomalies.low_accuracy anomalies.impossible_speed),
        fn key ->
          {:ok, value} =
            Dawarich.I18n.t(locale, "javascript." <> key, %{
              "accuracy" => "{accuracy}",
              "threshold" => "{threshold}"
            })

          {key, value}
        end
      )

    config =
      assigns.config
      |> Map.take(@fields)
      |> Map.put("locale", locale)
      |> Map.put("uiLabels", DawarichWeb.NativeMapLabels.labels(locale))
      |> Map.put("photoLabels", photo_labels)
      |> Map.put("entityLabels", entity_labels)
      |> Map.put("hexagonLabel", label |> LazyHTML.from_fragment() |> LazyHTML.text())
      |> Map.update(
        "routeOptions",
        %{},
        &Map.take(&1, ~w(distanceThresholdMeters timeThresholdMinutes))
      )
      |> Map.update("range", %{}, &Map.take(&1, @range))
      |> Map.update("mapOptions", %{}, &Map.take(&1, @options))

    assigns = assign(assigns, :serialized_config, Jason.encode!(config))

    ~H"""
    <div
      id={@id}
      class={@class}
      phx-hook={@hook}
      phx-update="ignore"
      data-map-config={@serialized_config}
      data-map-state="loading"
    >
    </div>
    """
  end
end

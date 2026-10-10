defmodule DawarichWeb.NativeMapHost do
  @moduledoc false
  use Phoenix.Component

  @fields ~w(namespace revision title styleUrl range mapOptions epoch pointsEnabled tracksEnabled heatmapEnabled trackColor styleName flightsEnabled fogEnabled fogMode fogRadius hexagonsEnabled scratchEnabled)
  @range ~w(startAt endAt importId timezone)
  @options ~w(center zoom minZoom maxZoom bearing pitch projection interactive attributionControl)

  attr :id, :string, required: true
  attr :config, :map, required: true
  attr :locale, :string, default: "en"
  attr :class, :string, default: "relative min-w-0 h-full w-full"

  def map_host(assigns) do
    locale =
      if assigns.locale in Dawarich.I18n.available_locales(), do: assigns.locale, else: "en"

    {:ok, label} = Dawarich.I18n.t(locale, "javascript.hexagons.points", %{"count" => "{count}"})

    config =
      assigns.config
      |> Map.take(@fields)
      |> Map.put("locale", locale)
      |> Map.put("hexagonLabel", label |> LazyHTML.from_fragment() |> LazyHTML.text())
      |> Map.update("range", %{}, &Map.take(&1, @range))
      |> Map.update("mapOptions", %{}, &Map.take(&1, @options))

    assigns = assign(assigns, :serialized_config, Jason.encode!(config))

    ~H"""
    <div
      id={@id}
      class={@class}
      phx-hook="Map"
      phx-update="ignore"
      data-map-config={@serialized_config}
      data-map-state="loading"
    >
    </div>
    """
  end
end

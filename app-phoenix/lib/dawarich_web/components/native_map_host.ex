defmodule DawarichWeb.NativeMapHost do
  @moduledoc false
  use Phoenix.Component

  @fields ~w(namespace revision title styleUrl range mapOptions)
  @range ~w(startAt endAt importId timezone)
  @options ~w(center zoom minZoom maxZoom bearing pitch projection interactive attributionControl)

  attr :id, :string, required: true
  attr :config, :map, required: true
  attr :class, :string, default: "relative min-w-0 h-full w-full"

  def map_host(assigns) do
    config =
      assigns.config
      |> Map.take(@fields)
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

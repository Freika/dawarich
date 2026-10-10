defmodule DawarichWeb.NativeMapPreview do
  @moduledoc false
  use Phoenix.Component
  @fields ~w(kind tripId uuid styleName interactive numbered revision)
  attr(:id, :string, required: true)
  attr(:config, :map, required: true)
  attr(:locale, :string, default: "en")
  attr(:class, :string, default: "h-full w-full min-w-0 bg-base-200")

  def preview(assigns) do
    locale =
      if assigns.locale in Dawarich.I18n.available_locales(), do: assigns.locale, else: "en"

    labels =
      Map.new(
        ~w(common.not_available map_info.location_data map_info.points map_info.h3_index map_info.time_range map_info.center),
        fn key ->
          {:ok, value} = Dawarich.I18n.t(locale, "javascript." <> key)
          {key, value}
        end
      )

    config =
      assigns.config
      |> Map.take(@fields)
      |> Map.put("locale", locale)
      |> Map.put("labels", labels)
      |> Map.put(
        "range",
        Map.take(assigns.config["range"] || %{}, ~w(startAt endAt importId timezone))
      )
      |> Map.put(
        "bounds",
        Map.take(assigns.config["bounds"] || %{}, ~w(point_count min_lat max_lat min_lng max_lng))
      )

    assigns = assign(assigns, :serialized_config, Jason.encode!(config))

    ~H"""
    <div id={@id} class={@class} phx-hook="MapPreview" phx-update="ignore" data-map-config={@serialized_config} data-map-state="loading"></div>
    """
  end
end

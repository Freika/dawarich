defmodule DawarichWeb.NativeTripMapPanel do
  @moduledoc false
  use Phoenix.Component
  attr :id, :string, default: nil
  attr :config, :map, required: true
  attr :locale, :string, default: "en"

  def panel(assigns) do
    assigns = assign(assigns, :id, assigns.id || "native-trip-map-#{assigns.config["tripId"]}")

    ~H"""
    <div data-native-map-root class="relative min-w-0 w-full h-full">
      <DawarichWeb.NativeMapReplay.panel id={@id <> "-replay"} locale={@locale} />
      <DawarichWeb.NativeMapHost.map_host
        id={@id}
        config={@config}
        locale={@locale}
        hook="Trip"
        class="relative min-w-0 w-full h-full min-h-80 overflow-hidden rounded-lg"
      />
    </div>
    """
  end
end

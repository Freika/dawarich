defmodule DawarichWeb.NativeTripMapPanel do
  @moduledoc false
  use Phoenix.Component
  attr :id, :string, default: "native-trip-map"
  attr :config, :map, required: true
  attr :locale, :string, default: "en"

  def panel(assigns) do
    ~H"""
    <DawarichWeb.NativeMapHost.map_host
      id={@id}
      config={@config}
      locale={@locale}
      hook="Trip"
      class="relative min-w-0 w-full h-full min-h-80 overflow-hidden rounded-lg"
    />
    """
  end
end

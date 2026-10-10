defmodule DawarichWeb.NativeTripMapPanel do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  attr :id, :string, default: nil
  attr :config, :map, required: true
  attr :locale, :string, default: "en"

  def panel(assigns) do
    assigns = assign(assigns, :id, assigns.id || "native-trip-map-#{assigns.config["tripId"]}")

    ~H"""
    <div class="relative min-w-0 w-full h-full">
      <button
        type="button"
        data-testid="map-button-poster"
        class="btn btn-sm h-auto whitespace-normal"
      >{t(@locale, "map.maplibre.button_cluster.poster_studio", %{})}</button>
      <button type="button" data-testid="map-button-video" class="btn btn-sm h-auto whitespace-normal">{t(
        @locale,
        "map.maplibre.button_cluster.video_studio",
        %{}
      )}</button>
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

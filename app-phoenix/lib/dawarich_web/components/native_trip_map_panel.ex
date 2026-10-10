defmodule DawarichWeb.NativeTripMapPanel do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  attr :id, :string, default: nil
  attr :config, :map, required: true
  attr :locale, :string, default: "en"

  attr :has_path, :boolean, default: true
  attr :state, :atom, default: :path
  attr :future, :boolean, default: false

  def panel(assigns) do
    assigns = assign(assigns, :id, assigns.id || "native-trip-map-#{assigns.config["tripId"]}")

    ~H"""
    <div class="relative min-w-0 w-full h-full">
      <button
        type="button"
        data-testid="map-button-poster"
        disabled={!@has_path}
        class="btn btn-sm h-auto whitespace-normal"
      >{t(@locale, "map.maplibre.button_cluster.poster_studio", %{})}</button>
      <button
        type="button"
        disabled={!@has_path}
        data-testid="map-button-video"
        class="btn btn-sm h-auto whitespace-normal"
      >{t(
        @locale,
        "map.maplibre.button_cluster.video_studio",
        %{}
      )}</button>
      <DawarichWeb.NativeMapReplay.panel :if={@state == :path} id={@id <> "-replay"} locale={@locale} />
      <DawarichWeb.NativeMapHost.map_host
        :if={@state in [:path, :plan]}
        id={@id}
        config={@config}
        locale={@locale}
        hook="Trip"
        class="relative min-w-0 w-full h-full min-h-80 overflow-hidden rounded-lg"
      />
      <p
        :if={@state != :path}
        data-trip-map-state={@state}
        role="status"
        class="min-w-0 [overflow-wrap:anywhere] p-3"
      >
        {t(@locale, "trips.show." <> state_key(@state, @future), %{})}
      </p>
    </div>
    """
  end

  defp state_key(:future, _), do: "trip_has_not_started_yet"
  defp state_key(:calculating, _), do: "trip_path_is_being_calculated"
  defp state_key(:plan, true), do: "trip_has_not_started_yet"
  defp state_key(_, _), do: "no_locations_recorded"
end

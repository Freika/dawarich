defmodule DawarichWeb.MapIndex do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  import DawarichWeb.MapControls, only: [date_navigation: 1, webgl_error: 1]
  import DawarichWeb.MapButtonCluster, only: [button_cluster: 1]
  import DawarichWeb.MapPanel, only: [settings_panel: 1]
  import DawarichWeb.MapReplay, only: [replay_panel: 1]

  import DawarichWeb.MapModals, only: [visit_creation_modal: 1, area_creation_modal: 1]
  import DawarichWeb.MapPlaceModal, only: [place_creation_modal: 1]
  import DawarichWeb.PosterStudio, only: [poster_studio: 1]
  import DawarichWeb.VideoStudio, only: [video_studio: 1]

  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat

  attr :page, :map, required: true
  attr :params, :map, required: true
  attr :locale, :string, required: true
  attr :base_url, :string, required: true
  attr :self_hosted, :boolean, required: true
  attr :rails_csrf_token, :string, default: nil
  attr :now, :any, required: true

  def map_page(assigns) do
    assigns = assign(assigns, :timeline, assigns.params["panel"] == "timeline")

    ~H"""
    <.date_navigation page={@page} params={@params} locale={@locale} />
    <div
      id="maps-maplibre-container"
      data-controller="maps--maplibre area-drawer maps--maplibre-realtime place-detail"
      data-action="place:open@document->place-detail#open place:deleted@document->maps--maplibre#handlePlaceDeleted"
      data-maps--maplibre-api-key-value={@page.api_key}
      data-maps--maplibre-start-date-value={@page.window.start}
      data-maps--maplibre-end-date-value={@page.window.end}
      data-maps--maplibre-timezone-value={@page.window.iana}
      data-maps--maplibre-user-plan-value={@page.plan}
      data-maps--maplibre-import-id-value={to_string(@page.import_id)}
      data-maps--maplibre-upgrade-url-value={@page.upgrade_url}
      data-maps--maplibre-realtime-enabled-value="true"
      data-maps--maplibre-realtime-live-mode-value={to_string(@page.live_map)}
      {place_values(@page.place)}
      data-family-members-features-value={@page.features_json}
      style="width: 100%; height: 100%; position: relative;"
    >
      <.webgl_error locale={@locale} />
      <div
        data-maps--maplibre-target="container"
        class={"maps-maplibre-container#{if @timeline, do: " panel-open panel-timeline-expanded"}"}
        style="width: 100%; height: 100%;"
      >
      </div>
      <div data-maps--maplibre-target="progressBadge" class="map-progress-badge">
        <span class="map-progress-badge-dot"></span>
        <span data-maps--maplibre-target="progressBadgeText">{t(
          @locale,
          "map.maplibre.index.loading",
          %{}
        )}</span>
      </div>
      <.button_cluster locale={@locale} self_hosted={@self_hosted} />
      <div
        class="timeline-map-overlay timeline-map-overlay--scope"
        data-timeline-feed-target="scopeBadge"
      >
        <span class="font-semibold">{t(@locale, "map.maplibre.index.pick_a_day", %{})}</span>
      </div>
      <.settings_panel
        page={@page}
        params={@params}
        locale={@locale}
        self_hosted={@self_hosted}
        rails_csrf_token={@rails_csrf_token}
      />
      <.poster_studio page={@page} locale={@locale} rails_csrf_token={@rails_csrf_token} />
      <.video_studio page={@page} locale={@locale} base_url={@base_url} />
      <.replay_panel locale={@locale} />
      <.visit_creation_modal page={@page} locale={@locale} />
      <.area_creation_modal locale={@locale} rails_csrf_token={@rails_csrf_token} />
      <.place_creation_modal page={@page} locale={@locale} rails_csrf_token={@rails_csrf_token} />
      <turbo-frame
        id="place-drawer"
        src={@page.place && "/places/#{@page.place.id}"}
        data-place-detail-target="frame"
      >
      </turbo-frame>
    </div>
    """
  end

  defp place_values(nil), do: []

  defp place_values(place),
    do: [
      {"data-maps--maplibre-place-latitude-value", RubyFloat.to_s(place.lat)},
      {"data-maps--maplibre-place-longitude-value", RubyFloat.to_s(place.lon)}
    ]
end

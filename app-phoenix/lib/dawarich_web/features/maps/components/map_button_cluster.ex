defmodule DawarichWeb.MapButtonCluster do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.Icon

  attr :locale, :string, required: true
  attr :self_hosted, :boolean, required: true

  def button_cluster(assigns) do
    ~H"""
    <div
      class="map-button-cluster"
      data-controller="map-panel"
      role="toolbar"
      aria-label={c(@locale, "map_controls")}
    >
      <button
        type="button"
        class="map-button-cluster__btn"
        data-action="click->map-panel#openTab"
        aria-expanded="false"
        data-tab="timeline-feed"
        data-testid="map-button-timeline"
        aria-label={c(@locale, "timeline")}
        aria-keyshortcuts="T"
        title={c(@locale, "timeline_t")}
      >
        <Icon.icon name="calendar-clock" class="size-6" />
      </button>

      <button
        type="button"
        class="map-button-cluster__btn"
        data-action="click->map-panel#openTab"
        aria-expanded="false"
        data-tab="layers"
        data-testid="map-button-layers"
        aria-label={c(@locale, "layers")}
        aria-keyshortcuts="L"
        title={c(@locale, "layers_l")}
      >
        <Icon.icon name="layer" class="size-6" />
      </button>

      <button
        type="button"
        class="map-button-cluster__btn"
        data-action="click->map-panel#openTab"
        aria-expanded="false"
        data-tab="search"
        data-testid="map-button-search"
        aria-label={c(@locale, "search")}
        aria-keyshortcuts="/"
        title={c(@locale, "search_2")}
      >
        <Icon.icon name="search" class="size-6" />
      </button>

      <button
        type="button"
        class="map-button-cluster__btn map-button-cluster__btn--create"
        data-action="click->map-panel#openTab"
        aria-expanded="false"
        data-tab="tools"
        data-testid="map-button-create"
        aria-label={c(@locale, "create")}
        aria-keyshortcuts="C"
        title={c(@locale, "create_c")}
      >
        <Icon.icon name="circle-plus" class="size-6" />
      </button>

      <button
        type="button"
        class="map-button-cluster__btn"
        data-action="click->maps--maplibre#toggleReplay"
        data-testid="map-button-replay"
        aria-label={c(@locale, "replay")}
        aria-keyshortcuts="R"
        title={c(@locale, "replay_points_for_the_current_date_range_r")}
      >
        <Icon.icon name="play" class="w-5 h-5" aria_hidden />
      </button>

      <button
        type="button"
        class="map-button-cluster__btn"
        data-action="click->map-panel#openPosterStudio"
        data-testid="map-button-poster"
        aria-label={c(@locale, "poster_studio")}
        title={c(@locale, "poster_studio")}
      >
        <Icon.icon name="image" class="size-6" />
      </button>

      <button
        type="button"
        class="map-button-cluster__btn"
        data-action="click->map-panel#openVideoStudio"
        data-testid="map-button-video"
        aria-label={c(@locale, "video_studio")}
        title={c(@locale, "video_studio")}
      >
        <Icon.icon name="video" class="size-6" />
      </button>

      <div class="map-button-cluster__divider" aria-hidden="true"></div>

      <button
        type="button"
        class="map-button-cluster__btn map-button-cluster__btn--muted"
        data-action="click->map-panel#openTab"
        aria-expanded="false"
        data-tab="settings"
        data-testid="map-button-settings"
        aria-label={c(@locale, "settings")}
        aria-keyshortcuts="S"
        title={c(@locale, "settings_s")}
      >
        <Icon.icon name="settings" class="size-6" />
      </button>

      <button
        :if={!@self_hosted}
        type="button"
        class="map-button-cluster__btn map-button-cluster__btn--muted"
        data-action="click->map-panel#openTab"
        aria-expanded="false"
        data-tab="links"
        data-testid="map-button-links"
        aria-label={c(@locale, "links")}
        title={c(@locale, "links")}
      >
        <Icon.icon name="info" class="size-6" />
      </button>
    </div>
    """
  end

  defp c(locale, key), do: t(locale, "map.maplibre.button_cluster." <> key, %{})
end

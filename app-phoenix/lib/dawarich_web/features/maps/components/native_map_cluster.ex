defmodule DawarichWeb.NativeMapCluster do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.Icon

  attr :locale, :string, required: true
  attr :panel, :string, default: ""
  attr :family, :boolean, default: false
  attr :self_hosted, :boolean, default: true

  def cluster(assigns) do
    ~H"""
    <div class="map-button-cluster" role="toolbar" aria-label={c(@locale, "map_controls")}>
      <.tab
        panel={@panel}
        tab="timeline"
        data_tab="timeline-feed"
        testid="map-button-timeline"
        icon="calendar-clock"
        label={c(@locale, "timeline")}
        keys="T"
        title={c(@locale, "timeline_t")}
      />
      <.tab
        panel={@panel}
        tab="layers"
        data_tab="layers"
        testid="map-button-layers"
        icon="layer"
        label={c(@locale, "layers")}
        keys="L"
        title={c(@locale, "layers_l")}
      />
      <.tab
        panel={@panel}
        tab="search"
        data_tab="search"
        testid="map-button-search"
        icon="search"
        label={c(@locale, "search")}
        keys="/"
        title={c(@locale, "search_2")}
      />
      <.tab
        :if={@family}
        panel={@panel}
        tab="family"
        data_tab="family"
        testid="map-button-family"
        icon="users"
        label={c(@locale, "family")}
        keys="F"
        title={c(@locale, "family_f")}
      />
      <.tab
        panel={@panel}
        tab="tools"
        data_tab="tools"
        testid="map-button-create"
        icon="wrench"
        label={c(@locale, "tools")}
        keys="C"
        title={c(@locale, "tools_c")}
        class="map-button-cluster__btn--create"
      />
      <button
        type="button"
        class="map-button-cluster__btn"
        data-map-replay-open
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
        data-testid="map-button-poster"
        aria-label={c(@locale, "poster_studio")}
        title={c(@locale, "poster_studio")}
      >
        <Icon.icon name="image" class="size-6" />
      </button>
      <button
        type="button"
        class="map-button-cluster__btn"
        data-testid="map-button-video"
        aria-label={c(@locale, "video_studio")}
        title={c(@locale, "video_studio")}
      >
        <Icon.icon name="video" class="size-6" />
      </button>
      <div class="map-button-cluster__divider" aria-hidden="true"></div>
      <.tab
        panel={@panel}
        tab="settings"
        data_tab="settings"
        testid="map-button-settings"
        icon="settings"
        label={c(@locale, "settings")}
        keys="S"
        title={c(@locale, "settings_s")}
        class="map-button-cluster__btn--muted"
      />
      <.tab
        :if={!@self_hosted}
        panel={@panel}
        tab="links"
        data_tab="links"
        testid="map-button-links"
        icon="info"
        label={c(@locale, "links")}
        title={c(@locale, "links")}
        class="map-button-cluster__btn--muted"
      />
    </div>
    """
  end

  attr :panel, :string, required: true
  attr :tab, :string, required: true
  attr :data_tab, :string, required: true
  attr :testid, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :title, :string, required: true
  attr :keys, :string, default: nil
  attr :class, :string, default: nil

  defp tab(assigns) do
    ~H"""
    <button
      type="button"
      class={["map-button-cluster__btn", @class, @panel == @tab && "map-button-cluster__btn--active"]}
      phx-click="map:panel"
      phx-value-panel={@tab}
      phx-value-toggle="true"
      aria-expanded={to_string(@panel == @tab)}
      data-tab={@data_tab}
      data-testid={@testid}
      aria-label={@label}
      aria-keyshortcuts={@keys}
      title={@title}
    >
      <Icon.icon name={@icon} class="size-6" />
    </button>
    """
  end

  defp c(locale, key), do: t(locale, "map.maplibre.button_cluster." <> key, %{})
end

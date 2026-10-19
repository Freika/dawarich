defmodule DawarichWeb.NativeMapPage do
  @moduledoc false
  use DawarichWeb, :html

  @titles %{
    "timeline" => "timeline",
    "layers" => "layers",
    "search" => "search",
    "family" => "family",
    "tools" => "tools",
    "settings" => "settings",
    "links" => "links"
  }

  def page(assigns) do
    assigns =
      if assigns[:page] do
        panel = assigns.map_url["panel"] || ""

        assign(assigns,
          selected_date: selected_date(assigns),
          panel: panel,
          timeline_open: panel == "timeline"
        )
      else
        assigns
      end

    ~H"""
    <div class="fixed w-full z-40 h-[calc(4rem+env(safe-area-inset-top))] pt-[env(safe-area-inset-top)] border-b border-base-content/10">
      <div class="container mx-auto h-full w-full flex items-center">
        <DawarichWeb.NativeMapChrome.header {assigns} />
      </div>
    </div>
    <div :if={@page} class="fixed top-[calc(4rem+env(safe-area-inset-top))] w-full z-50">
      <div class="container mx-auto px-5">
        <DawarichWeb.Chrome.flash locale={@locale} flash={@flash} native />
      </div>
    </div>
    <div
      :if={@page}
      id="native-map-page"
      class="absolute top-[calc(4rem+env(safe-area-inset-top))] left-0 right-0 bottom-0 w-full z-20 flex flex-col"
    >
      <DawarichWeb.NativeMapControls.date_navigation
        url={@map_url}
        window={@page.window}
        locale={@locale}
        live_share={@page.live_share == true}
      />
      <div
        id="maps-maplibre-container"
        data-native-map-root
        data-native-selected-date={@selected_date}
        style="width: 100%; height: 100%; position: relative;"
      >
        <div id="native-map-webgl-error" class="hidden">
          <div class="flex items-center justify-center h-full bg-base-200 text-center p-8">
            <div>
              <h3 class="text-lg font-bold mb-2">
                {t(@locale, "map.maplibre.webgl_error.webgl_is_not_available", %{})}
              </h3>
              <p class="text-sm text-base-content/70">
                {t(
                  @locale,
                  "map.maplibre.webgl_error.map_v2_requires_webgl_to_render_maps_please_enable_hardware",
                  %{}
                )}
              </p>
            </div>
          </div>
        </div>
        <DawarichWeb.NativeMapHost.map_host
          id="native-map"
          config={@map_config}
          locale={@locale}
          loading={false}
          class={[
            "maps-maplibre-container",
            @panel != "" && "panel-open",
            @timeline_open && "panel-timeline-expanded"
          ]}
          style="width: 100%; height: 100%;"
        />
        <div class="map-progress-badge" data-map-loading>
          <span class="map-progress-badge-dot"></span>
          <span>{t(@locale, "map.maplibre.index.loading", %{})}</span>
        </div>
        <DawarichWeb.NativeMapCluster.cluster
          locale={@locale}
          panel={@panel}
          family={@page.family}
          self_hosted={assigns[:self_hosted] != false}
        />
        <div class="timeline-map-overlay timeline-map-overlay--scope">
          <span class="font-semibold">{t(@locale, "map.maplibre.index.pick_a_day", %{})}</span>
        </div>
        <div
          id="map-settings-panel"
          class={[
            "map-control-panel",
            @panel != "" && "open",
            @timeline_open && "timeline-expanded"
          ]}
        >
          <div class="panel-content">
            <div class="panel-header">
              <button
                id="native-map-panel-close"
                class="btn btn-ghost btn-sm btn-circle"
                phx-click="map:panel"
                phx-value-panel=""
                title={t(@locale, "map.maplibre.settings_panel.close_panel", %{})}
              >
                <DawarichWeb.Icon.icon name="x" class="size-6" />
              </button>
              <h3 class="panel-title">{title(@locale, @panel)}</h3>
            </div>
            <div id="native-map-controls" class="panel-body">
              <DawarichWeb.NativeMapTabs.tabs {assigns} />
            </div>
          </div>
        </div>
        <DawarichWeb.NativeMapTools.overlays {assigns} />
      </div>
    </div>
    <.live_component
      :if={@current_scope && @page}
      module={DawarichWeb.OnboardingLiveComponent}
      id="onboarding"
      scope={@current_scope}
      navbar={@navbar}
      locale={@locale}
      base_url={assigns[:base_url] || ""}
      rails_csrf_token=""
      auto_open={true}
    />
    <div :if={@map_error} role="alert">{to_string(@map_error)}</div>
    """
  end

  defp title(locale, panel) do
    case @titles[panel] do
      nil -> t(locale, "map.maplibre.settings_panel.layers", %{})
      key -> t(locale, "javascript.map_panel." <> key, %{})
    end
  end

  defp selected_date(assigns) do
    case {assigns.map_url["date"], Date.from_iso8601(assigns.map_url["date"] || "")} do
      {_, {:ok, date}} -> Date.to_iso8601(date)
      {"today", _} -> Date.to_iso8601(assigns.page.window.start_date)
      _ -> nil
    end
  end
end

defmodule DawarichWeb.NativeMapTabs do
  @moduledoc false
  use DawarichWeb, :html

  def tabs(assigns) do
    ~H"""
    <div class={tab_class(@panel, "search")} data-tab-content="search">
      <div class="form-control w-full">
        <label class="label">
          <span class="label-text">{p(@locale, "search_for_a_place")}</span>
        </label>
        <div class="relative">
          <input
            id="native-map-search"
            type="text"
            placeholder={p(@locale, "enter_name_of_a_place")}
            aria-label={p(@locale, "search_for_a_place")}
            class="input input-bordered w-full"
            autocomplete="off"
            phx-update="ignore"
            data-map-search
          />
          <div
            id="native-map-suggestions"
            data-map-suggestions
            phx-update="ignore"
            class="absolute z-50 w-full mt-1 bg-base-100 rounded-lg shadow-lg border border-base-300 hidden max-height:400px;  overflow-y-auto"
          >
          </div>
        </div>
        <p class="text-xs text-base-content/60 mt-2">
          {p(@locale, "search_for_a_location_to_find_places_you_visited")}
        </p>
      </div>
    </div>

    <DawarichWeb.NativeMapLayersTab.tab
      locale={@locale}
      panel={@panel}
      settings={assigns[:map_settings]}
      config={@map_config}
      page={@page}
    />

    <div :if={@page.family} class={tab_class(@panel, "family")} data-tab-content="family">
      <DawarichWeb.NativeMapFamily.panel
        :if={@panel == "family" && assigns[:map_settings]}
        locale={@locale}
        settings={@map_settings}
      />
    </div>

    <DawarichWeb.NativeMapSettingsTab.tab
      locale={@locale}
      panel={@panel}
      settings={assigns[:map_settings]}
      page={@page}
    />

    <DawarichWeb.NativeMapTimelineTab.tab
      locale={@locale}
      open={@timeline_open}
      calendar={assigns[:calendar]}
      timeline={assigns[:timeline]}
      filter={assigns[:timeline_filter]}
      selection={assigns[:timeline_selection]}
      selected_visit={assigns[:selected_visit]}
      selected_date={@selected_date}
      tags={@page.timeline_tags}
      track_info={assigns[:track_info]}
      segments={assigns[:segment_drawer]}
      editing={if(match?(%{inline: true}, assigns[:visit_dialog]), do: @visit_dialog)}
      unit={@map_config["distanceUnit"] || "km"}
    />

    <DawarichWeb.NativeMapToolsTab.tab
      locale={@locale}
      panel={@panel}
      page={@page}
      restricted={!!(assigns[:map_settings] && @map_settings.restricted)}
      enrichment={assigns[:enrichment]}
    />

    <div
      :if={assigns[:self_hosted] == false}
      class={tab_class(@panel, "links")}
      data-tab-content="links"
    >
      <DawarichWeb.NativeMapLinks.links :if={@panel == "links"} locale={@locale} />
    </div>
    """
  end

  defp tab_class(panel, tab), do: ["tab-content", panel == tab && "active"]

  defp p(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end

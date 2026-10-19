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
            class="input input-bordered w-full"
            autocomplete="off"
            phx-update="ignore"
            data-map-search
          />
          <ul
            id="native-map-suggestions"
            data-map-suggestions
            role="listbox"
            phx-update="ignore"
            class="absolute z-50 w-full mt-1 bg-base-100 rounded-lg shadow-lg border border-base-300 hidden max-height:400px;  overflow-y-auto"
          >
          </ul>
        </div>
        <p class="text-xs text-base-content/60 mt-2">
          {p(@locale, "search_for_a_location_to_find_places_you_visited")}
        </p>
      </div>
      <section id="native-map-search-visits" data-map-search-visits phx-update="ignore"></section>
    </div>

    <div class={tab_class(@panel, "layers")} data-tab-content="layers">
      <DawarichWeb.NativeMapPanels.layer_panel
        :if={@panel == "layers" && assigns[:map_settings]}
        locale={@locale}
        settings={@map_settings}
        config={@map_config}
      />
      <DawarichWeb.NativePlaceFilters.filters
        :if={@panel == "layers" && assigns[:map_settings] && @map_config["placesEnabled"]}
        tags={@page.tags}
        filters={@map_settings.saved["places_tag_filters"]}
        locale={@locale}
      />
    </div>

    <div :if={@page.family} class={tab_class(@panel, "family")} data-tab-content="family">
      <DawarichWeb.NativeMapFamily.panel
        :if={@panel == "family" && assigns[:map_settings]}
        locale={@locale}
        settings={@map_settings}
      />
    </div>

    <div class={tab_class(@panel, "settings")} data-tab-content="settings">
      <button
        type="button"
        data-testid="native-edit-points"
        class="btn btn-sm"
        phx-click="settings:point_edit"
        phx-value-enabled={to_string(!@map_config["editEnabled"])}
        aria-pressed={to_string(@map_config["editEnabled"])}
      >{p(@locale, "edit_points")}</button>
      <DawarichWeb.NativeMapSettings.panel
        :if={@panel == "settings"}
        settings={assigns[:map_settings]}
        locale={@locale}
      />
    </div>

    <div class={tab_class(@panel, "timeline")} data-tab-content="timeline-feed">
      <section :if={@timeline_open} id="native-map-panel">
        <DawarichWeb.NativeTimelineCalendar.calendar
          calendar={assigns[:calendar]}
          locale={@locale}
          selected_date={@selected_date}
        />
        <DawarichWeb.NativeTimelineFeed.feed
          timeline={assigns[:timeline]}
          selected_date={@selected_date}
          filter={assigns[:timeline_filter]}
          selection={assigns[:timeline_selection]}
          selected_visit={assigns[:selected_visit]}
          tags={@page.timeline_tags}
          locale={@locale}
        />
        <DawarichWeb.NativeTrackInfo.card
          track={assigns[:track_info]}
          unit={@map_config["distanceUnit"] || "km"}
          locale={@locale}
        />
      </section>
    </div>

    <div class={tab_class(@panel, "tools")} data-tab-content="tools">
      <button type="button" data-testid="native-create-visit" class="btn btn-sm">{t(
        @locale,
        "javascript.visits.create_new",
        %{}
      )}</button>
      <button type="button" data-testid="native-create-place" class="btn btn-sm">{t(
        @locale,
        "javascript.places.create_new",
        %{}
      )}</button>
      <button type="button" data-testid="native-create-area" class="btn btn-sm">{t(
        @locale,
        "javascript.areas.create_new",
        %{}
      )}</button>
      <button
        type="button"
        data-testid="native-select-area"
        class="btn btn-sm"
        phx-update="ignore"
        id="native-select-area"
        aria-pressed="false"
        data-select-message={t(@locale, "javascript.map_controls.select_area", %{})}
        data-cancel-message={t(@locale, "javascript.visits.cancel_selection", %{})}
        data-draw-message={
          t(@locale, "javascript.messages.draw_a_rectangle_on_the_map_to_select_points", %{})
        }
      >{t(@locale, "javascript.map_controls.select_area", %{})}</button>
      <section
        id="native-map-selection"
        data-map-selection
        phx-update="ignore"
        class="min-w-0 max-w-full"
        tabindex="0"
      >
      </section>
      <DawarichWeb.NativeMapEnrichment.tool
        :if={@panel == "tools" && @page.full_access && @page.immich}
        enrichment={assigns[:enrichment]}
        start_date={String.slice(@page.window.start, 0, 10)}
        end_date={String.slice(@page.window.end, 0, 10)}
        locale={@locale}
      />
    </div>

    <div
      :if={assigns[:self_hosted] == false}
      class={tab_class(@panel, "links")}
      data-tab-content="links"
    >
      <DawarichWeb.NativeMapLinks.links :if={@panel == "links"} locale={@locale} />
    </div>

    <div :if={@panel == "insights"} class="tab-content active" data-tab-content="insights">
      <DawarichWeb.NativeResidency.card residency={assigns[:residency]} locale={@locale} />
    </div>
    """
  end

  defp tab_class(panel, tab), do: ["tab-content", panel == tab && "active"]

  defp p(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end

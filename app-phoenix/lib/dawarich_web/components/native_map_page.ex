defmodule DawarichWeb.NativeMapPage do
  @moduledoc false
  use DawarichWeb, :html

  def page(assigns) do
    ~H"""
    <DawarichWeb.NativeMapChrome.header {assigns} />
    <div
      :if={@page}
      id="native-map-page"
      data-native-map-root
      class="relative w-full min-w-0 h-[calc(100dvh-4rem)] flex flex-col"
    >
      <DawarichWeb.Chrome.flash locale={@locale} flash={@flash} native />
      <DawarichWeb.NativeMapPanels.navigation locale={@locale} panel={@map_url["panel"] || ""} />
      <DawarichWeb.NativeMapPanels.layer_panel
        :if={@map_url["panel"] == "layers" && assigns[:map_settings]}
        locale={@locale}
        settings={@map_settings}
        config={@map_config}
      />
      <DawarichWeb.NativePlaceFilters.filters
        :if={@map_url["panel"] == "layers" && assigns[:map_settings] && @map_config["placesEnabled"]}
        tags={@page.tags}
        filters={@map_settings.saved["places_tag_filters"]}
        locale={@locale}
      />
      <DawarichWeb.NativeMapControls.date_navigation
        url={@map_url}
        window={@page.window}
        locale={@locale}
      />
      <div class="min-w-0 max-w-full">
        <input
          id="native-map-search"
          autocomplete="off"
          phx-update="ignore"
          data-map-search
          type="search"
          class="input input-bordered max-w-full"
          aria-label={t(@locale, "javascript.search.search_placeholder", %{})}
        />
        <ul
          data-map-suggestions
          role="listbox"
          class="min-w-0 [overflow-wrap:anywhere]"
          phx-update="ignore"
          id="native-map-suggestions"
        >
        </ul>
        <section
          data-map-search-visits
          id="native-map-search-visits"
          phx-update="ignore"
          class="min-w-0 max-w-full"
        >
        </section>
      </div>
      <p
        id="native-map-edit-error"
        data-map-edit-error
        phx-update="ignore"
        role="alert"
        class="min-w-0 [overflow-wrap:anywhere]"
      >
      </p>
      <p
        id="native-map-tool-status"
        data-map-tool-status
        role="status"
        phx-update="ignore"
        data-visit-message={
          t(@locale, "javascript.messages.click_on_the_map_to_place_a_visit_esc_to", %{})
        }
        data-place-message={t(@locale, "javascript.messages.click_on_the_map_to_place_a_place", %{})}
        class="min-w-0 [overflow-wrap:anywhere]"
      >
      </p>
      <button
        type="button"
        data-testid="native-edit-points"
        class="btn btn-sm"
        phx-click="settings:point_edit"
        phx-value-enabled={to_string(!@map_config["editEnabled"])}
        aria-pressed={to_string(@map_config["editEnabled"])}
      >{t(@locale, "map.maplibre.settings_panel.edit_points", %{})}</button>
      <button type="button" data-testid="native-create-area" class="btn btn-sm">{t(
        @locale,
        "javascript.areas.create_new",
        %{}
      )}</button>
      <section
        :if={@map_url["panel"] == "timeline"}
        id="native-map-panel"
        class="absolute left-0 top-40 bottom-0 z-10 overflow-auto w-96 max-w-full min-w-0 bg-base-100 p-3"
      >
        <DawarichWeb.NativeTimelineCalendar.calendar calendar={assigns[:calendar]} locale={@locale} />
        <DawarichWeb.NativeTimelineFeed.feed
          timeline={assigns[:timeline]}
          filter={assigns[:timeline_filter]}
          selection={assigns[:timeline_selection]}
          tags={@page.timeline_tags}
          locale={@locale}
        />
      </section>
      <DawarichWeb.NativeResidency.card
        :if={@map_url["panel"] == "insights"}
        residency={assigns[:residency]}
        locale={@locale}
      />
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
      >{t(
        @locale,
        "javascript.map_controls.select_area",
        %{}
      )}</button>
      <section
        id="native-map-selection"
        data-map-selection
        phx-update="ignore"
        class="min-w-0 max-w-full"
        tabindex="0"
      >
      </section>
      <DawarichWeb.NativeMapVisit.dialog dialog={assigns[:visit_dialog]} locale={@locale} />
      <DawarichWeb.NativePointAddress.drawer address={assigns[:point_address]} locale={@locale} />
      <button type="button" data-testid="native-create-visit" class="btn btn-sm">{t(
        @locale,
        "javascript.visits.create_new",
        %{}
      )}</button>
      <DawarichWeb.NativeMapPlace.dialog dialog={assigns[:place_dialog]} locale={@locale} />
      <button type="button" data-testid="native-create-place" class="btn btn-sm">{t(
        @locale,
        "javascript.places.create_new",
        %{}
      )}</button>
      <DawarichWeb.NativeMapSettings.panel
        :if={@map_url["panel"] == "settings"}
        settings={assigns[:map_settings]}
        locale={@locale}
      />
      <DawarichWeb.NativeMapEnrichment.tool
        :if={@map_url["panel"] == "tools" && @page.full_access && @page.immich}
        enrichment={assigns[:enrichment]}
        start_date={String.slice(@page.window.start, 0, 10)}
        end_date={String.slice(@page.window.end, 0, 10)}
        locale={@locale}
      />
      <DawarichWeb.NativeTrackInfo.card
        track={assigns[:track_info]}
        unit={@map_config["distanceUnit"] || "km"}
        locale={@locale}
      />
      <DawarichWeb.NativeSegmentEditor.drawer drawer={assigns[:segment_drawer]} locale={@locale} />
      <DawarichWeb.NativeAreaDialog.dialog dialog={assigns[:area_dialog]} locale={@locale} />
      <DawarichWeb.NativeMapReplay.panel id="native-map-replay" locale={@locale} />
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
      <DawarichWeb.NativePosterStudio.poster_studio
        themes={@page.themes}
        posters={@posters}
        print_order_url={@page.print_order_url}
        locale={@locale}
      />
      <.live_component
        module={DawarichWeb.VideoStudioLiveComponent}
        id="video-studio-owner"
        scope={@current_scope}
        locale={@locale}
        base_url={assigns[:base_url] || ""}
        themes={@page.themes}
      />
      <div class="relative flex-1 min-h-0 min-w-0">
        <DawarichWeb.NativeMapHost.map_host id="native-map" config={@map_config} locale={@locale} />
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
end

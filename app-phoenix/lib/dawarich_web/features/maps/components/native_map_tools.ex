defmodule DawarichWeb.NativeMapTools do
  @moduledoc false
  use DawarichWeb, :html

  def overlays(assigns) do
    ~H"""
    <form id="native-map-visit-filter" phx-change="map:visits_filter" class="hidden"></form>
    <form id="native-reclassify" phx-submit="settings:reclassify" class="hidden"></form>
    <form
      id="native-timeline-filter"
      phx-change="timeline:filter"
      phx-submit="timeline:filter"
      class="hidden"
    >
    </form>
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
    <DawarichWeb.NativeMapVisit.dialog dialog={assigns[:visit_dialog]} locale={@locale} />
    <DawarichWeb.NativeMapPlace.dialog dialog={assigns[:place_dialog]} locale={@locale} />
    <DawarichWeb.NativeAreaDialog.dialog dialog={assigns[:area_dialog]} locale={@locale} />
    <DawarichWeb.MapReplay.replay_panel id="native-map-replay" locale={@locale} native hook="native" />
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
    """
  end
end

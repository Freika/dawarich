defmodule DawarichWeb.NativeMapTools do
  @moduledoc false
  use DawarichWeb, :html

  def overlays(assigns) do
    ~H"""
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
    <p id="native-map-point-summary" data-map-point-summary phx-update="ignore" role="status" />
    <DawarichWeb.NativeMapVisit.dialog dialog={assigns[:visit_dialog]} locale={@locale} />
    <DawarichWeb.NativePointAddress.drawer address={assigns[:point_address]} locale={@locale} />
    <DawarichWeb.NativePlaceDrawer.drawer detail={assigns[:place_detail]} locale={@locale} />
    <DawarichWeb.NativeMapPlace.dialog dialog={assigns[:place_dialog]} locale={@locale} />
    <DawarichWeb.NativeSegmentEditor.drawer drawer={assigns[:segment_drawer]} locale={@locale} />
    <DawarichWeb.NativeAreaDialog.dialog dialog={assigns[:area_dialog]} locale={@locale} />
    <DawarichWeb.NativeMapReplay.panel id="native-map-replay" locale={@locale} opener={false} />
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

defmodule DawarichWeb.TripMapPanel do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.MapReplay, only: [replay_panel: 1]
  attr :page, :map, required: true
  attr :locale, :string, required: true

  def panel(assigns) do
    ~H"""
    <%= if @page.map_state == :path do %>
      <div class="w-full h-full rounded-lg overflow-hidden relative" data-trip-maplibre-target="map">
        <div
          data-trip-maplibre-target="loadingIndicator"
          class="absolute bottom-4 left-4 z-10 bg-base-100/80 backdrop-blur-sm rounded-lg px-3 py-2 flex items-center gap-2 hidden"
        >
          <span class="loading loading-spinner loading-sm"></span>
          <span class="text-sm">{t(@locale, "trips.show.loading_route_data", %{})}</span>
        </div>
        <.replay_panel locale={@locale} stimulus="trip-maplibre" show_day_nav />
      </div>
    <% else %>
      <%= if @page.map_state == :plan do %>
        <div class="relative h-full w-full overflow-hidden rounded-lg">
          <div
            class="h-full w-full"
            data-testid="trip-plan-map"
            data-controller="trip-maplibre-preview"
            data-trip-maplibre-preview-plan-value={@page.plan_json}
            data-trip-maplibre-preview-numbered-value="true"
            data-trip-maplibre-preview-interactive-value="true"
            data-trip-maplibre-preview-map-style-value={@page.settings.style}
          >
          </div>
          <p class="trip-plan-caption" role="status">
            <.icon name="map" class="size-4 shrink-0" />
            <span class="min-w-0">
              <span class="font-medium">{t(@locale, "trips.show.planned_route", %{})}</span>
              <span class="text-base-content/60"> · {t(
                @locale,
                if(@page.future_start,
                  do: "trips.show.trip_has_not_started_yet",
                  else: "trips.show.no_locations_recorded"
                ),
                %{}
              )}</span>
            </span>
          </p>
        </div>
      <% else %>
        <div class="flex items-center justify-center h-full rounded-lg bg-base-200 p-6">
          <div class="max-w-xs text-center" role="status">
            <%= case @page.map_state do %>
              <% :future -> %>
                <.icon name="calendar-clock" class="mx-auto mb-3 size-8 text-base-content/40" />
                <p class="text-base-content/60">
                  {t(@locale, "trips.show.trip_has_not_started_yet", %{})}
                </p>
              <% :empty -> %>
                <.icon name="route" class="mx-auto mb-3 size-8 text-base-content/40" />
                <p class="font-medium">{t(@locale, "trips.show.no_locations_recorded", %{})}</p>
                <p class="mt-1 text-sm text-base-content/60">
                  {t(@locale, "trips.show.no_locations_recorded_hint", %{})}
                </p>
              <% :calculating -> %>
                <p class="text-base-content/60">
                  {t(@locale, "trips.show.trip_path_is_being_calculated", %{})}
                </p>
                <div class="loading loading-spinner loading-lg mt-4"></div>
            <% end %>
          </div>
        </div>
      <% end %>
    <% end %>
    """
  end
end

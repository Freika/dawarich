defmodule DawarichWeb.TripCard do
  @moduledoc false
  use DawarichWeb, :html

  alias DawarichWeb.{LocalizedDate, TripFormat}

  attr :trip, :map, required: true
  attr :settings, :map, required: true
  attr :locale, :string, required: true

  def trip_card(assigns) do
    ~H"""
    <a href={"/trips/#{@trip.id}"} class="block group">
      <div
        class="border border-base-300 rounded-xl overflow-hidden transition-all duration-200 hover:border-primary/30 hover:-translate-y-1 hover:shadow-lg"
        data-trip-id={@trip.id}
        id={"trip-#{@trip.id}"}
      >
        <%= cond do %>
          <% @trip.path_json -> %>
            <div
              style="width: 100%; aspect-ratio: 16/10;"
              id={"map-#{@trip.id}"}
              class="bg-base-200"
              data-controller="trip-maplibre-preview"
              data-trip-maplibre-preview-path-value={@trip.path_json}
              data-trip-maplibre-preview-map-style-value={@settings.style}
              phx-hook="RailsStimulus"
              phx-update="ignore"
            >
            </div>
          <% @trip.plan_json -> %>
            <div style="width: 100%; aspect-ratio: 16/10;" class="relative bg-base-200">
              <div
                class="h-full w-full"
                data-controller="trip-maplibre-preview"
                data-trip-maplibre-preview-plan-value={@trip.plan_json}
                data-trip-maplibre-preview-map-style-value={@settings.style}
              >
              </div>
              <span class="trip-plan-caption trip-plan-caption--compact">{t(
                @locale,
                "trips.trip.plan",
                %{}
              )}</span>
            </div>
          <% @trip.distance -> %>
            <div
              style="width: 100%; aspect-ratio: 16/10;"
              class="flex items-center justify-center bg-base-200"
            >
              <p class="text-base-content/40 text-sm">
                {t(@locale, "trips.trip.no_points_found", %{})}
              </p>
            </div>
          <% true -> %>
            <div
              style="width: 100%; aspect-ratio: 16/10;"
              class="flex items-center justify-center bg-base-200"
            >
              <div class="text-center">
                <div class="loading loading-spinner loading-sm"></div>
                <p class="text-base-content/40 text-xs mt-1">
                  {t(@locale, "trips.trip.calculating", %{})}
                </p>
              </div>
            </div>
        <% end %>
        <div class="px-4 py-3">
          <h3 class="font-semibold text-base group-hover:text-primary transition-colors truncate">
            {@trip.name}
          </h3>
          <p class="text-xs text-base-content/50 mt-0.5">
            {LocalizedDate.l(@locale, @trip.started_on, "day_month_year")} {t(
              @locale,
              "trips.trip.ndash",
              %{}
            )} {LocalizedDate.l(@locale, @trip.ended_on, "day_month_year")}
          </p>
          <div class="flex items-center justify-between mt-3">
            <span class="text-sm font-medium tabular-nums">
              {TripFormat.distance(@trip.distance, @settings.factor)} {@settings.unit}
            </span>
            <div class="flex items-center gap-2">
              <span :if={@trip.countries > 0} class="text-xs text-base-content/50">
                {t(@locale, "trips.trip.country_count", %{count: @trip.countries})}
              </span>
              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-medium bg-primary/10 text-primary">
                {t(@locale, "trips.trip.day_count", %{count: @trip.day_count})}
              </span>
            </div>
          </div>
        </div>
      </div>
    </a>
    """
  end
end

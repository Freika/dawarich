defmodule DawarichWeb.TripsNative.Card do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1]

  alias DawarichWeb.{LocalizedDate, TripFormat}

  attr :trip, :map, required: true
  attr :settings, :map, required: true
  attr :locale, :string, required: true

  def card(assigns) do
    ~H"""
    <.link navigate={"/trips/#{@trip.id}"} class="block group">
      <div
        class="border border-base-300 rounded-xl overflow-hidden transition-all duration-200 hover:border-primary/30 hover:-translate-y-1 hover:shadow-lg"
        data-trip-id={@trip.id}
        id={"trip-#{@trip.id}"}
      >
        <div
          style="width: 100%; aspect-ratio: 16/10;"
          class="relative flex items-center justify-center bg-base-200"
          data-trip-preview={@trip.preview}
        >
          <%= case @trip.preview do %>
            <% :calculating -> %>
              <div class="text-center">
                <div class="loading loading-spinner loading-sm"></div>
                <p class="text-base-content/40 text-xs mt-1">
                  {t(@locale, "trips.trip.calculating", %{})}
                </p>
              </div>
            <% :no_points -> %>
              <p class="text-base-content/40 text-sm">
                {t(@locale, "trips.trip.no_points_found", %{})}
              </p>
            <% preview -> %>
              <.icon name="map" class="w-12 h-12 text-base-content/40" />
              <span :if={preview == :plan} class="trip-plan-caption trip-plan-caption--compact">
                {t(@locale, "trips.trip.plan", %{})}
              </span>
          <% end %>
        </div>
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
          <div class="flex flex-wrap items-center justify-between gap-2 mt-3">
            <span class="text-sm font-medium tabular-nums">
              {TripFormat.distance(@trip.distance, @settings.factor)} {@settings.unit}
            </span>
            <div class="flex flex-wrap items-center gap-2 min-w-0">
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
    </.link>
    """
  end

  attr :trip, :map, required: true
  attr :locale, :string, required: true

  def family_card(assigns) do
    ~H"""
    <a href={"/s/#{@trip.share_id}"} class="block group">
      <div
        class="border border-base-300 rounded-xl overflow-hidden transition-all duration-200 hover:border-primary/30 hover:shadow-lg"
        data-testid="family-trip-card"
      >
        <div
          style="width: 100%; aspect-ratio: 16/10;"
          class="flex items-center justify-center bg-base-200"
        >
          <.icon name="map" class="w-12 h-12 text-base-content/40" />
        </div>
        <div class="px-4 py-3">
          <h3 class="font-semibold text-base group-hover:text-primary truncate">{@trip.name}</h3>
          <p class="text-xs text-base-content/50 mt-0.5">
            {LocalizedDate.l(@locale, @trip.started_on, "day_month_year")} {t(
              @locale,
              "trips.trip.ndash",
              %{}
            )} {LocalizedDate.l(@locale, @trip.ended_on, "day_month_year")}
          </p>
          <span class="badge badge-success badge-sm mt-3">
            {t(@locale, "shared_links.family.label", %{})}
          </span>
        </div>
      </div>
    </a>
    """
  end
end

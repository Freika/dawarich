defmodule DawarichWeb.NativeTripContent do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{LocalizedDate, LocalizedTime, TripFormat}
  attr :page, :map, required: true
  attr :locale, :string, required: true

  attr :selected_day, :string, default: nil

  attr :note_editor, :map, default: nil

  attr :expanded_days, :boolean, default: false

  attr :plan_enabled, :boolean, default: false

  def content(assigns) do
    ~H"""
    <section id="native-trip-summary" class="min-w-0 max-w-full">
      <h1 class="text-3xl font-bold [overflow-wrap:anywhere]">{@page.name}</h1>
      <DawarichWeb.TripParts.countries page={@page} locale={@locale} />
      <p :if={@page.description} class="prose max-w-full [overflow-wrap:anywhere]">
        {Phoenix.HTML.raw(Dawarich.TripDescription.html(@page.description))}
      </p>
      <DawarichWeb.NativeTripItinerary.itinerary
        :if={DawarichWeb.TripPlanItems.visible?(@page.plan)}
        plan={@page.plan}
        notes={@page.day_notes}
        plan_on_map={@plan_enabled}
        locale={@locale}
        now={@page.now}
      />
      <div class="space-y-1">
        <details
          :for={day <- @page.days}
          id={"native-trip-day-#{day.date}"}
          open={@expanded_days || @selected_day == Date.to_iso8601(day.date)}
          class="collapse collapse-arrow bg-base-200 min-w-0"
        >
          <summary class="collapse-title flex flex-wrap items-center gap-2 text-sm min-w-0">
            <button
              type="button"
              phx-click="trip:day"
              phx-value-day={Date.to_iso8601(day.date)}
              aria-pressed={to_string(@selected_day == Date.to_iso8601(day.date))}
              class="btn btn-sm btn-ghost h-auto whitespace-normal"
            >
              {LocalizedDate.l(@locale, day.date, "short_month_day_weekday")}
            </button>
            <span class="sr-only">{LocalizedDate.l(@locale, day.date, "short_month_day_weekday")}</span>
            <span :if={day.stats}>
              {LocalizedTime.l(@locale, day.stats.first, "hour_minute")} – {LocalizedTime.l(
                @locale,
                day.stats.last,
                "hour_minute"
              )}
              {TripFormat.day_distance(@locale, day.stats.distance_m, @page.settings.factor)} {@page.settings.unit}
            </span>
            <span :if={!day.stats}>{t(@locale, "trips.show.no_data", %{})}</span>
          </summary>
          <div class="collapse-content min-w-0">
            <DawarichWeb.NativeTripNote.note day={day} editor={@note_editor} locale={@locale} />
            <div :if={day.photos != []} class="grid grid-cols-3 gap-2">
              <img
                :for={photo <- day.photos}
                src={photo.url}
                alt=""
                loading="lazy"
                class="w-full object-cover rounded-lg"
              />
            </div>
          </div>
        </details>
      </div>
      <div class="flex flex-wrap gap-2">
        <a
          :for={source <- @page.photos.sources}
          href={@page.photos.links[source]}
          target="_blank"
          rel="noopener"
          class="btn btn-sm btn-outline h-auto whitespace-normal"
        >
          {t(@locale, "trips.show.more_on_source", %{
            source: t(@locale, "photo_sources.#{source}", %{})
          })}
        </a>
        <a href="/trips" class="btn btn-sm btn-ghost">{t(@locale, "trips.show.back_to_trips", %{})}</a>
      </div>
    </section>
    """
  end
end

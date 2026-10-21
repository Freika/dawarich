defmodule DawarichWeb.NativeTripContent do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{Icon, LocalizedDate, LocalizedTime, TripFormat}
  attr :page, :map, required: true
  attr :locale, :string, required: true

  attr :selected_day, :string, default: nil

  attr :note_editor, :map, default: nil

  attr :expanded_days, :boolean, default: false

  attr :plan_enabled, :boolean, default: false

  def content(assigns) do
    ~H"""
    <section id="native-trip-summary" class="contents">
      <DawarichWeb.NativeTripItinerary.itinerary
        :if={DawarichWeb.TripPlanItems.visible?(@page.plan)}
        plan={@page.plan}
        notes={@page.day_notes}
        plan_on_map={@plan_enabled}
        locale={@locale}
        now={@page.now}
      />
      <div class="space-y-1 mb-6">
        <details
          :for={day <- @page.days}
          id={"native-trip-day-#{day.date}"}
          data-day-key={Date.to_iso8601(day.date)}
          open={@expanded_days || @selected_day == Date.to_iso8601(day.date)}
          class="collapse collapse-arrow bg-base-200 rounded-lg"
        >
          <summary
            class="collapse-title flex flex-wrap items-center gap-2 text-sm font-medium min-h-0 cursor-pointer"
            phx-click="trip:day"
            phx-value-day={Date.to_iso8601(day.date)}
          >
            <span
              class="inline-block w-3 h-3 rounded-full flex-shrink-0 bg-base-content/30"
              data-day-dot={Date.to_iso8601(day.date)}
            ></span>
            <span>{LocalizedDate.l(@locale, day.date, "short_month_day_weekday")}</span>
            <%= if day.stats do %>
              <span class="text-base-content/50 text-xs">{LocalizedTime.l(
                @locale,
                day.stats.first,
                "hour_minute"
              )} – {LocalizedTime.l(@locale, day.stats.last, "hour_minute")}</span>
              <span class="text-base-content/50 ml-auto mr-6 text-xs">{t(
                @locale,
                "trips.show.middot",
                %{}
              )} {TripFormat.day_distance(@locale, day.stats.distance_m, @page.settings.factor)} {@page.settings.unit}</span>
            <% else %>
              <span class="text-base-content/50 ml-auto mr-6 text-xs">{t(
                @locale,
                "trips.show.no_data",
                %{}
              )}</span>
            <% end %>
          </summary>
          <div class="collapse-content">
            <DawarichWeb.NativeTripNote.note
              day={day}
              trip_id={@page.id}
              editor={@note_editor}
              locale={@locale}
            />
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
      <div :if={@page.description} class="mb-6">
        <h3 class="text-lg font-semibold mb-2">{t(@locale, "trips.show.trip_notes", %{})}</h3>
        <div class="prose max-w-none [overflow-wrap:anywhere]">
          {Phoenix.HTML.raw(
            @page[:description_html] || Dawarich.TripDescription.html(@page.description)
          )}
        </div>
      </div>
      <div :if={@page.photos.sources != []} class="mb-6">
        <div class="flex flex-wrap gap-2">
          <a
            :for={source <- @page.photos.sources}
            href={@page.photos.links[source]}
            target="_blank"
            rel="noopener"
            class="btn btn-sm btn-outline gap-1"
          ><Icon.icon name="camera" class="w-4 h-4" /> {t(@locale, "trips.show.more_on_source", %{
            source: t(@locale, "photo_sources.#{source}", %{})
          })}</a>
        </div>
      </div>
      <div class="mb-6">
        <a href="/trips" class="btn btn-sm btn-ghost gap-1"><Icon.icon
          name="arrow-left"
          class="w-4 h-4"
        /> {t(@locale, "trips.show.back_to_trips", %{})}</a>
      </div>
    </section>
    """
  end
end

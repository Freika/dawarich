defmodule DawarichWeb.TripsNative.ShowParts do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1]

  alias DawarichWeb.{HumanDatetime, LocalizedDate, LocalizedTime, MapParts, TripFormat}
  alias Phoenix.LiveView.JS

  attr :trip, :map, required: true
  attr :locale, :string, required: true

  def header(assigns) do
    ~H"""
    <div class="mb-6">
      <div class="flex flex-wrap items-start justify-between gap-3 mb-1">
        <h1 class="text-3xl font-bold leading-tight min-w-0 [overflow-wrap:anywhere]">
          {@trip.name}
        </h1>
        <div class="flex flex-wrap items-center gap-1 shrink-0" data-testid="trip-header-actions">
          <a
            href={"/map/v2?" <> DawarichWeb.Params.to_query(%{"start_at" => HumanDatetime.iso8601(@trip.started_at), "end_at" => HumanDatetime.iso8601(@trip.ended_at)})}
            class="btn btn-sm btn-ghost"
            title={s(@locale, "open_in_map")}
            aria-label={s(@locale, "open_in_map")}
          ><.icon name="map" class="w-4 h-4" /></a>
          <div class="dropdown dropdown-end">
            <div
              tabindex="0"
              role="button"
              class="btn btn-sm btn-ghost"
              aria-label={s(@locale, "download_trip")}
            >
              <.icon name="download" class="w-4 h-4" />
            </div>
            <ul
              tabindex="0"
              class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-44 z-10"
            >
              <li>
                <button type="button" phx-click="export" phx-value-format="gpx">{s(@locale, "gpx")}</button>
              </li>
              <li>
                <button type="button" phx-click="export" phx-value-format="json">{s(
                  @locale,
                  "geojson"
                )}</button>
              </li>
            </ul>
          </div>
          <.link
            class="btn btn-sm btn-ghost"
            navigate={"/trips/#{@trip.id}/edit"}
            aria-label={s(@locale, "edit_trip")}
          >
            <.icon name="square-pen" class="w-4 h-4" />
          </.link>
          <span
            :if={@trip.shared}
            class="badge badge-success badge-xs"
            aria-label={s(@locale, "currently_shared")}
          >
            {s(@locale, "public")}
          </span>
          <button
            type="button"
            class="btn btn-sm btn-ghost text-error"
            phx-click="delete"
            data-confirm={s(@locale, "delete_this_trip_this_cannot_be_undone")}
            aria-label={s(@locale, "delete_trip")}
          >
            <.icon name="trash-2" class="w-4 h-4" />
          </button>
        </div>
      </div>
      <p class="text-md text-base-content/60 mb-4">
        {date(@locale, @trip.started_at)} {s(@locale, "ndash")} {date(@locale, @trip.ended_at)}
      </p>
      <DawarichWeb.TripParts.countries page={@trip} locale={@locale} />
    </div>
    """
  end

  attr :recalculating, :boolean, required: true
  attr :locale, :string, required: true

  def recalculate(assigns) do
    ~H"""
    <div class="mb-4">
      <button :if={@recalculating} class="btn btn-outline btn-sm" disabled>
        <span class="loading loading-spinner loading-xs"></span> {r(@locale, "recalculating_hellip")}
      </button>
      <button
        :if={!@recalculating}
        type="button"
        class="btn btn-outline btn-sm"
        phx-click="recalculate"
        data-confirm={r(@locale, "recalculate_this_trip_s_path_distance_and_countries_from_your")}
      >
        <.icon name="refresh-ccw" class="w-4 h-4" /> {r(@locale, "recalculate")}
      </button>
    </div>
    """
  end

  attr :trip, :map, required: true
  attr :days, :list, required: true
  attr :status, :atom, required: true
  attr :previous, :any, default: nil
  attr :next, :any, default: nil
  attr :locale, :string, required: true
  slot :note

  def days(assigns) do
    ~H"""
    <section class="mb-6" data-days-status={@status} aria-busy={@status == :loading && "true"}>
      <div :if={@status == :loading} class="flex justify-center py-4">
        <span class="loading loading-spinner loading-sm"></span>
      </div>
      <div :if={@status == :failed} role="alert" class="alert alert-error flex flex-wrap gap-2">
        <span class="min-w-0">{t(@locale, "controllers.application.admin_action_failed", %{})}</span>
        <button type="button" class="btn btn-sm" phx-click="retry_days">
          {t(@locale, "trips.recalculate_button.recalculate", %{})}
        </button>
      </div>
      <div class="space-y-1">
        <details
          :for={day <- @days}
          class="collapse collapse-arrow bg-base-200 rounded-lg"
          data-day-key={Date.to_iso8601(day.date)}
          phx-mounted={JS.ignore_attributes("open")}
        >
          <summary class="collapse-title flex flex-wrap items-center gap-2 text-sm font-medium min-h-0 cursor-pointer">
            <span class="min-w-0">{LocalizedDate.l(@locale, day.date, "short_month_day_weekday")}</span>
            <%= if day.stats do %>
              <span class="text-base-content/50 text-xs">
                {LocalizedTime.l(@locale, day.stats.first, "hour_minute")} – {LocalizedTime.l(
                  @locale,
                  day.stats.last,
                  "hour_minute"
                )}
              </span>
              <span class="text-base-content/50 ml-auto mr-6 text-xs">
                {t(@locale, "trips.show.middot", %{})}
                {TripFormat.day_distance(@locale, day.stats.distance_m, @trip.settings.factor)} {@trip.settings.unit}
              </span>
            <% else %>
              <span class="text-base-content/50 ml-auto mr-6 text-xs">{t(
                @locale,
                "trips.show.no_data",
                %{}
              )}</span>
            <% end %>
          </summary>
          <div class="collapse-content">{render_slot(@note, day)}</div>
        </details>
      </div>
      <nav :if={@previous || @next} class="flex flex-wrap justify-between gap-2 mt-2">
        <.link
          :if={@previous}
          patch={"/trips/#{@trip.id}?from=#{@previous}"}
          class="btn btn-sm btn-ghost"
          rel="prev"
        >
          {t(@locale, "kaminari.prev_page.laquo", %{})}
        </.link>
        <.link
          :if={@next}
          patch={"/trips/#{@trip.id}?from=#{@next}"}
          class="btn btn-sm btn-ghost ml-auto"
          rel="next"
        >
          {t(@locale, "kaminari.next_page.raquo", %{})}
        </.link>
      </nav>
    </section>
    """
  end

  attr :trip, :map, required: true
  attr :html, :string, default: nil
  attr :locale, :string, required: true

  def description(assigns) do
    ~H"""
    <div :if={@trip.description} class="mb-6">
      <h3 class="text-lg font-semibold mb-2">{t(@locale, "trips.show.trip_notes", %{})}</h3>
      <div
        id={"trip-description-#{@trip.id}-#{@trip.description}"}
        phx-update="ignore"
        class="prose max-w-none [overflow-wrap:anywhere]"
      >
        {@html && Phoenix.HTML.raw(@html)}
      </div>
    </div>
    """
  end

  defp date(locale, at), do: MapParts.human_date(locale, NaiveDateTime.to_date(at.local))
  defp s(locale, key), do: t(locale, "trips.show." <> key, %{})
  defp r(locale, key), do: t(locale, "trips.recalculate_button." <> key, %{})
end

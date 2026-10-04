defmodule DawarichWeb.TripParts do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1, country_flag: 1]

  alias DawarichWeb.{MapParts, TripFormat}

  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :rails_csrf_token, :string, required: true

  def trip_header(assigns) do
    ~H"""
    <div class="mb-6">
      <div class="flex items-start justify-between gap-3 mb-1">
        <h1 class="text-3xl font-bold leading-tight">{@page.name}</h1>
        <div class="flex items-center gap-1 shrink-0" data-testid="trip-header-actions">
          <div class="dropdown dropdown-end">
            <label tabindex="0" class="btn btn-sm btn-ghost" title={s(@locale, "download_trip")}>
              <.icon name="download" class="w-4 h-4" />
            </label>
            <ul
              tabindex="0"
              class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-44 z-10"
            >
              <li>
                <a data-turbo-method="post" href={"/trips/#{@page.id}/export?file_format=gpx"}>{s(
                  @locale,
                  "gpx"
                )}</a>
              </li>
              <li>
                <a data-turbo-method="post" href={"/trips/#{@page.id}/export?file_format=json"}>{s(
                  @locale,
                  "geojson"
                )}</a>
              </li>
            </ul>
          </div>
          <button
            type="button"
            class="btn btn-sm btn-ghost"
            data-trip-maplibre-target="posterBtn"
            data-action="click->trip-maplibre#openPosterStudio"
            aria-label={s(@locale, "create_poster")}
            title={s(@locale, if(@page.has_path, do: "create_poster", else: "poster_unavailable"))}
            disabled={!@page.has_path}
          >
            <.icon name="image" class="w-4 h-4" />
          </button>
          <button
            type="button"
            class="btn btn-sm btn-ghost"
            data-action="click->trip-maplibre#openVideoStudio"
            aria-label={s(@locale, "create_video")}
            title={s(@locale, if(@page.has_path, do: "create_video", else: "video_unavailable"))}
            disabled={!@page.has_path}
          >
            <.icon name="video" class="w-4 h-4" />
          </button>
          <a
            class="btn btn-sm btn-ghost"
            title={s(@locale, "edit_trip")}
            href={"/trips/#{@page.id}/edit"}
          >
            <.icon name="square-pen" class="w-4 h-4" />
          </a>
          <a
            class="btn btn-sm btn-ghost relative"
            title={s(@locale, "share_trip")}
            data-turbo-frame="share-link-modal"
            href={"/trips/#{@page.id}/share_link/new"}
          >
            <.icon name="share" class="w-4 h-4" />
            <span
              :if={@page.shared}
              class="badge badge-success badge-xs"
              aria-label={s(@locale, "currently_shared")}
            >{s(@locale, "public")}</span>
          </a>
          <form
            class="button_to"
            method="post"
            action={"/trips/#{@page.id}"}
            data-turbo-confirm={s(@locale, "delete_this_trip_this_cannot_be_undone")}
          >
            <input type="hidden" name="_method" value="delete" />
            <button
              class="btn btn-sm btn-ghost text-error"
              title={s(@locale, "delete_trip")}
              type="submit"
            >
              <.icon name="trash-2" class="w-4 h-4" />
            </button>
            <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
          </form>
        </div>
      </div>
      <p class="text-md text-base-content/60 mb-4">
        {human_date(@locale, @page.started_at)} {s(@locale, "ndash")} {human_date(
          @locale,
          @page.ended_at
        )}
      </p>
      <.countries page={@page} locale={@locale} />
    </div>
    """
  end

  attr :page, :map, required: true
  attr :locale, :string, required: true

  def countries(assigns) do
    ~H"""
    <div class="mb-4">
      <p class="text-base-content/60 text-sm">
        {TripFormat.distance(@page.distance, @page.settings.factor)} {@page.settings.unit}
        {t(@locale, "trips.countries.middot", %{})}
        {TripFormat.duration(@locale, @page.duration)}
        {t(@locale, "trips.countries.middot", %{})}
        <%= if @page.countries != [] do %>
          {t(@locale, "trips.countries.country_count", %{count: length(@page.countries)})}
        <% else %>
          <span class="text-base-content/40">{Phoenix.HTML.raw(
            t(@locale, "trips.countries.mdash", %{})
          )}</span>
        <% end %>
      </p>
      <div :if={@page.countries != []} class="flex flex-wrap items-center gap-1.5 mt-2">
        <.country_flag :for={country <- @page.countries} name={country} table={@page.flags} />
      </div>
    </div>
    """
  end

  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :rails_csrf_token, :string, required: true

  def trip_toolbar(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2 mb-4">
      <button
        :if={@page.settings.airtrail}
        type="button"
        class="btn btn-sm btn-outline gap-1"
        data-trip-maplibre-target="flightsToggleBtn"
        data-action="click->trip-maplibre#toggleFlights"
        title={s(@locale, "toggle_airtrail_flights_on_map")}
      >
        <.icon name="plane" class="w-4 h-4" />
        <span class="hidden sm:inline">{s(@locale, "flights")}</span>
      </button>
      <button
        :if={@page.plan_toggle}
        type="button"
        class="btn btn-sm btn-outline gap-1"
        data-testid="trip-plan-toggle"
        data-trip-maplibre-target="planToggleBtn"
        data-action="click->trip-maplibre#togglePlan"
        aria-pressed="false"
        title={s(@locale, "toggle_plan_on_map")}
      >
        <.icon name="map" class="w-4 h-4" />
        <span class="hidden sm:inline">{s(@locale, "plan")}</span>
      </button>
      <button
        type="button"
        class="btn btn-sm btn-outline gap-1"
        data-trip-maplibre-target="replayToggleBtn"
        data-action="click->trip-maplibre#toggleReplay"
        title={s(@locale, "replay_the_trip")}
      >
        <.icon name="play" class="w-4 h-4" />
        <span class="hidden sm:inline">{s(@locale, "replay")}</span>
      </button>
      <button
        type="button"
        class="btn btn-sm btn-outline gap-1"
        data-trip-maplibre-target="expandAllBtn"
        data-action="click->trip-maplibre#expandAllDays"
      >
        <.icon name="chevron-down" class="w-4 h-4" />
        <span class="hidden sm:inline">{s(@locale, "show_all_days")}</span>
      </button>
      <.recalculate_button
        trip_id={@page.id}
        recalculating={@page.recalculating}
        error={false}
        locale={@locale}
        rails_csrf_token={@rails_csrf_token}
      />
    </div>
    """
  end

  attr :trip_id, :integer, required: true
  attr :recalculating, :boolean, required: true
  attr :error, :boolean, required: true
  attr :locale, :string, required: true
  attr :rails_csrf_token, :string, default: nil

  def recalculate_button(assigns) do
    ~H"""
    <turbo-frame id="trip_recalculate_frame">
      <%= if @recalculating do %>
        <button class="btn btn-outline btn-sm" disabled>
          <span class="loading loading-spinner loading-xs"></span> {r(
            @locale,
            "recalculating_hellip"
          )}
        </button>
      <% else %>
        <form
          class="button_to"
          method="post"
          action={"/trips/#{@trip_id}/recalculate"}
          data-turbo-confirm={
            r(@locale, "recalculate_this_trip_s_path_distance_and_countries_from_your")
          }
        >
          <button class="btn btn-outline btn-sm" type="submit">
            <.icon name="refresh-ccw" class="w-4 h-4" /> {r(@locale, "recalculate")}
          </button>
          <input
            :if={@rails_csrf_token}
            type="hidden"
            name="authenticity_token"
            value={@rails_csrf_token}
          />
        </form>
        <span :if={@error} class="text-error text-xs ml-2">
          {r(@locale, "recalculation_failed_try_again")}
        </span>
      <% end %>
    </turbo-frame>
    """
  end

  defp human_date(locale, at), do: MapParts.human_date(locale, NaiveDateTime.to_date(at.local))

  defp s(locale, key), do: t(locale, "trips.show." <> key, %{})
  defp r(locale, key), do: t(locale, "trips.recalculate_button." <> key, %{})
end

defmodule DawarichWeb.TripsLive.Show do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.PosterStudio, only: [poster_studio: 1]
  import DawarichWeb.TripDaysList, only: [trip_days: 1]
  import DawarichWeb.TripParts, only: [trip_header: 1, trip_toolbar: 1]
  import DawarichWeb.VideoStudio, only: [video_studio: 1]

  alias Dawarich.{TripDescription, TripPage}
  alias DawarichWeb.{HumanDatetime, MapParts}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    with {trip_id, ""} <- Integer.parse(id),
         {:ok, page} <- TripPage.load(socket.assigns.current_user, trip_id, socket.assigns.now),
         {:ok, _} <-
           Dawarich.Trips.ShowCalculation.run(
             Dawarich.Repo,
             socket.assigns.current_user,
             trip_id,
             %{now: socket.assigns.now, connected: connected?(socket)}
           ) do
      title = page.name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

      title =
        if connected?(socket),
          do: DawarichWeb.Layouts.page_title(socket.assigns.locale, title),
          else: title

      {:ok,
       assign(socket,
         page: page,
         page_title: title,
         rails_js: true,
         rails_charts: false,
         morph_page_refreshes: false
       ), temporary_assigns: [page: nil]}
    else
      _ -> {:ok, redirect(socket, to: "/trips/" <> URI.encode_www_form(id))}
    end
  end

  @impl true
  def handle_event("rails_flash", params, socket),
    do: {:noreply, DawarichWeb.RailsWidgets.rails_flash(socket, params)}

  @impl true
  def render(assigns) do
    ~H"""
    <div id="trip-shell" class="contents" phx-hook="MapShell" phx-update="ignore" data-turbo="true">
      <turbo-cable-stream-source
        channel="Turbo::StreamsChannel"
        signed-stream-name={@page.trip_stream}
      >
      </turbo-cable-stream-source>
      <div
        class="container mx-auto px-4 my-5"
        data-controller="trip-maplibre"
        data-trip-maplibre-api-key-value={@page.api_key}
        data-trip-maplibre-timezone-value={@page.iana}
        data-trip-maplibre-started-at-value={HumanDatetime.iso8601(@page.started_at)}
        data-trip-maplibre-ended-at-value={HumanDatetime.iso8601(@page.ended_at)}
        data-trip-maplibre-trip-id-value={@page.id}
        data-trip-maplibre-trip-name-value={@page.name}
        data-trip-maplibre-meters-between-routes-value={@page.settings.meters}
        data-trip-maplibre-minutes-between-routes-value={@page.settings.minutes}
        data-trip-maplibre-path-data-value={@page.path_json}
        data-trip-maplibre-device-windows-value={@page.windows_json}
        data-trip-maplibre-map-style-value={@page.settings.style}
      >
        <div class="flex flex-col lg:flex-row gap-6 lg:h-[calc(100dvh-9.75rem)]">
          <div class="w-full lg:w-3/5 h-[50vh] lg:h-full shrink-0">
            <DawarichWeb.TripMapPanel.panel page={@page} locale={@locale} />
          </div>
          <div class="w-full lg:w-2/5 lg:h-full lg:overflow-y-auto">
            <.trip_header page={@page} locale={@locale} rails_csrf_token={@rails_csrf_token} />
            <turbo-frame id="share-link-modal"></turbo-frame>
            <.trip_toolbar page={@page} locale={@locale} rails_csrf_token={@rails_csrf_token} />
            <DawarichWeb.TripItinerary.itinerary
              :if={DawarichWeb.TripPlanItems.visible?(@page.plan)}
              plan={@page.plan}
              notes={@page.day_notes}
              plan_on_map={@page.plan_on_map}
              locale={@locale}
              now={@page.now}
            />
            <.trip_days page={@page} locale={@locale} rails_csrf_token={@rails_csrf_token} />
            <div :if={@page.description} class="mb-6">
              <h3 class="text-lg font-semibold mb-2">{t(@locale, "trips.show.trip_notes", %{})}</h3>
              <div class="prose max-w-none">
                {Phoenix.HTML.raw(TripDescription.html(@page.description))}
              </div>
            </div>
            <div class="mb-6">
              <a href="/trips" class="btn btn-sm btn-ghost gap-1"><.icon
                name="arrow-left"
                class="w-4 h-4"
              /> {t(@locale, "trips.show.back_to_trips", %{})}</a>
            </div>
          </div>
        </div>
      </div>
      <.poster_studio
        page={@page.studio}
        locale={@locale}
        rails_csrf_token={@rails_csrf_token}
        date_range_label={range(@locale, @page)}
      />
      <.video_studio page={@page.studio} locale={@locale} base_url={@base_url} />
    </div>
    """
  end

  defp range(locale, page),
    do: "#{human_date(locale, page.started_at)} – #{human_date(locale, page.ended_at)}"

  defp human_date(locale, at), do: MapParts.human_date(locale, NaiveDateTime.to_date(at.local))
end

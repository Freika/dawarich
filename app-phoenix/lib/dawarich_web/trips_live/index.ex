defmodule DawarichWeb.TripsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.ListParts, only: [page_header: 1]
  import DawarichWeb.Paginator, only: [paginator: 1]
  import DawarichWeb.TripCard, only: [trip_card: 1]

  alias Dawarich.TripList
  alias DawarichWeb.TripsGate

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: t(socket.assigns.locale, "trips.index.trips", %{}),
       rails_js: true,
       rails_charts: false
     ), temporary_assigns: [entries: []]}
  end

  @impl true
  def handle_params(params, uri, socket) do
    %URI{path: path, query: query} = URI.parse(uri)

    with page when is_binary(page) or is_nil(page) <- params["page"],
         number = TripsGate.page_number(page),
         family_page when is_binary(family_page) or is_nil(family_page) <- params["family_page"],
         family_number = TripsGate.page_number(family_page),
         {:ok, result} <- TripList.load(socket.assigns.current_user, number) do
      family =
        Dawarich.SharedLinks.FamilyAudience.trips(
          socket.assigns.current_user,
          family_number,
          DateTime.utc_now()
        )

      result =
        Map.merge(result, %{
          family_entries: family.entries,
          family_total_pages: family.total_pages,
          family_page: family_number
        })

      {:noreply,
       socket |> assign(page: number, query: URI.decode_query(query || "")) |> assign(result)}
    else
      _ -> {:noreply, redirect(socket, to: if(query, do: path <> "?" <> query, else: path))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full my-5">
      <div id="trips" class="min-w-full">
        <.page_header title={t(@locale, "trips.index.trips", %{})}>
          <a href="/trips/new" class="btn btn-primary btn-sm"><.icon
            name="circle-plus"
            class="w-4 h-4"
          /> {t(@locale, "trips.index.new_trip", %{})}</a>
        </.page_header>
        <%= if @entries == [] do %>
          <div class="text-center py-16 px-8 bg-base-200 rounded-xl border-2 border-dashed border-base-300">
            <h3 class="text-xl font-bold mb-3">{t(@locale, "trips.index.no_trips_yet", %{})}</h3>
            <p class="text-base-content/50 mb-6 max-w-sm mx-auto">
              {t(
                @locale,
                "trips.index.create_your_first_trip_to_see_your_journeys_visualized_with",
                %{}
              )}
            </p>
            <a href="/trips/new" class="btn btn-primary"><.icon name="circle-plus" class="w-4 h-4" /> {t(
              @locale,
              "trips.index.create_your_first_trip",
              %{}
            )}</a>
          </div>
        <% else %>
          <div class="flex justify-center mb-4">
            <.paginator
              locale={@locale}
              path="/trips"
              query={@query}
              page={@page}
              total_pages={@total_pages}
            />
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <.trip_card :for={trip <- @entries} trip={trip} settings={@settings} locale={@locale} />
          </div>
          <div class="flex justify-center mt-4">
            <.paginator
              locale={@locale}
              path="/trips"
              query={@query}
              page={@page}
              total_pages={@total_pages}
            />
          </div>
        <% end %>
        <section
          :if={@family_entries != []}
          class="mt-8"
          aria-label={t(@locale, "shared_links.family.trips", %{})}
        >
          <h2 class="text-xl font-bold mb-4">{t(@locale, "shared_links.family.trips", %{})}</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <a :for={trip <- @family_entries} href={"/s/#{trip.share_id}"} class="block group">
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
                  <h3 class="font-semibold text-base group-hover:text-primary truncate">
                    {trip.name}
                  </h3><p class="text-xs text-base-content/50 mt-0.5">
                    {DawarichWeb.LocalizedDate.l(@locale, trip.started_on, "day_month_year")} {t(
                      @locale,
                      "trips.trip.ndash",
                      %{}
                    )} {DawarichWeb.LocalizedDate.l(@locale, trip.ended_on, "day_month_year")}
                  </p><span class="badge badge-success badge-sm mt-3">{t(
                    @locale,
                    "shared_links.family.label",
                    %{}
                  )}</span>
                </div>
              </div>
            </a>
          </div>
          <div class="flex justify-center mt-4">
            <.paginator
              locale={@locale}
              path="/trips"
              query={@query}
              page={@family_page}
              total_pages={@family_total_pages}
              param_name="family_page"
            />
          </div>
        </section>
      </div>
    </div>
    """
  end
end

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
         {:ok, result} <- TripList.load(socket.assigns.current_user, number) do
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
      </div>
    </div>
    """
  end
end

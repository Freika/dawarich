defmodule DawarichWeb.NativeTripsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.ListParts, only: [page_header: 1]
  import DawarichWeb.Paginator, only: [paginator: 1]
  import DawarichWeb.TripsNative.Card, only: [card: 1, family_card: 1]

  alias Dawarich.Trips.Pages
  alias DawarichWeb.TripsNative.Access

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: t(socket.assigns.locale, "trips.index.trips", %{}),
       status: :ready,
       entries: [],
       family_entries: [],
       total_pages: 0,
       family_total_pages: 0,
       page: 1,
       family_page: 1,
       query: %{},
       settings: %{unit: "km", factor: 1000}
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    with {:ok, scope} <- Access.scope(socket),
         {:ok, result} <- Pages.list(scope, params, DateTime.utc_now()) do
      {:noreply,
       assign(socket,
         status: :ready,
         entries: result.entries,
         family_entries: result.family_entries,
         total_pages: result.total_pages,
         family_total_pages: result.family_total_pages,
         page: result.query.page,
         family_page: result.query.family_page,
         query: query(result.query),
         settings: result.settings
       )}
    else
      {:error, :stale_session} -> {:noreply, Access.refuse(socket)}
      _ -> {:noreply, assign(socket, status: :unavailable, entries: [], family_entries: [])}
    end
  end

  defp query(%{page: page, family_page: family}) do
    for {key, value} <- [{"page", page}, {"family_page", family}],
        value > 1,
        into: %{},
        do: {key, Integer.to_string(value)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full my-5">
      <div id="trips" class="min-w-full">
        <.page_header title={t(@locale, "trips.index.trips", %{})}>
          <.link navigate="/trips/new" class="btn btn-primary btn-sm">
            <.icon name="circle-plus" class="w-4 h-4" /> {t(@locale, "trips.index.new_trip", %{})}
          </.link>
        </.page_header>
        <div :if={@status == :unavailable} role="alert" class="alert alert-error mb-4">
          {t(@locale, "controllers.application.admin_action_failed", %{})}
        </div>
        <div
          :if={@status == :ready and @entries == []}
          class="text-center py-16 px-8 bg-base-200 rounded-xl border-2 border-dashed border-base-300"
        >
          <h3 class="text-xl font-bold mb-3">{t(@locale, "trips.index.no_trips_yet", %{})}</h3>
          <p class="text-base-content/50 mb-6 max-w-sm mx-auto">
            {t(
              @locale,
              "trips.index.create_your_first_trip_to_see_your_journeys_visualized_with",
              %{}
            )}
          </p>
          <.link navigate="/trips/new" class="btn btn-primary">
            <.icon name="circle-plus" class="w-4 h-4" /> {t(
              @locale,
              "trips.index.create_your_first_trip",
              %{}
            )}
          </.link>
        </div>
        <div :if={@entries != []}>
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
            <.card :for={trip <- @entries} trip={trip} settings={@settings} locale={@locale} />
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
        </div>
        <section
          :if={@family_entries != []}
          class="mt-8"
          aria-label={t(@locale, "shared_links.family.trips", %{})}
        >
          <h2 class="text-xl font-bold mb-4">{t(@locale, "shared_links.family.trips", %{})}</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <.family_card :for={trip <- @family_entries} trip={trip} locale={@locale} />
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

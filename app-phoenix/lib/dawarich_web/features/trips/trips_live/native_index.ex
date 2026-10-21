defmodule DawarichWeb.TripsLive.NativeIndex do
  @moduledoc false
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.MapLiveAuth, :default}
  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.ListParts, only: [page_header: 1]
  import DawarichWeb.Paginator, only: [paginator: 1]
  import DawarichWeb.NativeTripCard, only: [trip_card: 1]
  alias Dawarich.Trips.{IndexQuery, Pages}

  @impl true
  def mount(_, _, socket) do
    socket =
      assign(socket,
        entries: [],
        family_entries: [],
        total_pages: 0,
        family_total_pages: 0,
        family_page: 1,
        query: %{},
        filters: Pages.normalize(%{}),
        filter_form: to_form(%{}, as: "filters"),
        filter_options: %{years: [], countries: []},
        filtered: false,
        has_trips: false,
        settings: nil
      )

    socket =
      if socket.assigns.current_scope, do: DawarichWeb.NativeMapChrome.load(socket), else: socket

    {:ok,
     assign(socket,
       body_class: "min-h-screen flex flex-col",
       viewport: "width=device-width,initial-scale=1"
     ), layout: false}
  end

  @impl true
  def handle_params(params, uri, socket) do
    with true <- valid_page?(params["page"]) and valid_page?(params["family_page"]),
         page = DawarichWeb.TripsGate.page_number(params["page"]),
         family_page = DawarichWeb.TripsGate.page_number(params["family_page"]),
         {:ok, result} <-
           Dawarich.Maps.Trip.list(socket.assigns.current_scope, page, family_page,
             filters: params
           ) do
      {:noreply,
       socket
       |> assign(result)
       |> assign(
         page: page,
         family_page: family_page,
         query:
           Map.merge(
             URI.decode_query(URI.parse(uri).query || "") |> Map.take(~w(locale view)),
             query(result.query)
           ),
         has_trips: result.options.years != [],
         filters: result.query,
         filter_form: to_form(query(result.query), as: "filters"),
         filter_options: result.options,
         filtered: IndexQuery.active?(result.query),
         map_error: nil,
         page_title: t(socket.assigns.locale, "trips.index.trips", %{})
       )}
    else
      _ ->
        {:noreply,
         assign(socket,
           entries: [],
           family_entries: [],
           page: nil,
           page_title: nil,
           map_error: :unavailable
         )}
    end
  end

  defp valid_page?(page) when is_binary(page) or is_nil(page),
    do: DawarichWeb.TripsGate.page_number(page) <= 1_000_000_000_000

  defp valid_page?(_), do: false

  @impl true
  def handle_event("trips:filter", filters, socket) when is_map(filters) do
    if Enum.all?(filters, fn {key, value} ->
         key in ~w(q sort year month country) and is_binary(value)
       end) do
      with {:ok, _scope} <- Dawarich.Maps.admit(socket.assigns.current_scope) do
        normalized = Pages.normalize(Map.put(filters, "family_page", socket.assigns.family_page))
        query = URI.encode_query(query(normalized))

        {:noreply,
         push_patch(socket, to: "/trips" <> if(query == "", do: "", else: "?" <> query))}
      else
        _ -> {:noreply, DawarichWeb.MapLiveAuth.refuse(socket, :unauthorized)}
      end
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         t(socket.assigns.locale, "controllers.application.admin_action_failed", %{})
       )}
    end
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp query(query) do
    query
    |> Enum.reject(fn {key, value} ->
      value in [nil, ""] or (key in [:page, :family_page] and value == 1) or
        (key == :sort and value == "newest")
    end)
    |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :inner_content, content(assigns))

    ~H"""
    <DawarichWeb.Layouts.app :if={@current_scope && !@map_error} {assigns} />
    <p :if={@map_error} data-native-trip-index-refused role="alert">
      {t(@locale, "controllers.api.v1.settings.something_went_wrong", %{})}
    </p>
    """
  end

  defp content(assigns) do
    ~H"""
    <main id="native-trips-index" class="contents">
      <div class="w-full my-5">
        <div id="trips" class="min-w-full">
          <.page_header title={t(@locale, "trips.index.trips", %{})}>
            <a href="/trips/new" class="btn btn-primary btn-sm"><.icon
              name="circle-plus"
              class="w-4 h-4"
            /> {t(@locale, "trips.index.new_trip", %{})}</a>
          </.page_header>
          <DawarichWeb.TripsNative.Filters.filters
            :if={@has_trips}
            locale={@locale}
            form={@filter_form}
            options={@filter_options}
            query={@filters}
          />
          <div
            :if={@entries == [] and @has_trips}
            data-testid="trips-no-matches"
            class="text-center py-12 px-8 bg-base-200 rounded-xl border border-base-300"
          >
            <h3 class="text-lg font-bold mb-2">{t(@locale, "trips.index.no_matching_trips", %{})}</h3>
            <p class="text-base-content/50 mb-5 max-w-sm mx-auto">
              {t(@locale, "trips.index.try_other_filters", %{})}
            </p>
            <.link patch="/trips" class="btn btn-sm">{t(@locale, "trips.index.show_all_trips", %{})}</.link>
          </div>
          <%= if !@has_trips do %>
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
          <% end %>
          <%= if @entries != [] do %>
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
                    <h3 class="font-semibold text-base group-hover:text-primary [overflow-wrap:anywhere]">
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
    </main>
    """
  end
end

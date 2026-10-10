defmodule DawarichWeb.PlacesLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.HumanDatetime, only: [human_datetime: 1]
  import DawarichWeb.Paginator, only: [paginator: 1]

  alias Dawarich.PlaceList
  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat
  alias DawarichWeb.TripsGate

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: t(socket.assigns.locale, "places.index.places", %{}))}

  @impl true
  def handle_params(params, uri, socket) do
    %URI{path: path, query: query} = URI.parse(uri)

    with page when is_binary(page) or is_nil(page) <- params["page"],
         {:ok, result} <- PlaceList.load(socket.assigns.current_user, page) do
      {:noreply,
       socket
       |> assign(
         page: TripsGate.page_number(page),
         delete_query: delete_query(page),
         query: URI.decode_query(query || "")
       )
       |> assign(result)}
    else
      _ -> {:noreply, redirect(socket, to: if(query, do: path <> "?" <> query, else: path))}
    end
  end

  defp delete_query(nil), do: ""
  defp delete_query(page), do: "?" <> URI.encode_query(%{"page" => page})

  defp coordinates(place), do: RubyFloat.to_s(place.lat) <> ", " <> RubyFloat.to_s(place.lon)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full my-5">
      <div class="overflow-x-auto pb-1">
        <div role="tablist" class="tabs tabs-lifted tabs-lg inline-flex min-w-max flex-nowrap">
          <a
            role="tab"
            class="tab font-bold text-xl"
            href="/map/v2?panel=timeline&date=today&status=confirmed"
          >{t(@locale, "places.index.timeline", %{})}</a>
          <a role="tab" class="tab font-bold text-xl tab-active" href="/places">{t(
            @locale,
            "places.index.places",
            %{}
          )}</a>
        </div>
      </div>

      <div id="places" class="min-w-full">
        <%= if @entries == [] do %>
          <div class="hero min-h-80 bg-base-200">
            <div class="hero-content text-center">
              <div class="max-w-md">
                <h1 class="text-5xl font-bold">{t(@locale, "places.index.hello_there", %{})}</h1>
                <p class="py-6">
                  {t(
                    @locale,
                    "places.index.here_you_ll_find_your_places_created_by_visits_suggestion",
                    %{}
                  )}
                </p>
              </div>
            </div>
          </div>
        <% else %>
          <div class="flex justify-center my-5">
            <.paginator
              locale={@locale}
              path="/places"
              query={@query}
              page={@page}
              total_pages={@total_pages}
            />
          </div>
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>{t(@locale, "places.index.name", %{})}</th>
                  <th>{t(@locale, "places.index.created_at", %{})}</th>
                  <th>{t(@locale, "places.index.coordinates", %{})}</th>
                  <th>{t(@locale, "places.index.actions", %{})}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={place <- @entries}>
                  <td>{place.name}</td>
                  <td><.human_datetime locale={@locale} at={place.created} /></td>
                  <td>{coordinates(place)}</td>
                  <td>
                    <a
                      data-turbo-confirm={
                        t(
                          @locale,
                          "places.index.are_you_sure_deleting_a_place_will_result_in_deleting",
                          %{}
                        )
                      }
                      data-turbo-method="delete"
                      class="px-4 py-2 bg-red-500 text-white rounded-md"
                      href={"/places/#{place.id}" <> @delete_query}
                    >{t(@locale, "places.index.delete", %{})}</a>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end

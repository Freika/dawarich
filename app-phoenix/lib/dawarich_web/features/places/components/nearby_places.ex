defmodule DawarichWeb.NearbyPlaces do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat

  def empty(assigns), do: render(assign(assigns, :places, []))

  def render(assigns) do
    next = min(assigns.radius + 0.5, 1.5)

    query = [
      {"latitude", assigns.params["latitude"]},
      {"limit", "5"},
      {"longitude", assigns.params["longitude"]},
      {"radius", RubyFloat.to_s(next)}
    ]

    assigns =
      assign(assigns,
        next_radius: next,
        href: "/places/nearby?" <> URI.encode_query(query),
        native: assigns[:native] == true
      )

    ~H"""
    <turbo-frame :if={!@native} id="nearby-places">
      <.list
        places={@places}
        locale={@locale}
        radius={@radius}
        next_radius={@next_radius}
        href={@href}
        native={false}
      />
    </turbo-frame>
    <.list
      :if={@native}
      places={@places}
      locale={@locale}
      radius={@radius}
      next_radius={@next_radius}
      href={@href}
      native
    />
    """
  end

  defp list(assigns) do
    ~H"""
    <div class="space-y-2 max-h-48 overflow-y-auto">
      <p :if={@places == []} class="text-sm text-gray-500">
        {t(@locale, "places.nearby_places.no_nearby_places_found", %{})}
      </p>
      <div
        :for={{place, index} <- Enum.with_index(@places)}
        class="card card-compact bg-base-200 cursor-pointer hover:bg-base-300 transition"
        data-action={!@native && "click->place-creation#selectNearby"}
        phx-click={@native && "place:nearby_pick"}
        phx-value-index={@native && index}
        data-place-name={place["name"]}
        data-place-latitude={place["latitude"]}
        data-place-longitude={place["longitude"]}
      >
        <div class="card-body">
          <div class="flex gap-2">
            <span class="badge badge-primary badge-sm">#{index + 1}</span>
            <div class="flex-1">
              <h4 class="font-semibold">{place["name"]}</h4>
              <p :if={Dawarich.Ingest.Ruby.present?(place["street"])} class="text-sm">
                {place["street"]}
              </p>
              <p :if={Dawarich.Ingest.Ruby.present?(place["city"])} class="text-xs text-gray-500">
                {place["city"]}{if Dawarich.Ingest.Ruby.present?(place["country"]),
                  do: ", " <> place["country"]}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    <div :if={@radius < 1.5} class="mt-2 text-center">
      <a
        data-turbo-frame={!@native && "nearby-places"}
        class="btn btn-sm btn-ghost"
        href={if @native, do: "#", else: @href}
        phx-click={@native && "place:nearby"}
        phx-value-radius={@native && @next_radius}
      >{t(
        @locale,
        "places.nearby_places.load_more_search_up_to_distance_m",
        %{distance: Dawarich.RubyFloat.round(@next_radius * 1000)}
      )}</a>
    </div>
    """
  end
end

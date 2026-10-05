defmodule DawarichWeb.NearbyPlaces do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat

  def empty(assigns) do
    next = min(assigns.radius + 0.5, 1.5)

    query = [
      {"latitude", assigns.params["latitude"]},
      {"limit", "5"},
      {"longitude", assigns.params["longitude"]},
      {"radius", RubyFloat.to_s(next)}
    ]

    assigns =
      assign(assigns, next_radius: next, href: "/places/nearby?" <> URI.encode_query(query))

    ~H"""
    <turbo-frame id="nearby-places">
      <div class="space-y-2 max-h-48 overflow-y-auto">
        <p class="text-sm text-gray-500">
          {t(@locale, "places.nearby_places.no_nearby_places_found", %{})}
        </p>
      </div>
      <div :if={@radius < 1.5} class="mt-2 text-center">
        <a data-turbo-frame="nearby-places" class="btn btn-sm btn-ghost" href={@href}>{t(
          @locale,
          "places.nearby_places.load_more_search_up_to_distance_m",
          %{distance: Dawarich.RubyFloat.round(@next_radius * 1000)}
        )}</a>
      </div>
    </turbo-frame>
    """
  end
end

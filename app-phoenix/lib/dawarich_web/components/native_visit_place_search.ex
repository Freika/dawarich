defmodule DawarichWeb.NativeVisitPlaceSearch do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias Phoenix.LiveView.JS

  @move_threshold 100

  attr :search, :map, default: nil
  attr :locale, :string, required: true

  def search(assigns) do
    search = assigns.search || %{query: "", results: nil, error: nil}
    results = search.results || %{}
    places = results["places"] || []
    query = search.query || ""

    assigns =
      assign(assigns,
        query: query,
        error: search.error,
        places: Enum.with_index(places),
        areas: Enum.with_index(results["areas"] || []),
        loaded: not is_nil(search.results),
        create:
          String.length(query) >= 2 and
            not Enum.any?(places, &(String.downcase(&1["name"] || "") == String.downcase(query)))
      )

    ~H"""
    <section class="mt-4 min-w-0">
      <form
        id="native-visit-place-search"
        phx-change="visit:place_search"
        phx-submit="visit:place_search"
      >
        <input
          type="search"
          name="q"
          value={@query}
          phx-debounce="300"
          class="input input-sm input-bordered w-full"
          placeholder={j(@locale, "places.search_placeholder")}
          aria-label={j(@locale, "places.search_placeholder")}
        />
      </form>
      <p :if={@error} class="text-error text-sm mt-1" role="alert">
        {t(@locale, "controllers.api.v1.settings.something_went_wrong", %{})}
      </p>
      <ul
        :if={@loaded}
        id="native-visit-place-results"
        class="menu menu-sm bg-base-200 rounded-box mt-2"
      >
        <li :for={{area, index} <- @areas}>
          <button
            type="button"
            data-pick={"area-#{index}"}
            phx-click={JS.push("visit:place_pick", value: %{kind: "area", index: index})}
          >
            <span class="badge badge-xs badge-secondary">{j(@locale, "map_info.area")}</span>
            <span class="[overflow-wrap:anywhere]">{area["name"]}</span>
          </button>
        </li>
        <li :for={{place, index} <- @places}>
          <button
            type="button"
            data-pick={"place-#{index}"}
            data-confirm={move(@locale, place["distance_m"])}
            phx-click={JS.push("visit:place_pick", value: %{kind: "place", index: index})}
          >
            <span class="[overflow-wrap:anywhere]">{place["name"]}</span>
          </button>
        </li>
        <li :if={@create}>
          <button
            type="button"
            data-pick="create-0"
            phx-click={JS.push("visit:place_pick", value: %{kind: "create", index: 0})}
          >
            <span class="[overflow-wrap:anywhere]">{j(@locale, "places.create_here", %{name: @query})}</span>
          </button>
        </li>
        <li
          :if={@areas == [] and @places == [] and not @create}
          class="text-xs text-base-content/60 px-3 py-2"
        >
          {j(@locale, "places.none_found")}
        </li>
      </ul>
    </section>
    """
  end

  defp move(locale, meters) when is_integer(meters) and meters > @move_threshold,
    do: j(locale, "places.confirm_move_visit", %{distance: meters})

  defp move(_locale, _meters), do: nil

  defp j(locale, key, bindings \\ %{}), do: t(locale, "javascript." <> key, bindings)
end

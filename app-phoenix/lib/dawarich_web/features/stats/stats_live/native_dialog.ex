defmodule DawarichWeb.StatsLive.NativeDialog do
  @moduledoc false
  use DawarichWeb, :html
  attr :dialog, :any, required: true
  attr :data, :map, required: true
  attr :locale, :string, required: true

  attr :path, :string, default: "/stats"
  attr :query, :map, default: %{}

  def render(assigns) do
    ~H"""
    <section
      id="stats-dialog"
      role="dialog"
      aria-modal="true"
      aria-labelledby="stats-dialog-title"
      class="fixed inset-0 z-50 bg-base-100 p-6 overflow-y-auto min-w-0"
      phx-window-keydown="close_dialog"
      phx-key="Escape"
      phx-mounted={Phoenix.LiveView.JS.focus(to: "#stats-dialog-close")}
    >
      <h2 id="stats-dialog-title" class="text-xl break-words">
        {t(@locale, "stats.index.statistics", %{})}
      </h2>
      <button id="stats-dialog-close" class="btn" phx-click="close_dialog">{t(
        @locale,
        "stats.reverse_geocoding_stats.close",
        %{}
      )}</button>
      <DawarichWeb.StatsLive.NativeYearCard.places
        :if={match?({:year_places, _}, @dialog)}
        data={@data}
        year={elem(@dialog, 1)}
        locale={@locale}
      />
      <ul :if={@dialog in ~w(countries cities)}>
        <li
          :for={
            value <-
              if(@dialog == "countries", do: @data.countries_visited, else: @data.cities_visited)
          }
          class="[overflow-wrap:anywhere]"
          phx-no-format
        >{value}</li>
      </ul>
      <nav
        :if={@dialog in ~w(countries cities)}
        aria-label={t(@locale, "stats.index.statistics", %{})}
        class="flex flex-wrap gap-2"
      >
        <.link
          :if={@data.places_page > 1}
          patch={places_path(@data, @dialog, -1, @path, @query)}
          class="btn"
        >{t(
          @locale,
          "views.pagination.previous",
          %{}
        )}</.link>
        <.link
          :if={@data.places_more}
          patch={places_path(@data, @dialog, 1, @path, @query)}
          class="btn"
        >{t(
          @locale,
          "views.pagination.next",
          %{}
        )}</.link>
      </nav>
      <form
        :if={@dialog == :share || is_map(@dialog)}
        id="stats-sharing"
        phx-submit="share"
        class="flex flex-wrap gap-3 min-w-0"
      >
        <input type="hidden" name="enabled" value="0" />
        <label for="stats-sharing-enabled">{t(
          @locale,
          "shared.sharing_modal.enable_public_access",
          %{}
        )}</label>
        <input
          type="checkbox"
          id="stats-sharing-enabled"
          name="enabled"
          value="1"
          checked={is_map(@dialog) && @dialog.enabled}
        />
        <label for="stats-sharing-expiration">{t(@locale, "shared.sharing_modal.link_expiration", %{})}</label><select
          id="stats-sharing-expiration"
          name="expiration"
        ><option
          :for={value <- ~w(1h 12h 24h)}
          value={value}
          selected={is_map(@dialog) && @dialog.expiration == value}
        >
          {value}
        </option></select>
        <button class="btn btn-primary whitespace-normal" type="submit">{t(
          @locale,
          "helpers.submit.submit",
          %{}
        )}</button>
        <a
          :if={is_map(@dialog) && @dialog.url != ""}
          id="stats-sharing-url"
          href={@dialog.url}
          class="[overflow-wrap:anywhere]"
        >{@dialog.url}</a>
      </form>
    </section>
    """
  end

  defp places_path(data, kind, direction, path, query),
    do:
      path <>
        "?" <>
        URI.encode_query(
          Map.merge(query, %{
            "page" => data.page,
            "places_page" => data.places_page + direction,
            "places_kind" => kind
          })
        )
end

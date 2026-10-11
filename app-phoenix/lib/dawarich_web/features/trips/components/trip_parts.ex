defmodule DawarichWeb.TripParts do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1, country_flag: 1]

  alias DawarichWeb.TripFormat

  attr :page, :map, required: true
  attr :locale, :string, required: true

  def countries(assigns) do
    ~H"""
    <div class="mb-4">
      <p class="text-base-content/60 text-sm">
        {TripFormat.distance(@page.distance, @page.settings.factor)} {@page.settings.unit}
        {t(@locale, "trips.countries.middot", %{})}
        {TripFormat.duration(@locale, @page.duration)}
        {t(@locale, "trips.countries.middot", %{})}
        <%= if @page.countries != [] do %>
          {t(@locale, "trips.countries.country_count", %{count: length(@page.countries)})}
        <% else %>
          <span class="text-base-content/40">{Phoenix.HTML.raw(
            t(@locale, "trips.countries.mdash", %{})
          )}</span>
        <% end %>
      </p>
      <div :if={@page.countries != []} class="flex flex-wrap items-center gap-1.5 mt-2">
        <.country_flag :for={country <- @page.countries} name={country} table={@page.flags} />
      </div>
    </div>
    """
  end

  attr :trip_id, :integer, required: true
  attr :recalculating, :boolean, required: true
  attr :error, :boolean, required: true
  attr :locale, :string, required: true
  attr :rails_csrf_token, :string, default: nil

  def recalculate_button(assigns) do
    ~H"""
    <turbo-frame id="trip_recalculate_frame">
      <%= if @recalculating do %>
        <button class="btn btn-outline btn-sm" disabled>
          <span class="loading loading-spinner loading-xs"></span> {r(
            @locale,
            "recalculating_hellip"
          )}
        </button>
      <% else %>
        <form
          class="button_to"
          method="post"
          action={"/trips/#{@trip_id}/recalculate"}
          data-turbo-confirm={
            r(@locale, "recalculate_this_trip_s_path_distance_and_countries_from_your")
          }
        >
          <button class="btn btn-outline btn-sm" type="submit">
            <.icon name="refresh-ccw" class="w-4 h-4" /> {r(@locale, "recalculate")}
          </button>
          <input
            :if={@rails_csrf_token}
            type="hidden"
            name="authenticity_token"
            value={@rails_csrf_token}
          />
        </form>
        <span :if={@error} class="text-error text-xs ml-2">
          {r(@locale, "recalculation_failed_try_again")}
        </span>
      <% end %>
    </turbo-frame>
    """
  end

  defp r(locale, key), do: t(locale, "trips.recalculate_button." <> key, %{})
end

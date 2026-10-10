defmodule DawarichWeb.StatsLive.NativeMonthParts do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{StatsFormat, NumberFormat}
  alias Dawarich.Stats.Toponyms
  attr :data, :map, required: true
  attr :locale, :string, required: true

  def summary(assigns) do
    ~H"""
    <%= if @data.data.stat do %>
      <section class="grid grid-cols-1 md:grid-cols-2 gap-4 min-w-0 my-4">
        <div class="min-w-0">
          <h2 class="break-words">{t(@locale, "stats.month.distance_traveled", %{})}</h2>
          <p id="stats-month-distance">
            ~{StatsFormat.distance(@locale, @data.data.stat.distance, @data.unit)}
          </p>
          <p id="stats-month-average">
            {StatsFormat.than_average(@locale, @data.data.stat.distance, @data.data.average_km)}
          </p>
        </div>
        <div :if={(@data.data.stat.flight_distance || 0) > 0} class="min-w-0">
          <h2>{t(@locale, "stats.month.flight_distance", %{})}</h2>
          <p>{StatsFormat.distance(@locale, @data.data.stat.flight_distance, @data.unit)}</p>
          <p class="break-words">
            {t(@locale, "stats.month.from_airtrail_not_counted_in_distance", %{})}
          </p>
        </div>
        <div>
          <h2>{t(@locale, "stats.month.active_days", %{})}</h2>
          <p id="stats-month-active-days">{StatsFormat.active_days(@data.data.stat.daily)}</p>
          <p>
            {StatsFormat.than_previous_active_days(
              @locale,
              @data.data.stat.daily,
              @data.data.previous
            )}
          </p>
        </div>
        <div>
          <h2>{t(@locale, "stats.month.countries_visited", %{})}</h2>
          <p>{NumberFormat.delimited(@locale, length(Toponyms.visited(@data.data.stat.toponyms)))}</p>
          <p>
            {StatsFormat.than_previous_countries(
              @locale,
              @data.data.stat.toponyms,
              @data.data.previous
            )}
          </p>
        </div>
      </section>
      <p>
        {t(@locale, "stats.month.quietest_week", %{})} {StatsFormat.quietest_week(
          @locale,
          @data.year,
          @data.month,
          @data.data.stat.daily
        )}
      </p>
      <details class="min-w-0 my-4">
        <summary class="break-words">{t(@locale, "stats.month.countries_cities", %{})}</summary>
        <section :for={place <- Toponyms.visited(@data.data.stat.toponyms)} class="min-w-0">
          <h3 class="[overflow-wrap:anywhere]">{place["country"]}</h3>
          <p class="[overflow-wrap:anywhere]">{Enum.map_join(place["cities"], ", ", & &1["city"])}</p>
        </section>
      </details>
      <.link href={"/stats/#{@data.year}"} class="btn whitespace-normal">{t(
        @locale,
        "stats.month.back_to",
        %{}
      )} {@data.year}</.link>
    <% else %>
      <p role="status" class="alert break-words min-w-0">
        {t(@locale, "stats.month.no_location_data_available_for_this_month", %{})}
      </p>
    <% end %>
    """
  end
end

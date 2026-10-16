defmodule DawarichWeb.InsightsLive.NativeConsolidated do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.Analytics.Period
  alias DawarichWeb.{LocalizedDate, NumberFormat, StatsFormat}
  attr :data, :map, required: true
  attr :locale, :string, required: true

  def render(assigns) do
    assigns = assign(assigns, :content, assigns.data.consolidated)

    ~H"""
    <%= if @data.all_time do %>
      <section id="insights-tracking" class="my-4 min-w-0">
        <p>{@content.index.points.total} {t(@locale, "stats.index.geopoints_tracked", %{})}</p>
        <p :if={@content.index.points.state == :pending} role="status" id="stats-count-pending">
          {t(@locale, "javascript.common.loading", %{})}
        </p>
        <p :if={@content.index.points.state == :ready} id="stats-count-ready">
          {@content.index.points.geocoded} / {@content.index.points.total} ({@content.index.points.percentage}%)
        </p>
        <p :if={(@content.index.points[:without_data] || 0) > 0}>
          {@content.index.points.without_data} {t(
            @locale,
            "stats.reverse_geocoding_stats.points_without_data",
            %{}
          )}
        </p>
        <button phx-click="open_places" phx-value-kind="countries" class="btn">{t(
          @locale,
          "stats.reverse_geocoding_stats.countries_visited",
          %{}
        )}: {@content.index.total_countries}</button>
        <button phx-click="open_places" phx-value-kind="cities" class="btn">{t(
          @locale,
          "stats.reverse_geocoding_stats.cities_visited",
          %{}
        )}: {@content.index.total_cities}</button>
        <.link navigate="/digests">{t(@locale, "stats.index.year_end_digests", %{})}</.link>
      </section>
      <section
        aria-label={t(@locale, "insights.year_cards.title", %{})}
        class="grid md:grid-cols-2 gap-4"
      >
        <article
          :for={year <- @content.index.years}
          data-testid="insights-year-card"
          class="rounded border p-4 min-w-0"
        >
          <.link patch={"/insights?year=#{year.year}"} class="text-xl underline">{year.year}</.link>
          <div
            :if={year.year in @content.map_years}
            id={"insights-year-map-#{year.year}"}
            data-testid="insights-year-map"
            phx-hook="InsightsYearMap"
            data-url={"/insights/routes/#{year.year}"}
            data-style={@data.consolidated.style}
            class="w-full h-48"
            phx-update="ignore"
          >
          </div>
          <p>
            {NumberFormat.delimited(@locale, Period.rounded(Enum.sum(year.distances), @data.unit))} {@data.unit}
          </p>
          <p>{t(@locale, "stats.index.last_update", %{})} {year.updated_on}</p>
          <.link href={StatsFormat.year_map_path(year.year)}>{t(@locale, "shared.navbar.map", %{})}</.link>
          <details>
            <summary>
              {t(@locale, "stats.index.countries_count_countries_cities_count_cities", %{
                countries_count: year.places.countries_count,
                cities_count: year.places.cities_count
              })}
            </summary>
            <div :for={{country, cities} <- year.places.grouped}>
              <h3>{country}</h3><p>{Enum.join(cities, ", ")}</p><p :if={cities == []}>
                {t(@locale, "stats.index.no_specific_cities_recorded", %{})}
              </p>
            </div>
          </details>
          <div
            data-testid="insights-year-strip"
            class="flex gap-1"
            role="img"
            aria-label={t(@locale, "insights.months.title", %{})}
          >
            <span
              :for={{meters, month} <- Enum.with_index(year.distances, 1)}
              title={LocalizedDate.month_name(@locale,year.year,month) <> ": #{Period.rounded(meters,@data.unit)} #{@data.unit}"}
              class={"flex-1 h-2 rounded #{if meters > 0, do: "bg-primary", else: "bg-base-300"}"}
            ></span>
          </div>
        </article>
        <p :for={year <- @content.index.locked_years} data-testid="insights-locked-year">
          {year} — {t(@locale, "stats.locked_year_card.available_on_pro", %{})}
        </p>
      </section>
      <nav class="flex gap-2">
        <.link
          :if={@content.index.page > 1}
          patch={"/insights?year=all&page=#{@content.index.page-1}"}
        >{t(@locale, "views.pagination.previous", %{})}</.link>
        <.link :if={@content.index.more} patch={"/insights?year=all&page=#{@content.index.page+1}"}>{t(
          @locale,
          "views.pagination.next",
          %{}
        )}</.link>
      </nav>
    <% else %>
      <nav class="flex gap-3 my-3">
        <.link href={StatsFormat.year_map_path(@data.year)}>{t(@locale, "shared.navbar.map", %{})}</.link>
        <.link navigate={"/digests/#{@data.year}"}>{t(@locale, "stats.index.year_end_digests", %{})}</.link>
      </nav>
      <section
        class="grid grid-cols-2 md:grid-cols-4 gap-3"
        aria-label={t(@locale, "insights.months.title", %{})}
      >
        <article
          :for={month <- @content.months}
          data-testid="insights-month"
          data-empty={to_string(month.empty)}
          class="rounded border p-3 min-w-0"
        >
          <span :if={month.locked}>{LocalizedDate.month_name(@locale, @data.year, month.month)} — {t(
            @locale,
            "stats.locked_year_card.available_on_pro",
            %{}
          )}</span>
          <.link :if={!month.locked} navigate={"/stats/#{@data.year}/#{month.month}"}>{LocalizedDate.month_name(
            @locale,
            @data.year,
            month.month
          )}</.link>
          <p :if={!month.locked && !month.empty}>
            {Period.rounded(month.distance, @data.unit)} {@data.unit}
          </p>
          <p :if={!month.locked && month.empty}>
            {t(@locale, "insights.stats_row.no_stats_data_available", %{})}
          </p>
        </article>
      </section>
      <DawarichWeb.InsightsLive.NativeRace.render
        :if={@content.race}
        race={@content.race}
        unit={@data.unit}
        locale={@locale}
        today={@data.period.today}
      />
      <p :if={@data.restricted && @content.prior} data-testid="distance-race-locked">
        {t(@locale, "insights.distance_race.title", %{year: @data.year, previous: @data.year - 1})} — {t(
          @locale,
          "stats.locked_year_card.available_on_pro",
          %{}
        )}
      </p>
    <% end %>
    """
  end
end

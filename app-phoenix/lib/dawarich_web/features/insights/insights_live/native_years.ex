defmodule DawarichWeb.InsightsLive.NativeYears do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.Analytics.Period
  alias DawarichWeb.{LocalizedDate, NumberFormat, StatsFormat}
  attr :data, :map, required: true
  attr :locale, :string, required: true

  def render(assigns) do
    assigns = assign(assigns, :content, assigns.data.consolidated)

    ~H"""
    <section
      :if={@content.index.years != [] || @content.index.locked_years != []}
      class="mb-6"
      aria-labelledby="insights-years-title"
    >
      <h2 id="insights-years-title" class="text-xl font-bold mb-3">
        {t(@locale, "insights.year_cards.title", %{})}
      </h2>
      <div class={"grid grid-cols-1 gap-4 #{if length(@content.index.years) + length(@content.index.locked_years) > 1, do: "lg:grid-cols-2"}"}>
        <div
          :for={year <- @content.index.years}
          class="card bg-base-200 overflow-hidden"
          data-testid="insights-year-card"
        >
          <.link
            :if={year.year in @content.map_years}
            patch={"/insights?year=#{year.year}"}
            class="block bg-base-300"
            tabindex="-1"
            aria-hidden="true"
            data-map-wrapper="true"
          >
            <div
              class="pointer-events-none aspect-[16/7] max-h-72 w-full"
              data-testid="insights-year-map"
              id={"native-insights-year-map-#{year.year}"}
              phx-hook="InsightsYearMap"
              data-url={"/insights/routes/#{year.year}"}
              data-style={@content.style}
              phx-update="ignore"
            >
            </div>
          </.link>
          <div class="card-body p-5 gap-3">
            <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
              <h3 class="text-2xl font-bold">
                <.link
                  patch={"/insights?year=#{year.year}"}
                  class={"link link-hover text-#{StatsFormat.header_color(year.year)}"}
                >{year.year}</.link>
              </h3>
              <span class="text-lg font-semibold tabular-nums">{NumberFormat.delimited(
                @locale,
                Period.rounded(Enum.sum(year.distances), @data.unit)
              )} {@data.unit}</span>
            </div>
            <div class="flex flex-wrap items-center justify-between gap-2 text-sm text-base-content/60">
              <span>{t(@locale, "stats.index.last_update", %{})} {LocalizedDate.l(
                @locale,
                year.updated_on,
                "day_month_year"
              )}</span>
              <span class="flex items-center gap-3">
                <a href={StatsFormat.year_map_path(year.year)} class="link link-hover">{t(
                  @locale,
                  "shared.navbar.map",
                  %{}
                )}</a>
                <label
                  :if={@content.geocoding}
                  for={year.places.modal_id}
                  class="link link-primary cursor-pointer"
                >{t(@locale, "stats.index.countries_count_countries_cities_count_cities", %{
                  countries_count: year.places.countries_count,
                  cities_count: year.places.cities_count
                })}</label>
              </span>
            </div>
            <div
              class="flex h-1.5 gap-0.5"
              role="img"
              aria-label={t(@locale, "insights.months.title", %{})}
              data-testid="insights-year-strip"
            >
              <span
                :for={{meters, month} <- Enum.with_index(year.distances, 1)}
                class="flex-1 rounded-full"
                title={LocalizedDate.month_name(@locale, year.year, month) <> ": #{NumberFormat.delimited(@locale, Period.rounded(meters, @data.unit))} #{@data.unit}"}
                style={"background: color-mix(in oklab, oklch(var(--p)) #{shade(meters, year.distances)}%, oklch(var(--bc) / 0.1))"}
              ></span>
            </div>
            <.places :if={@content.geocoding} year={year} locale={@locale} />
          </div>
        </div>
        <div :for={year <- @content.index.locked_years} data-testid="insights-year-card">
          <DawarichWeb.InsightsLive.NativeLockedYear.render
            year={year}
            locale={@locale}
            unit={@data.unit}
          />
        </div>
      </div>
    </section>
    <nav :if={@content.index.page > 1 || @content.index.more} class="flex gap-2">
      <.link
        :if={@content.index.page > 1}
        patch={"/insights?year=all&page=#{@content.index.page - 1}"}
      >{t(@locale, "views.pagination.previous", %{})}</.link>
      <.link :if={@content.index.more} patch={"/insights?year=all&page=#{@content.index.page + 1}"}>{t(
        @locale,
        "views.pagination.next",
        %{}
      )}</.link>
    </nav>
    """
  end

  defp shade(0, _), do: 0
  defp shade(meters, distances), do: round(20 + meters / Enum.max(distances) * 80)

  defp places(assigns) do
    ~H"""
    <input
      type="checkbox"
      id={@year.places.modal_id}
      class="modal-toggle"
      aria-label={t(@locale, "stats.index.countries_and_cities_visited_in", %{}) <> " #{@year.year}"}
      phx-mounted={Phoenix.LiveView.JS.ignore_attributes("checked")}
    />
    <div class="modal" role="dialog">
      <div class="modal-box max-w-3xl">
        <h3 class="text-lg font-bold mb-4">
          {t(@locale, "stats.index.countries_and_cities_visited_in", %{})} {@year.year}
        </h3>
        <div class="max-h-96 overflow-y-auto">
          <div :for={{country, cities} <- @year.places.grouped} class="mb-4">
            <h4 class="font-bold">
              <span class="mr-2"><DawarichWeb.NativeDigestFlag.flag name={country} id={"native-insights-year-#{@year.year}-" <> Base.url_encode64(country, padding: false)} table={Dawarich.CountryNames.table()} /></span>{country}
            </h4>
            <div :if={cities != []} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2 pl-4">
              <div :for={city <- cities} class="text-sm">{city}</div>
            </div>
            <p :if={cities == []} class="text-sm text-base-content/50 italic pl-4">
              {t(@locale, "stats.index.no_specific_cities_recorded", %{})}
            </p>
          </div>
        </div>
      </div>
      <label class="modal-backdrop" for={@year.places.modal_id}></label>
    </div>
    """
  end
end

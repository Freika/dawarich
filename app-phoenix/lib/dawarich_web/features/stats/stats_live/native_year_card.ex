defmodule DawarichWeb.StatsLive.NativeYearCard do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{NativeChart, NumberFormat, StatsFormat}
  alias Dawarich.Analytics.Period
  attr :year, :map, required: true
  attr :locale, :string, required: true
  attr :unit, :string, required: true
  attr :chart, :list, required: true
  attr :revision, :string, required: true

  def render(assigns) do
    assigns = assign(assigns, :places, assigns.year.places)

    ~H"""
    <article class="my-4 min-w-0 rounded-lg border p-4">
      <.link navigate={"/stats/#{@year.year}"} class="text-xl underline">{@year.year}</.link>
      <a id={"stats-year-#{@year.year}-map"} href={StatsFormat.year_map_path(@year.year)}>{t(
        @locale,
        "stats.index.map",
        %{}
      )}</a>
      <p>{@year.updated_on}</p>
      <p id={"stats-year-total-#{@year.year}"}>
        {NumberFormat.delimited(@locale, Period.rounded(Enum.sum(@year.distances), @unit))} {@unit}
      </p>
      <button
        id={"stats-year-#{@year.year}-places"}
        phx-click="open_year_places"
        phx-value-year={@year.year}
        class="btn whitespace-normal"
      >{t(@locale, "stats.index.countries_count_countries_cities_count_cities", %{
        countries_count: @places.countries_count,
        cities_count: @places.cities_count
      })}</button>
      <NativeChart.chart
        id={"stats-year-#{@year.year}"}
        data={@chart}
        revision={@revision}
        label={t(@locale, "stats.year.distance", %{})}
        options={%{suffix: " " <> @unit}}
      />
    </article>
    """
  end

  attr :data, :map, required: true
  attr :year, :integer, required: true
  attr :locale, :string, required: true

  def places(assigns) do
    year = Enum.find(assigns.data.years, &(&1.year == assigns.year))

    assigns = assign(assigns, :places, year.places)

    ~H"""
    <div data-year-places={@year} class="min-w-0">
      <h3>{t(@locale, "stats.index.countries_and_cities_visited_in", %{})} {@year}</h3>
      <section :for={{country, cities} <- @places.grouped} class="min-w-0">
        <h4 class="break-words">{country}</h4>
        <p :for={city <- cities} class="[overflow-wrap:anywhere]">{city}</p>
      </section>
    </div>
    """
  end
end

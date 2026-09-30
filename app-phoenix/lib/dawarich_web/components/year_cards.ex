defmodule DawarichWeb.YearCards do
  @moduledoc false
  use DawarichWeb, :html

  alias Dawarich.Stats.Toponyms
  alias DawarichWeb.{Chartkick, Icon, LocalizedDate, NumberFormat, StatsFormat}

  @month_colors ~w(#397bb5 #5A4E9D #3B945E #7BC96F #FFD54F #FFA94D #FF6B6B #FF8C42 #C97E4F #8B4513 #5A2E2E #265d7d)

  def month_colors, do: @month_colors

  attr :locale, :string, required: true
  attr :year, :map, required: true
  attr :unit, :string, required: true
  attr :geocoding, :boolean, required: true
  attr :table, :list, required: true

  def year_card(assigns) do
    ~H"""
    <div class="card w-full bg-base-200 shadow-xl">
      <div class="card-body">
        <h2 class={"card-title justify-between text-#{StatsFormat.header_color(@year.year)}"}>
          <div>
            <a class="underline hover:no-underline" href={"/stats/#{@year.year}"}>{@year.year}</a>
            <a class="underline hover:no-underline" href={StatsFormat.year_map_path(@year.year)}>{t(
              @locale,
              "stats.index.map",
              %{}
            )}</a>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-xs text-gray-500">{t(@locale, "stats.index.last_update", %{})} {LocalizedDate.l(
              @locale,
              @year.updated_on,
              "day_month_year"
            )}</span>
            <a
              data-turbo-method="put"
              class="text-sm text-gray-500 hover:text-primary"
              href={"/stats/#{@year.year}/all/update"}
            ><Icon.icon name="refresh-ccw" class="size-6" /></a>
          </div>
        </h2>
        <p>
          {NumberFormat.delimited(@locale, StatsFormat.rounded(Enum.sum(@year.distances), @unit))} {@unit}
        </p>
        <.places
          :if={@geocoding}
          locale={@locale}
          year={@year.year}
          places={Toponyms.year_places(@year.stats, @year.year, @table)}
          table={@table}
        />
        <Chartkick.column_chart
          id={"chart-year-distance-#{@year.year}"}
          height="200px"
          data={year_data(@locale, @year, @unit)}
          options={year_options(@locale, @unit)}
        />
      </div>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :year, :integer, required: true
  attr :places, :map, required: true
  attr :table, :list, required: true

  defp places(assigns) do
    ~H"""
    <div class="card-actions justify-end">
      <a
        class="link link-primary"
        data-turbo="false"
        onclick={"event.preventDefault(); document.getElementById('#{@places.modal_id}').checked = true"}
        href="#"
      >{t(@locale, "stats.index.countries_count_countries_cities_count_cities", %{
        countries_count: @places.countries_count,
        cities_count: @places.cities_count
      })}</a>
      <div>
        <input type="checkbox" id={@places.modal_id} class="modal-toggle" phx-update="ignore" />
        <div class="modal" role="dialog">
          <div class="modal-box max-w-3xl">
            <h3 class="text-lg font-bold mb-4">
              {t(@locale, "stats.index.countries_and_cities_visited_in", %{})} {@year}
            </h3>
            <div class="max-h-96 overflow-y-auto">
              <div :for={{country, cities} <- @places.grouped} class="mb-4">
                <h4 class="font-bold">
                  <span class="mr-2"><Icon.country_flag name={country} table={@table} /></span> {country}
                </h4>
                <div
                  :if={cities != []}
                  class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2 pl-4"
                >
                  <div :for={city <- cities} class="text-sm">{city}</div>
                </div>
                <p :if={cities == []} class="text-sm text-gray-500 italic pl-4">
                  {t(@locale, "stats.index.no_specific_cities_recorded", %{})}
                </p>
              </div>
            </div>
          </div>
          <label class="modal-backdrop" for={@places.modal_id}></label>
        </div>
      </div>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :year, :integer, required: true
  attr :unit, :string, required: true
  attr :upgrade, :string, required: true
  attr :badge, :string, required: true

  def locked_year_card(assigns) do
    ~H"""
    <div class="card w-full bg-base-200 shadow-xl">
      <div class="card-body">
        <h2 class={"card-title justify-between text-#{StatsFormat.header_color(@year)}"}>
          <div>{@year}</div>
          <a
            href={@badge}
            target="_blank"
            rel="noopener noreferrer"
            class="tooltip tooltip-bottom"
            data-tip={t(@locale, "helpers.application.pro_only", %{})}
            tabindex="0"
          ><span class="badge badge-sm badge-outline gap-1"><Icon.icon name="lock" class="w-3 h-3" />{t(
            @locale,
            "helpers.application.pro_badge",
            %{}
          )}</span></a>
        </h2>
        <div class="relative">
          <div class="opacity-20 blur-[3px] pointer-events-none select-none" aria-hidden="true">
            <Chartkick.column_chart
              id={"chart-year-locked-#{@year}"}
              height="200px"
              data={locked_data(@locale, @year)}
              options={[suffix: " " <> @unit, colors: month_colors()]}
            />
          </div>
          <div class="absolute inset-0 flex flex-col items-center justify-center">
            <Icon.icon name="lock" class="w-6 h-6 opacity-30" />
            <p class="text-sm text-base-content/50 mt-1">
              {t(@locale, "stats.locked_year_card.available_on_pro", %{})}
            </p>
            <a href={@upgrade} class="btn btn-sm btn-primary mt-2" target="_blank" rel="noopener">{t(
              @locale,
              "stats.locked_year_card.upgrade_to_pro",
              %{}
            )}</a>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :stat, :map, required: true
  attr :unit, :string, required: true

  def stat_card(assigns) do
    visited = Toponyms.visited(assigns.stat.toponyms)

    assigns =
      assign(assigns,
        countries: length(visited),
        cities: visited |> Enum.map(&length(&1["cities"])) |> Enum.sum()
      )

    ~H"""
    <a
      class="group block p-6 bg-base-100 hover:bg-base-200/50 rounded-xl border border-base-300 hover:border-primary/40 hover:shadow-lg transition-all duration-200 hover:scale-[1.02]"
      href={t(@locale, "stats.stat.year_month", %{year: @stat.year, month: @stat.month})}
    >
      <div class="flex items-center justify-between mb-4">
        <h3
          class="text-lg font-medium text-base-content group-hover:text-primary transition-colors flex items-center gap-2"
          style={"color: #{StatsFormat.month_color(@stat.month)};"}
        >
          <Icon.icon name={StatsFormat.month_icon(@stat.month)} class="size-6" /> {LocalizedDate.l(
            @locale,
            Date.new!(@stat.year, @stat.month, 1),
            "month_year"
          )}
        </h3>
        <div class="opacity-0 group-hover:opacity-100 transition-opacity">
          <svg class="w-5 h-5 text-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M9 5l7 7-7 7"
          /></svg>
        </div>
      </div>
      <div class="space-y-3">
        <div>
          <div
            class="text-2xl font-semibold text-base-content"
            style={"color: #{StatsFormat.month_color(@stat.month)};"}
          >
            {NumberFormat.delimited(@locale, StatsFormat.rounded(@stat.distance, @unit))}
            <span class="text-sm font-normal text-base-content/60 ml-1">{@unit}</span>
          </div>
          <div class="text-sm text-base-content/60">
            {t(@locale, "stats.stat.total_distance", %{})}
          </div>
        </div>
        <div class="text-sm text-gray-600">
          {t(@locale, "helpers.stats.countries_and_cities", %{countries: @countries, cities: @cities})}
        </div>
      </div>
    </a>
    """
  end

  defp year_data(locale, year, unit),
    do:
      for(
        {distance, month} <- Enum.with_index(year.distances, 1),
        do: [
          LocalizedDate.month_name(locale, year.year, month),
          if(distance == 0, do: nil, else: StatsFormat.rounded(distance, unit))
        ]
      )

  defp year_options(locale, unit),
    do: [
      suffix: " " <> unit,
      xtitle: t(locale, "stats.index.days", %{}),
      ytitle: t(locale, "stats.index.distance", %{}),
      colors: @month_colors,
      library: [
        datasets: [backgroundColor: @month_colors, borderWidth: 0, bar: [minBarLength: 4]],
        interaction: [mode: "index", intersect: false]
      ]
    ]

  defp locked_data(locale, year),
    do:
      for(
        month <- 1..12,
        do: [LocalizedDate.month_name(locale, year, month), Enum.random(5_000..80_000)]
      )
end

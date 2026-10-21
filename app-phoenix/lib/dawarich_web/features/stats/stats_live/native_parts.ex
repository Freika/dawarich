defmodule DawarichWeb.StatsLive.NativeParts do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.Analytics.Period
  alias DawarichWeb.{NativeChart, LocalizedDate, NumberFormat, StatsFormat}

  attr :data, :map, required: true
  attr :locale, :string, required: true
  attr :mode, :atom, required: true
  attr :month_layer, :string, default: "heatmap"

  def page(assigns) do
    ~H"""
    <div :if={@mode != :month} class="min-w-0">
      <section
        :if={@data.restricted}
        id="stats-window-alert"
        role="alert"
        class="alert flex flex-wrap min-w-0"
      >
        <p class="break-words min-w-0">
          {t(
            @locale,
            "shared.plan_data_window_alert.your_lite_plan_includes_the_last_12_months_of_data",
            %{}
          )}
        </p>
        <button id="stats-upgrade" class="btn whitespace-normal" phx-click="upgrade">{t(
          @locale,
          "shared.plan_data_window_alert.upgrade_to_pro",
          %{}
        )}</button>
      </section>
      <%= if @mode == :index do %>
        <p id="stats-total">
          {NumberFormat.delimited(@locale, Period.rounded(@data.total_distance, @data.unit))} {@data.unit}
        </p>
        <p>
          {NumberFormat.delimited(@locale, @data.points.total)} {t(
            @locale,
            "stats.index.geopoints_tracked",
            %{}
          )}
        </p>
        <p
          :if={@data.points.state == :pending}
          id="stats-count-pending"
          role="status"
          aria-live="polite"
        >
          {t(@locale, "javascript.common.loading", %{})}
        </p>
        <div :if={@data.points.state == :ready} id="stats-count-ready">
          {NumberFormat.delimited(@locale, @data.points.geocoded)} / {NumberFormat.delimited(
            @locale,
            @data.points.total
          )} ({@data.points.percentage}%)
        </div>
        <p
          :if={@data.points.state == :ready && (@data.points.without_data || 0) > 0}
          id="stats-without-data"
        >
          {@data.points.without_data} {t(
            @locale,
            "stats.reverse_geocoding_stats.points_without_data",
            %{}
          )}
        </p>
        <div class="flex flex-wrap gap-2 min-w-0">
          <button
            class="btn btn-outline whitespace-normal"
            phx-click="open_places"
            phx-value-kind="countries"
          >{t(@locale, "stats.reverse_geocoding_stats.countries_visited", %{})}: {@data.total_countries}</button>
          <button
            class="btn btn-outline whitespace-normal"
            phx-click="open_places"
            phx-value-kind="cities"
          >{t(@locale, "stats.reverse_geocoding_stats.cities_visited", %{})}: {@data.total_cities}</button>
        </div>
        <p id="stats-refresh-policy">
          {t(@locale, "stats.index.all_stats_data_above_except_for_total_distance_and_number", %{})}
        </p>
        <a href="/digests">{t(@locale, "stats.index.year_end_digests", %{})}</a>
        <DawarichWeb.StatsLive.NativeYearCard.render
          :for={year <- @data.years}
          year={year}
          locale={@locale}
          unit={@data.unit}
          chart={months(@locale, year.year, year.distances, @data.unit)}
          revision={revision(year.distances)}
        />
        <p :for={year <- @data.locked_years} id={"stats-locked-#{year}"} class="my-4">
          {year} — {t(@locale, "stats.locked_year_card.available_on_pro", %{})}
        </p>
        <nav aria-label={t(@locale, "views.pagination.next", %{})} class="flex flex-wrap gap-2">
          <.link :if={@data.page > 1} patch={"/stats?page=#{@data.page-1}"} class="btn">{t(
            @locale,
            "views.pagination.previous",
            %{}
          )}</.link>
          <.link :if={@data.more} patch={"/stats?page=#{@data.page+1}"} class="btn">{t(
            @locale,
            "views.pagination.next",
            %{}
          )}</.link>
        </nav>
      <% else %>
        <p>{@data.year}</p>
        <%= if @mode == :year do %>
          <NativeChart.chart
            id="stats-native-chart"
            data={months(@locale, @data.year, @data.distances, @data.unit)}
            revision={revision(@data.distances)}
            label={t(@locale, "stats.year.distance", %{})}
            options={%{suffix: " " <> @data.unit}}
          />
          <article :for={stat <- @data.stats} class="my-4 border rounded-lg p-4 min-w-0">
            <.link href={"/stats/#{@data.year}/#{stat.month}"} class="underline">{LocalizedDate.month_name(
              @locale,
              @data.year,
              stat.month
            )}</.link>
            <p>
              {NumberFormat.delimited(@locale, Period.rounded(stat.distance, @data.unit))} {@data.unit}
            </p>
            <p id={"stats-month-places-#{stat.month}"} class="[overflow-wrap:anywhere]">
              {Enum.join(cities([stat]), ", ")}
            </p>
            <.link href={StatsFormat.year_map_path(@data.year)}>{t(@locale, "stats.year.map", %{})}</.link>
          </article>
        <% end %>
      <% end %>
    </div>
    <DawarichWeb.StatsLive.NativeMonthParts.summary
      :if={@mode == :month}
      data={@data}
      locale={@locale}
      layer={@month_layer}
    />
    """
  end

  attr :dialog, :any, required: true
  attr :data, :map, required: true
  attr :locale, :string, required: true
  attr :path, :string, default: "/stats"
  attr :query, :map, default: %{}
  def dialog(assigns), do: DawarichWeb.StatsLive.NativeDialog.render(assigns)

  defp revision(data),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(data)) |> Base.encode16(case: :lower)

  defp cities(stats),
    do: stats |> Enum.flat_map(& &1.toponyms) |> Dawarich.Stats.Toponyms.cities()

  defp months(locale, year, distances, unit),
    do:
      for(
        {meters, month} <- Enum.with_index(distances, 1),
        do: [LocalizedDate.month_name(locale, year, month), Period.rounded(meters, unit)]
      )
end

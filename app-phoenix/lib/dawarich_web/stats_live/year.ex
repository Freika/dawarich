defmodule DawarichWeb.StatsLive.Year do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.StatsCards, only: [plan_alert: 1]
  import DawarichWeb.YearCards, only: [stat_card: 1]

  alias Dawarich.Stats
  alias DawarichWeb.{Chartkick, LocalizedDate, Params, RailsWidgets, StatsFormat, YearCards}

  @impl true
  def mount(params, _session, socket),
    do: {:ok, assign(socket, page(socket.assigns.current_user, params, socket.assigns))}

  @impl true
  def handle_event("rails_flash", params, socket),
    do: {:noreply, RailsWidgets.rails_flash(socket, params)}

  def page(user, %{"year" => year}, %{locale: locale, now: now, self_hosted: self_hosted}) do
    year = Params.ruby_to_i(year)
    context = Stats.context(user, now, self_hosted)
    unit = StatsFormat.unit(user.settings)
    data = Stats.year(user, year, context)

    Map.merge(data, %{
      page_title: t(locale, "stats.show.statistics_for_year_year", %{year: year}),
      rails_js: true,
      year: year,
      restricted: context.restricted,
      unit: unit,
      color: StatsFormat.sample_header_color(user.id, year, now),
      alert_href: StatsFormat.upgrade_url(user, now, self_hosted, "data_window", "stats_year"),
      chart:
        for(
          {distance, month} <- Enum.with_index(data.distances, 1),
          do: [LocalizedDate.month_name(locale, year, month), StatsFormat.rounded(distance, unit)]
        )
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full my-5">
      <.plan_alert :if={@restricted} locale={@locale} href={@alert_href} />
      <h2 class="text-3xl font-bold mt-10">
        <a class={"underline hover:no-underline text-#{@color}"} href={"/stats/#{@year}"}>{@year}</a>
        <a class="underline hover:no-underline" href={StatsFormat.year_map_path(@year)}>{t(
          @locale,
          "stats.year.map",
          %{}
        )}</a>
      </h2>
      <div class="my-10">
        <Chartkick.column_chart
          id={"chart-year-distance-#{@year}"}
          height="200px"
          data={@chart}
          options={[
            suffix: " " <> @unit,
            xtitle: t(@locale, "stats.year.days", %{}),
            ytitle: t(@locale, "stats.year.distance", %{}),
            colors: YearCards.month_colors()
          ]}
        />
      </div>
      <div class="mt-5 grid grid-cols-1 sm:grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 p-4">
        <.stat_card :for={stat <- @stats} locale={@locale} stat={stat} unit={@unit} />
      </div>
    </div>
    """
  end
end

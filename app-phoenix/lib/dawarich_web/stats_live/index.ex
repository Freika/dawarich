defmodule DawarichWeb.StatsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.StatsCards, only: [plan_alert: 1, reverse_geocoding: 1]
  import DawarichWeb.YearCards, only: [year_card: 1, locked_year_card: 1]

  alias Dawarich.{CountryNames, Stats}
  alias DawarichWeb.{Icon, NumberFormat, RailsWidgets, StatsFormat}

  @impl true
  def mount(params, _session, socket),
    do: {:ok, assign(socket, page(socket.assigns.current_user, params, socket.assigns))}

  @impl true
  def handle_event("rails_flash", params, socket),
    do: {:noreply, RailsWidgets.rails_flash(socket, params)}

  def page(user, _params, %{locale: locale, now: now, self_hosted: self_hosted}) do
    context = Stats.context(user, now, self_hosted)
    geocoding = Dawarich.Geocoding.Config.resolve(Dawarich.Repo)
    data = Stats.index(user, context, geocoding.store_geodata, now)
    upgrade = &StatsFormat.upgrade_url(user, now, self_hosted, &1, &2)

    Map.merge(data, %{
      page_title: t(locale, "stats.index.statistics", %{}),
      rails_js: true,
      restricted: context.restricted,
      geocoding: geocoding.enabled,
      store_geodata: geocoding.store_geodata,
      table: if(geocoding.enabled and data.years != [], do: CountryNames.table(), else: []),
      unit: StatsFormat.unit(user.settings),
      active: user.status == 1,
      alert_href: upgrade.("data_window", "stats_index"),
      badge_href: upgrade.("badge", "pro_badge"),
      locked_hrefs: Map.new(data.locked_years, &{&1, upgrade.("stats", "stats_year_#{&1}")})
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full my-5">
      <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between mb-6">
        <h1 class="text-3xl font-bold">{t(@locale, "stats.index.statistics", %{})}</h1>
        <div
          :if={Date.compare(DateTime.to_date(@now), ~D[2025-12-31]) != :lt}
          class="flex flex-wrap gap-2"
        >
          <a class="btn btn-outline btn-sm" href="/digests"><Icon.icon name="earth" class="size-6" /> {t(
            @locale,
            "stats.index.year_end_digests",
            %{}
          )}</a>
        </div>
      </div>
      <.plan_alert :if={@restricted} locale={@locale} href={@alert_href} />
      <div class="stats stats-vertical lg:stats-horizontal shadow w-full bg-base-200 relative">
        <div class="stat text-center">
          <div class="stat-value text-primary">
            {NumberFormat.delimited(@locale, StatsFormat.rounded(@total_distance, @unit))} {@unit}
          </div>
          <div class="stat-title">{t(@locale, "stats.index.total_distance", %{})}</div>
        </div>
        <div class="stat text-center">
          <div class="stat-value text-success">{NumberFormat.delimited(@locale, @points.total)}</div>
          <div class="stat-title">{t(@locale, "stats.index.geopoints_tracked", %{})}</div>
        </div>
        <.reverse_geocoding
          :if={@geocoding}
          locale={@locale}
          points={@points}
          store_geodata={@store_geodata}
          countries={@countries_visited}
          cities={@cities_visited}
        />
      </div>
      <div class="text-xs text-gray-500 text-center mt-5">
        {t(@locale, "stats.index.all_stats_data_above_except_for_total_distance_and_number", %{})}
      </div>
      <a :if={@active} data-turbo-method="put" class="btn btn-primary mt-5" href="/stats/update_all">{t(
        @locale,
        "stats.index.update_stats",
        %{}
      )}</a>
      <div class="mt-6 grid grid-cols-1 sm:grid-cols-1 md:grid-cols-2 lg:grid-cols-2 gap-6">
        <.year_card
          :for={year <- @years}
          locale={@locale}
          year={year}
          unit={@unit}
          geocoding={@geocoding}
          table={@table}
        />
        <.locked_year_card
          :for={year <- @locked_years}
          locale={@locale}
          year={year}
          unit={@unit}
          upgrade={@locked_hrefs[year]}
          badge={@badge_href}
        />
      </div>
    </div>
    """
  end
end

defmodule DawarichWeb.InsightsLive.NativeHeader do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  alias DawarichWeb.StatsFormat
  attr :data, :map, required: true
  attr :locale, :string, required: true

  def render(assigns) do
    ~H"""
    <div class="mb-6 space-y-3">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div class="min-w-0">
          <div class="flex items-center gap-2">
            <.icon name="compass" class="w-7 h-7 text-primary shrink-0" />
            <h1 class="text-3xl font-bold">{t(@locale, "insights.header.insights", %{})}</h1>
          </div>
          <p class="text-base-content/60 mt-1">
            {t(@locale, "insights.header.your_personal_movement_analytics_and_travel_patterns", %{})}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <.link
            :if={Date.compare(@data.period.today, ~D[2025-12-31]) != :lt}
            navigate="/digests"
            class="btn btn-sm"
          >
            <.icon name="earth" class="w-4 h-4" /> {t(@locale, "stats.index.year_end_digests", %{})}
          </.link>
          <a :if={!@data.all_time} href={StatsFormat.year_map_path(@data.year)} class="btn btn-sm">
            <.icon name="map" class="w-4 h-4" /> {t(@locale, "shared.navbar.map", %{})}
          </a>
          <a
            :if={@data.active && !@data.year_locked}
            id="insights-update"
            href={if @data.all_time, do: "/stats/update_all", else: "/stats/#{@data.year}/all/update"}
            phx-click="update"
            class="btn btn-sm btn-ghost"
          >
            <.icon name="refresh-ccw" class="w-4 h-4" /> {t(@locale, "stats.index.update_stats", %{})}
          </a>
        </div>
      </div>
      <nav
        :if={@data.available != []}
        class="flex flex-wrap gap-2"
        aria-label={t(@locale, "insights.header.period", %{})}
        data-testid="insights-period"
      >
        <.link
          patch="/insights?year=all"
          class={"btn btn-sm #{if @data.all_time, do: "btn-primary"}"}
          aria-current={@data.all_time && "page"}
        >{t(@locale, "insights.header.all_time", %{})}</.link>
        <.link
          :for={year <- @data.available}
          patch={"/insights?year=#{year}"}
          class={"btn btn-sm tabular-nums #{if !@data.all_time && year == @data.year, do: "btn-primary"}"}
          aria-current={!@data.all_time && year == @data.year && "page"}
        >
          <.icon :if={year in @data.locked} name="lock" class="w-3 h-3 opacity-60" />
          <span :if={year in @data.locked} class="sr-only">{t(
            @locale,
            "stats.locked_year_card.available_on_pro",
            %{}
          )}</span>
          {year}
        </.link>
      </nav>
    </div>
    """
  end
end

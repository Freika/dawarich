defmodule DawarichWeb.StatsLive.NativeMonthParts do
  @moduledoc false
  use DawarichWeb, :html

  alias Dawarich.Stats.Toponyms
  alias DawarichWeb.{NativeChart, Icon, LocalizedDate, StatsFormat}

  @daily_colors ~w(#570df8 #f000b8 #ffea00 #00d084 #3abff8 #ff5724 #8e24aa #3949ab #00897b #d81b60 #5e35b1 #039be5 #43a047 #f4511e #6d4c41 #757575 #546e7a #d32f2f)

  attr :data, :map, required: true
  attr :locale, :string, required: true
  attr :layer, :string, default: "heatmap"

  def summary(assigns) do
    data = assigns.data

    assigns =
      assign(
        assigns,
        Map.merge(Map.delete(data, :data), %{
          stat: data.data.stat,
          previous: data.data.previous,
          average_km: data.data.average_km,
          bg_url: "/native/" <> StatsFormat.month_background(data.month)
        })
      )

    ~H"""
    <div class="w-full my-5">
      <DawarichWeb.StatsCards.plan_alert :if={@restricted} native locale={@locale} href="#" />
      <%= if @stat do %>
        <div
          class="hero text-white rounded-lg shadow-lg mb-8"
          style={"background-image: url('#{@bg_url}');"}
        >
          <div class="hero-overlay bg-opacity-60"></div>
          <div class="hero-content text-center relative w-full">
            <div class="max-w-md mt-5">
              <h1 class="text-4xl font-bold flex items-center justify-center gap-2">
                <Icon.icon name={StatsFormat.month_icon(@month)} class="size-6" /> {LocalizedDate.l(
                  @locale,
                  Date.new!(@year, @month, 1),
                  "month_year"
                )}
              </h1>
              <p class="py-4">{t(@locale, "stats.month.monthly_digest", %{})}</p>
              <button
                class="btn btn-outline btn-sm text-neutral border-neutral hover:bg-white hover:text-primary"
                phx-click="open_share"
              >
                <Icon.icon name="share" class="size-6" /> {t(@locale, "stats.month.share", %{})}
              </button>
            </div>
          </div>
        </div>
        <.stats_row
          locale={@locale}
          stat={@stat}
          previous={@previous}
          average_km={@average_km}
          unit={@unit}
        />
        <DawarichWeb.StatsLive.NativeMonthMap.render data={@data} locale={@locale} layer={@layer} />
        <div class="card bg-base-100 shadow-xl mb-8">
          <div class="card-body">
            <h2 class="card-title">
              <Icon.icon name="activity" class="size-6" /> {t(
                @locale,
                "stats.month.daily_activity",
                %{}
              )}
            </h2>
            <div class="w-full h-48 bg-base-200 rounded-lg p-4 relative">
              <NativeChart.chart
                rails
                revision={
                  :crypto.hash(:sha256, :erlang.term_to_binary(@stat.daily)) |> Base.encode16()
                }
                label={t(@locale, "stats.month.daily_activity", %{})}
                id={"chart-month-daily-#{@year}-#{@month}"}
                height="200px"
                data={for [day, meters] <- @stat.daily, do: [day, StatsFormat.rounded(meters, @unit)]}
                options={NativeChart.options(daily_options(@locale, @unit))}
              />
            </div>
            <div class="text-sm opacity-70 text-center mt-2">
              {t(@locale, "stats.month.peak_day", %{})}
              <%= if @peak do %>
                <a id="native-stats-peak-day" class="underline" href={StatsFormat.peak_href(@bounds)}>{StatsFormat.peak_text(
                  @locale,
                  @year,
                  @month,
                  @peak,
                  @unit
                )}</a>
              <% else %>
                {t(@locale, "common.not_available", %{})}
              <% end %>
              {t(@locale, "stats.month.quietest_week", %{})} {StatsFormat.quietest_week(
                @locale,
                @year,
                @month,
                @stat.daily
              )}
            </div>
          </div>
        </div>
        <DawarichWeb.StatsLive.NativeMonthPlaces.render locale={@locale} toponyms={@stat.toponyms} />
        <div class="flex flex-wrap gap-4 mt-8 justify-center">
          <a href={"/insights?year=#{@year}"} class="btn btn-outline">{t(
            @locale,
            "stats.month.back_to",
            %{}
          )} {@year}</a>
          <button class="btn btn-outline" phx-click="open_share"><Icon.icon
            name="share"
            class="size-6"
          /> {t(
            @locale,
            "stats.month.share",
            %{}
          )}</button>
        </div>
      <% else %>
        <div class="alert">
          {t(@locale, "stats.month.no_location_data_available_for_this_month", %{})}
        </div>
      <% end %>
    </div>
    """
  end

  defp stats_row(assigns) do
    ~H"""
    <div class="stats stats-vertical lg:stats-horizontal shadow shadow-lg mx-auto mb-8 w-full">
      <div class="stat place-items-center text-center">
        <div class="stat-title flex items-center justify-center gap-1">
          <Icon.icon name="map-plus" class="size-6" /> {t(
            @locale,
            "stats.month.distance_traveled",
            %{}
          )}
        </div>
        <div id="native-stats-month-distance" class="stat-value text-success">
          ~{StatsFormat.distance(@locale, @stat.distance, @unit)}
        </div>
        <div id="native-stats-month-average" class="stat-desc">
          {StatsFormat.than_average(@locale, @stat.distance, @average_km)}
        </div>
      </div>
      <div :if={@stat.flight_distance > 0} class="stat place-items-center text-center">
        <div class="stat-title flex items-center justify-center gap-1">
          <Icon.icon name="plane" class="size-6" /> {t(@locale, "stats.month.flight_distance", %{})}
        </div>
        <div class="stat-value text-info">
          {StatsFormat.distance(@locale, @stat.flight_distance, @unit)}
        </div>
        <div class="stat-desc">
          {t(@locale, "stats.month.from_airtrail_not_counted_in_distance", %{})}
        </div>
      </div>
      <div class="stat place-items-center text-center">
        <div class="stat-title flex items-center justify-center gap-1">
          <Icon.icon name="calendar-check-2" class="size-6" /> {t(
            @locale,
            "stats.month.active_days",
            %{}
          )}
        </div>
        <div id="native-stats-month-active-days" class="stat-value text-secondary">
          {StatsFormat.active_days(@stat.daily)}
        </div>
        <div class="stat-desc">
          {StatsFormat.than_previous_active_days(@locale, @stat.daily, @previous)}
        </div>
      </div>
      <div class="stat place-items-center text-center">
        <div class="stat-title flex items-center justify-center gap-1">
          <Icon.icon name="map-pin-plus" class="size-6" /> {t(
            @locale,
            "stats.month.countries_visited",
            %{}
          )}
        </div>
        <div class="stat-value text-accent">{length(Toponyms.countries(@stat.toponyms))}</div>
        <div class="stat-desc">
          {StatsFormat.than_previous_countries(@locale, @stat.toponyms, @previous)}
        </div>
      </div>
    </div>
    """
  end

  defp daily_options(locale, unit),
    do: [
      suffix: " " <> unit,
      xtitle: t(locale, "stats.month.day", %{}),
      ytitle: t(locale, "stats.month.distance", %{}),
      colors: @daily_colors,
      library: [
        plugins: [legend: [display: false]],
        scales: [x: [grid: [color: "rgba(0,0,0,0.1)"]], y: [grid: [color: "rgba(0,0,0,0.1)"]]]
      ]
    ]
end

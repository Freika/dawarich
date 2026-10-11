defmodule DawarichWeb.PublicMonth do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.Stats.Toponyms
  alias DawarichWeb.{Chartkick, Icon, LocalizedDate, StatsFormat}

  @colors ~w(#570df8 #f000b8 #ffea00 #00d084 #3abff8 #ff5724 #8e24aa #3949ab #00897b #d81b60 #5e35b1 #039be5 #43a047 #f4511e #6d4c41 #757575 #546e7a #d32f2f)

  def document(assigns) do
    assigns = assign(assigns, :visited, Toponyms.visited(assigns.stat.toponyms))

    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div
        class="hero text-white rounded-lg shadow-lg mb-8"
        style={"background-image: url('#{@bg_url}');"}
      >
        <div class="hero-overlay bg-opacity-60"></div>
        <div class="hero-content text-center py-8">
          <div class="max-w-lg">
            <h1 class="text-4xl font-bold flex items-center justify-center gap-2">
              <Icon.icon name={StatsFormat.month_icon(@month)} class="size-6" /> {LocalizedDate.l(
                @locale,
                Date.new!(@year, @month, 1),
                "month_year"
              )}
            </h1>
            <p class="pt-6 pb-2">{t(@locale, "stats.public_month.monthly_digest", %{})}</p>
          </div>
        </div>
      </div>
      <div class="stats stats-vertical lg:stats-horizontal shadow mx-auto mb-8 w-full">
        <div class="stat place-items-center text-center">
          <div class="stat-title">{t(@locale, "stats.public_month.distance_traveled", %{})}</div>
          <div class="stat-value">{StatsFormat.distance(@locale, @stat.distance, @unit)}</div>
          <div class="stat-desc">
            {t(@locale, "stats.public_month.total_distance_for_this_month", %{})}
          </div>
        </div>
        <div :if={@stat.flight_distance > 0} class="stat place-items-center text-center">
          <div class="stat-title">{t(@locale, "stats.public_month.flight_distance", %{})}</div>
          <div class="stat-value text-info">
            {StatsFormat.distance(@locale, @stat.flight_distance, @unit)}
          </div>
          <div class="stat-desc">
            {t(@locale, "stats.public_month.from_airtrail_not_counted_in_distance", %{})}
          </div>
        </div>
        <div class="stat place-items-center text-center">
          <div class="stat-title">{t(@locale, "stats.public_month.active_days", %{})}</div>
          <div class="stat-value text-secondary">{StatsFormat.active_days(@stat.daily)}</div>
          <div class="stat-desc text-secondary">
            {t(@locale, "stats.public_month.days_with_tracked_activity", %{})}
          </div>
        </div>
        <div class="stat place-items-center text-center">
          <div class="stat-title">{t(@locale, "stats.public_month.countries_visited", %{})}</div>
          <div class="stat-value">{length(@visited)}</div>
          <div class="stat-desc">{t(@locale, "stats.public_month.different_countries", %{})}</div>
        </div>
      </div>
      <div class="card bg-base-100 shadow-xl mb-8">
        <div class="card-body p-0">
          <div class="p-4 border-b border-base-300 bg-base-50">
            <div class="flex justify-between items-center">
              <div class="flex items-center gap-4">
                <h3 class="font-semibold text-lg flex items-center gap-2">
                  <Icon.icon name="map" class="size-6" /> {t(
                    @locale,
                    "stats.public_month.location_hexagons",
                    %{}
                  )}
                </h3>
              </div>
            </div>
          </div>
          <div class="w-full h-96 border border-base-300 relative overflow-hidden">
            <div
              phx-hook="RailsStimulus"
              id="public-monthly-stats-map"
              class="w-full h-full"
              data-controller="public-stat-map"
              data-public-stat-map-year-value={@year}
              data-public-stat-map-month-value={@month}
              data-public-stat-map-uuid-value={@uuid}
              data-public-stat-map-data-bounds-value={
                if @data_bounds, do: Jason.encode!(@data_bounds), else: ""
              }
              data-public-stat-map-hexagons-available-value={to_string(@hexagons)}
              data-public-stat-map-timezone-value={@timezone}
            >
            </div>
            <div
              id="map-loading"
              class="absolute inset-0 bg-base-200 bg-opacity-80 flex items-center justify-center z-50"
            >
              <div class="text-center">
                <span class="loading loading-spinner loading-lg text-primary"></span>
                <p class="text-sm mt-2 text-base-content">
                  {t(@locale, "stats.public_month.loading_hexagons", %{})}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
      <div class="card bg-base-100 shadow-xl mb-8">
        <div class="card-body">
          <h2 class="card-title">
            <Icon.icon name="trending-up" class="size-6" /> {t(
              @locale,
              "stats.public_month.daily_activity",
              %{}
            )}
          </h2>
          <div class="w-full h-48 bg-base-200 rounded-lg p-4 relative">
            <Chartkick.column_chart
              id="chart-1"
              height="200px"
              data={for [day, meters] <- @stat.daily, do: [day, StatsFormat.rounded(meters, "km")]}
              options={options(@locale)}
            />
          </div>
          <div class="text-sm opacity-70 text-center mt-2">
            {t(@locale, "stats.public_month.peak_day", %{})}
            <%= if @peak do %>
              <a class="underline" href={StatsFormat.peak_href(@peak_bounds)}>{StatsFormat.peak_text(
                @locale,
                @year,
                @month,
                @peak,
                @unit
              )}</a>
            <% else %>
              {t(@locale, "common.not_available", %{})}
            <% end %>
            {t(@locale, "stats.public_month.quietest_week", %{})} {StatsFormat.quietest_week(
              @locale,
              @year,
              @month,
              @stat.daily
            )}
          </div>
        </div>
      </div>
      <div class="card bg-base-100 shadow-xl mb-8">
        <div class="card-body">
          <h2 class="card-title">
            <Icon.icon name="earth" class="size-6" /> {t(
              @locale,
              "stats.public_month.countries_cities",
              %{}
            )}
          </h2>
          <div class="space-y-4">
            <div :for={{country, index} <- Enum.with_index(@visited)} class="space-y-2">
              <div class="flex justify-between items-center">
                <span class="font-semibold">{country["country"]}</span><span class="text-sm">{length(
                  country["cities"]
                )} {t(@locale, "stats.public_month.cities", %{})}</span>
              </div>
              <progress class="progress progress-primary w-full" value={100 - index * 20} max="100"></progress>
            </div>
          </div>
          <div class="divider"></div>
          <div class="flex flex-wrap gap-2">
            <span class="text-sm font-medium">{t(@locale, "stats.public_month.cities_visited", %{})}</span>
            <%= for country <- @visited do %>
              <div :for={city <- Enum.take(country["cities"], 5)} class="badge badge-outline">
                {city["city"]}
              </div>
              <div :if={length(country["cities"]) > 5} class="badge badge-ghost">
                +{length(country["cities"]) - 5} {t(@locale, "stats.public_month.more", %{})}
              </div>
            <% end %>
          </div>
        </div>
      </div>
      <div class="text-center py-8">
        <div class="text-sm text-gray-500">
          {t(@locale, "stats.public_month.powered_by", %{})} <a
            href="https://dawarich.app"
            class="link link-primary"
            target="_blank"
          >{t(@locale, "stats.public_month.dawarich", %{})}</a>{t(
            @locale,
            "stats.public_month.your_personal_memories_mapper",
            %{}
          )}
        </div>
      </div>
    </div>
    """
  end

  defp options(locale),
    do: [
      suffix: t(locale, "units.kilometers_suffix", %{}),
      xtitle: t(locale, "stats.public_month.day", %{}),
      ytitle: t(locale, "stats.public_month.distance", %{}),
      colors: @colors,
      library: [
        plugins: [legend: [display: false]],
        scales: [x: [grid: [color: "rgba(0,0,0,0.1)"]], y: [grid: [color: "rgba(0,0,0,0.1)"]]]
      ]
    ]
end

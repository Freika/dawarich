defmodule DawarichWeb.StatsMonth do
  @moduledoc false
  use DawarichWeb, :html

  alias Dawarich.Stats.Toponyms
  alias DawarichWeb.{Chartkick, Icon, LocalizedDate, SharingParts, StatsFormat}

  @daily_colors ~w(#570df8 #f000b8 #ffea00 #00d084 #3abff8 #ff5724 #8e24aa #3949ab #00897b #d81b60 #5e35b1 #039be5 #43a047 #f4511e #6d4c41 #757575 #546e7a #d32f2f)

  attr :locale, :string, required: true
  attr :year, :integer, required: true
  attr :month, :integer, required: true
  attr :stat, :map, required: true
  attr :previous, :map, default: nil
  attr :average_km, :integer, required: true
  attr :unit, :string, required: true
  attr :peak, :any, required: true
  attr :bounds, :any, required: true
  attr :api_key, :string, required: true
  attr :tiles_url, :string, required: true
  attr :tiles_fallback, :string, required: true
  attr :bg_url, :string, required: true
  attr :sharing_allowed, :boolean, required: true
  attr :sharing_url, :string, required: true
  attr :sharing_upgrade, :string, required: true
  attr :csrf, :string, default: nil

  def month_digest(assigns) do
    ~H"""
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
            onclick="sharing_modal.showModal()"
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
    <div
      id="stat-page-card"
      class="card bg-base-100 shadow-xl mb-8"
      data-controller="stat-page"
      data-api-key={@api_key}
      data-year={@year}
      data-month={@month}
      data-tiles-url={@tiles_url}
      data-tiles-fallback={@tiles_fallback}
      phx-hook="RailsStimulus"
      phx-update="ignore"
    >
      <div class="card-body">
        <div class="page-header-row mb-4">
          <h2 class="card-title">
            <Icon.icon name="map" class="size-6" /> {t(@locale, "stats.month.map_summary", %{})}
          </h2>
          <div class="flex flex-wrap gap-2">
            <button
              class="btn btn-sm btn-outline btn-active"
              data-stat-page-target="heatmapBtn"
              data-action="click->stat-page#toggleHeatmap"
            ><Icon.icon name="flame" class="size-6" /> {t(@locale, "stats.month.heatmap", %{})}</button>
            <button
              class="btn btn-sm btn-outline"
              data-stat-page-target="pointsBtn"
              data-action="click->stat-page#togglePoints"
            ><Icon.icon name="map-pin" class="size-6" /> {t(@locale, "stats.month.points", %{})}</button>
          </div>
        </div>
        <div class="w-full h-96 rounded-lg border border-base-300 relative overflow-hidden">
          <div id="monthly-stats-map" data-stat-page-target="map" class="w-full h-full"></div>
          <div
            data-stat-page-target="loading"
            class="absolute inset-0 bg-base-200 flex items-center justify-center"
          >
            <span class="loading loading-spinner loading-lg text-primary"></span>
          </div>
        </div>
      </div>
    </div>
    <div class="card bg-base-100 shadow-xl mb-8">
      <div class="card-body">
        <h2 class="card-title">
          <Icon.icon name="activity" class="size-6" /> {t(@locale, "stats.month.daily_activity", %{})}
        </h2>
        <div class="w-full h-48 bg-base-200 rounded-lg p-4 relative">
          <Chartkick.column_chart
            id={"chart-month-daily-#{@year}-#{@month}"}
            height="200px"
            data={for [day, meters] <- @stat.daily, do: [day, StatsFormat.rounded(meters, @unit)]}
            options={daily_options(@locale, @unit)}
          />
        </div>
        <div class="text-sm opacity-70 text-center mt-2">
          {t(@locale, "stats.month.peak_day", %{})}
          <%= if @peak do %>
            <a class="underline" href={StatsFormat.peak_href(@bounds)}>{StatsFormat.peak_text(
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
    <.places_card locale={@locale} toponyms={@stat.toponyms} />
    <div class="flex flex-wrap gap-4 mt-8 justify-center">
      <a href={"/stats/#{@year}"} class="btn btn-outline">{t(@locale, "stats.month.back_to", %{})} {@year}</a>
      <button class="btn btn-outline" onclick="sharing_modal.showModal()"><Icon.icon
        name="share"
        class="size-6"
      /> {t(
        @locale,
        "stats.month.share",
        %{}
      )}</button>
    </div>
    <SharingParts.sharing_dialog
      locale={@locale}
      scope="shared.sharing_modal"
      hint="shared.sharing_modal.allow_others_to_view_this_monthly_digest_auto_saves_on"
      action={"/stats/#{@year}/#{@month}/sharing"}
      enabled={@stat.sharing.enabled}
      expiration={@stat.sharing.expiration || "1h"}
      url={@sharing_url}
      csrf={@csrf}
      allowed={@sharing_allowed}
      upgrade={@sharing_upgrade}
    />
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
        <div class="stat-value text-success">
          ~{StatsFormat.distance(@locale, @stat.distance, @unit)}
        </div>
        <div class="stat-desc">{StatsFormat.than_average(@locale, @stat.distance, @average_km)}</div>
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
        <div class="stat-value text-secondary">{StatsFormat.active_days(@stat.daily)}</div>
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
        <div class="stat-value text-accent">{length(Toponyms.visited(@stat.toponyms))}</div>
        <div class="stat-desc">
          {StatsFormat.than_previous_countries(@locale, @stat.toponyms, @previous)}
        </div>
      </div>
    </div>
    """
  end

  defp places_card(assigns) do
    visited = Toponyms.visited(assigns.toponyms)

    assigns =
      assign(assigns,
        visited: visited,
        max: visited |> Enum.map(&length(&1["cities"])) |> Enum.max(fn -> 0 end)
      )

    ~H"""
    <div class="card bg-base-100 shadow-xl mb-8">
      <div class="card-body">
        <h2 class="card-title">
          <Icon.icon name="globe" class="size-6" /> {t(@locale, "stats.month.countries_cities", %{})}
        </h2>
        <div class="space-y-4">
          <%= if @visited != [] do %>
            <div :for={{country, index} <- Enum.with_index(@visited)} class="space-y-2">
              <div class="flex justify-between items-center">
                <span class="font-semibold">{country["country"]}</span>
                <span class="text-sm">
                  {t(@locale, "stats.month.city_count", %{count: length(country["cities"])})}
                  <%= if StatsFormat.city_progress(length(country["cities"]), @max) > 0 do %>
                    ({StatsFormat.city_progress(length(country["cities"]), @max)}%)
                  <% end %>
                </span>
              </div>
              <progress
                class={"progress #{StatsFormat.progress_color(index)} w-full"}
                value={StatsFormat.city_progress(length(country["cities"]), @max)}
                max="100"
              ></progress>
            </div>
          <% else %>
            <div class="text-center text-gray-500">
              <p>{t(@locale, "stats.month.no_location_data_available_for_this_month", %{})}</p>
            </div>
          <% end %>
        </div>
        <div class="divider"></div>
        <div class="flex flex-wrap gap-2">
          <span class="text-sm font-medium">{t(@locale, "stats.month.cities_visited", %{})}</span>
          <%= for country <- @visited, %{"city" => city} <- country["cities"] do %>
            <div class="badge badge-outline">{city}</div>
          <% end %>
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

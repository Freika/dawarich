defmodule DawarichWeb.InsightsLive.NativeParts do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.InsightsParts
  alias DawarichWeb.InsightsDetails.{YearComparison, Activity, Locations, Travel, Wellness}

  attr :data, :map, required: true
  attr :query, :map, required: true
  attr :locale, :string, required: true
  attr :path, :string, required: true

  def overview(assigns) do
    ~H"""
    <DawarichWeb.InsightsLive.NativeHeader.render data={@data} locale={@locale} />
    <InsightsParts.stats_row
      :if={!@data.year_locked}
      locale={@locale}
      totals={@data.totals}
      all_time={@data.all_time}
      year={@data.year}
      unit={@data.unit}
    />
    <DawarichWeb.InsightsLive.NativeConsolidated.render
      :if={!@data.year_locked}
      data={@data}
      locale={@locale}
    />
    """
  end

  attr :kind, :string, required: true
  attr :read, :map, required: true
  attr :locale, :string, required: true
  attr :query, :map, required: true
  attr :path, :string, required: true

  attr :calendar_mode, :string, default: "both"
  attr :calendar_country, :any, default: nil
  attr :heatmap, :any, default: nil
  attr :unit, :string, default: "km"

  attr :race, :any, default: nil

  def read(assigns) do
    ~H"""
    <section
      :if={@read.state == :loading}
      id={"insights-#{@kind}-loading"}
      role="status"
      aria-live="polite"
    >
      {t(@locale, "javascript.common.loading", %{})}
    </section>
    <section
      :if={@read.state == :failed}
      id={"insights-#{@kind}-error"}
      role="alert"
      class="alert flex-wrap min-w-0"
    >
      <span class="break-words">{t(@locale, "controllers.application.admin_action_failed", %{})}</span>
      <button class="btn whitespace-normal" phx-click="retry_read" phx-value-kind={@kind}>{t(
        @locale,
        "javascript.common.confirm",
        %{}
      )}</button>
    </section>
    <%= if @read.state in [:ready, :pending] do %>
      <.details
        :if={@kind == "details"}
        data={@read.value}
        locale={@locale}
        query={@query}
        path={@path}
      />
      <.residency
        :if={@kind == "residency"}
        race={@race}
        calendar_mode={@calendar_mode}
        calendar_country={@calendar_country}
        heatmap={@heatmap}
        unit={@unit}
        data={@read.value}
        locale={@locale}
        query={@query}
        path={@path}
      />
    <% end %>
    """
  end

  attr :data, :map, required: true
  attr :locale, :string, required: true
  attr :query, :map, required: true
  attr :path, :string, required: true

  def details(assigns) do
    ~H"""
    <section
      id={if(@data.state == :ready, do: "insights-details-ready", else: "insights-details-pending")}
      class="contents"
    >
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <div class="space-y-6">
          <YearComparison.render data={@data} locale={@locale} />
          <Activity.render data={@data} locale={@locale} />
          <Locations.render data={@data} locale={@locale} />
        </div>
        <div class="space-y-6">
          <DawarichWeb.InsightsLive.NativeMonthly.render
            :if={!@data.all_time}
            path={@path}
            data={Map.put(@data, :monthly, @data.monthly && @data.monthly.source)}
            locale={@locale}
          />
          <Travel.render data={@data} locale={@locale} />
        </div>
      </div>
      <Wellness.render data={@data} locale={@locale} />
    </section>
    """
  end

  attr :data, :map, required: true
  attr :locale, :string, required: true
  attr :query, :map, required: true
  attr :path, :string, required: true

  attr :calendar_mode, :string, default: "both"
  attr :calendar_country, :any, default: nil
  attr :heatmap, :any, default: nil
  attr :unit, :string, default: "km"

  attr :race, :any, default: nil

  def residency(assigns) do
    ~H"""
    <section id="insights-residency-ready" class="contents">
      <DawarichWeb.InsightsLive.NativeYearCalendar.render
        data={@data}
        locale={@locale}
        mode={@calendar_mode}
        country={@calendar_country}
        heatmap={@heatmap}
        unit={@unit}
      />
      <%= if @data.countries != [] && @race do %>
        <div
          class="mb-6 grid gap-6 lg:grid-cols-2 [&>section]:mb-0 [&>section]:min-w-0"
          data-testid="insights-distance-row"
        >
          <DawarichWeb.InsightsLive.NativeCountryRibbon.render data={@data} locale={@locale} />
          <DawarichWeb.InsightsLive.NativeRace.render
            race={@race}
            locale={@locale}
            unit={@unit}
            today={@data.today}
          />
        </div>
      <% else %>
        <DawarichWeb.InsightsLive.NativeCountryRibbon.render
          :if={@data.countries != []}
          data={@data}
          locale={@locale}
        />
        <DawarichWeb.InsightsLive.NativeRace.render
          :if={@race}
          race={@race}
          locale={@locale}
          unit={@unit}
          today={@data.today}
        />
      <% end %>
      <p
        :if={@data.countries == []}
        class="mb-6 text-sm text-base-content/60"
        data-testid="residency-no-countries"
      >
        {t(@locale, "map.residency.show.points_need_reverse_geocoding_to_detect_countries", %{})}
      </p>
      <nav :if={@data.page > 1 || @data.more} class="flex flex-wrap gap-2 min-w-0">
        <.link :if={@data.page > 1} patch={residency_path(@path, @query, @data.page - 1)}>{t(
          @locale,
          "views.pagination.previous",
          %{}
        )}</.link>
        <.link :if={@data.more} patch={residency_path(@path, @query, @data.page + 1)}>{t(
          @locale,
          "views.pagination.next",
          %{}
        )}</.link>
      </nav>
    </section>
    """
  end

  defp residency_path(path, query, page),
    do: path <> "?" <> URI.encode_query(Map.put(query, "residency_page", page))
end

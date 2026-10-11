defmodule DawarichWeb.InsightsLive.NativeParts do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{InsightsParts, HeatmapParts, LocalizedDate}
  alias DawarichWeb.InsightsDetails.{YearComparison, Activity, Locations, Travel, Wellness}

  attr :data, :map, required: true
  attr :query, :map, required: true
  attr :locale, :string, required: true
  attr :path, :string, required: true

  def overview(assigns) do
    ~H"""
    <form id="insights-period" phx-submit="period" class="flex flex-wrap min-w-0 gap-2 my-4">
      <label for="insights-year">{t(@locale, "insights.header.by_year", %{})}</label>
      <select id="insights-year" name="period[year]" class="select max-w-full">
        <option value="all" selected={@data.all_time}>
          {t(@locale, "insights.header.all_time", %{})}
        </option>
        <option :for={year <- @data.available} value={year} selected={year == @data.year}>
          {year}
        </option>
        <option :if={@data.year && @data.year not in @data.available} value={@data.year} selected>
          {@data.year}
        </option>
      </select>
      <label for="insights-month">{t(@locale, "insights.details.monthly_digest", %{})}</label>
      <select id="insights-month" name="period[month]" class="select max-w-full">
        <option value="">{t(@locale, "insights.header.all_time", %{})}</option>
        <option :for={month <- 1..12} value={month} selected={month == @data[:selected_month]}>
          {LocalizedDate.month_name(@locale, @data.year || @data.period.today.year, month)}
        </option>
      </select>
      <button class="btn whitespace-normal" type="submit">{t(
        @locale,
        "javascript.common.confirm",
        %{}
      )}</button>
    </form>
    <nav class="flex flex-wrap gap-2" aria-label={t(@locale, "insights.header.by_year", %{})}>
      <.link :if={@data.period.page > 1} patch={page_path(@path, @query, @data.period.page - 1)}>{t(
        @locale,
        "views.pagination.previous",
        %{}
      )}</.link>
      <.link :if={@data.more} patch={page_path(@path, @query, @data.period.page + 1)}>{t(
        @locale,
        "views.pagination.next",
        %{}
      )}</.link>
    </nav>
    <%= if !@data.year_locked do %>
      <InsightsParts.stats_row
        locale={@locale}
        totals={@data.totals}
        all_time={@data.all_time}
        year={@data.year}
        unit={@data.unit}
      />
      <div :if={!@data.all_time} class="flex flex-wrap min-w-0 gap-4">
        <HeatmapParts.heatmap
          native={true}
          zone={@data.period.zone}
          locale={@locale}
          heatmap={@data.heatmap}
          year={@data.year}
          today={@data.period.today}
          unit={@data.unit}
        />
        <HeatmapParts.streak
          locale={@locale}
          heatmap={@data.heatmap}
          current_year={@data.year == @data.period.today.year}
        />
      </div>
    <% end %>
    """
  end

  attr :kind, :string, required: true
  attr :read, :map, required: true
  attr :locale, :string, required: true
  attr :query, :map, required: true
  attr :path, :string, required: true

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
      class="min-w-0 [&_.card-title]:flex-wrap [&_.card-body]:min-w-0 [&_span]:break-words [&_span]:[overflow-wrap:anywhere]"
    >
      <YearComparison.render data={@data} locale={@locale} />
      <Activity.render data={@data} locale={@locale} />
      <Locations.render data={@data} locale={@locale} />
      <DawarichWeb.InsightsLive.NativeMonthly.render
        :if={!@data.all_time}
        data={Map.put(@data, :monthly, @data.monthly && @data.monthly.source)}
        locale={@locale}
      />
      <Travel.render data={@data} locale={@locale} />
      <Wellness.render data={@data} locale={@locale} />
    </section>
    """
  end

  attr :data, :map, required: true
  attr :locale, :string, required: true
  attr :query, :map, required: true
  attr :path, :string, required: true

  def residency(assigns) do
    ~H"""
    <section id="insights-residency-ready" class="min-w-0 my-4">
      <h2 class="text-xl break-words">{t(@locale, "map.residency.show.days_per_country", %{})}</h2>
      <p>{@data.total} / {if(Calendar.ISO.leap_year?(@data.year), do: 366, else: 365)}</p>
      <DawarichWeb.InsightsLive.NativeResidencyCalendar.render data={@data} locale={@locale} />
      <p :if={@data.countries == []} class="break-words">
        {t(@locale, "map.residency.show.no_country_data_for", %{})} {@data.year}
      </p>
      <details :for={country <- @data.countries} class="min-w-0 my-2">
        <summary class="flex flex-wrap min-w-0 gap-2 [overflow-wrap:anywhere]">
          <DawarichWeb.Icon.flag
            :if={country.iso}
            code={String.downcase(country.iso)}
            class="w-6 h-4"
          /> {country.name} {country.days} ({country.year_percentage}%)
          <span :if={country.warning}>{t(
            @locale,
            "map.residency.show.exceeds_183_day_threshold_common_in_many_tax_jurisdictions",
            %{}
          )}</span>
        </summary>
        <p :for={{first, last} <- country.periods} class="break-words">
          {LocalizedDate.l(@locale, first, "medium")} – {LocalizedDate.l(@locale, last, "medium")} · {Date.diff(
            last,
            first
          ) + 1} {t(@locale, "map.residency.show.days", %{})}
        </p>
      </details>
      <nav class="flex flex-wrap gap-2 min-w-0">
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

  defp page_path(path, query, page),
    do: path <> "?" <> URI.encode_query(Map.put(query, "page", page))

  defp residency_path(path, query, page),
    do: path <> "?" <> URI.encode_query(Map.put(query, "residency_page", page))
end

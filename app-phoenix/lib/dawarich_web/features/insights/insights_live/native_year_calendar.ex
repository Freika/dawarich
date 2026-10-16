defmodule DawarichWeb.InsightsLive.NativeYearCalendar do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{LocalizedDate, StatsFormat}
  attr :data, :map, required: true
  attr :heatmap, :any, default: nil
  attr :locale, :string, required: true
  attr :mode, :string, default: "both"
  attr :country, :any, default: nil
  attr :unit, :string, default: "km"

  def render(assigns) do
    first = Date.new!(assigns.data.year, 1, 1)

    assigns =
      assign(assigns,
        dates: Enum.to_list(Date.range(first, Date.new!(first.year, 12, 31))),
        daily: Map.new(assigns.data.daily, fn [date, country] -> {date, country} end),
        lanes: Enum.take(assigns.data.countries, 8)
      )

    ~H"""
    <section
      data-testid="year-calendar"
      data-mode={@mode}
      data-country={@country}
      class="min-w-0 my-4"
    >
      <h3>{t(@locale, "insights.activity_heatmap.activity_overview", %{})}</h3>
      <div
        :if={@data.countries != []}
        role="group"
        aria-label={t(@locale, "insights.year_calendar.mode", %{})}
        class="flex flex-wrap gap-2"
      >
        <button
          :for={mode <- ~w(both distance countries)}
          phx-click="calendar_mode"
          phx-value-mode={mode}
          aria-pressed={to_string(mode == @mode)}
          class="btn btn-sm"
        >{t(@locale, "insights.year_calendar.mode_#{mode}", %{})}</button>
      </div>
      <div
        :if={@data.countries != []}
        role="group"
        aria-label={t(@locale, "map.residency.show.days_per_country", %{})}
        class="flex flex-wrap gap-2"
      >
        <button
          :for={country <- @data.countries}
          phx-click="calendar_country"
          phx-value-country={country.name}
          aria-pressed={to_string(country.name == @country)}
          class="btn btn-sm"
        >{country.name} {country.days}</button>
      </div>
      <div class="grid grid-cols-7 gap-1" role="list">
        <div
          :for={date <- @dates}
          :if={Date.compare(date, @data[:today] || Date.new!(@data.year, 12, 31)) != :gt}
          role="listitem"
          data-residency-day={Date.to_iso8601(date)}
          data-country={@daily[date]}
          aria-label={label(@locale, date, @daily[date], meters(@heatmap, date), @unit, @mode)}
          title={label(@locale, date, @daily[date], meters(@heatmap, date), @unit, @mode)}
          class={"rounded p-1 text-xs min-w-0 break-words #{if @country && @country != @daily[date], do: "opacity-30", else: ""} #{if active?(@mode,@daily[date],meters(@heatmap,date)), do: "bg-primary/20", else: "bg-base-200"}"}
        >
          <time datetime={Date.to_iso8601(date)}>{LocalizedDate.l(@locale, date, "short_month_day")}</time>
          <span :if={@mode != "distance"}>{@daily[date]}</span>
          <span :if={@mode != "countries" && meters(@heatmap, date) > 0}>{StatsFormat.distance(
            @locale,
            meters(@heatmap, date),
            @unit
          )}</span>
        </div>
      </div>
      <p :if={@data[:zone] not in [nil, "UTC", "Etc/UTC"]} data-testid="year-calendar-timezone-note">
        {t(@locale, "insights.year_calendar.timezone_note", %{zone: @data.zone})}
      </p>
    </section>
    <section :if={@lanes != []} data-testid="country-ribbon" class="min-w-0 my-4">
      <h3>{t(@locale, "insights.country_ribbon.title", %{year: @data.year})}</h3>
      <div :for={country <- @lanes} data-testid="country-ribbon-lane" class="my-2 min-w-0">
        <h4>{country.name} · {country.days}</h4>
        <div class="relative h-8 bg-base-200 rounded">
          <span
            :for={{first, last} <- country.periods}
            role="img"
            tabindex="0"
            style={segment_style(first, last, @data.year)}
            class="absolute h-6 rounded bg-primary/50"
            aria-label={segment(@locale, country.name, first, last)}
            title={segment(@locale, country.name, first, last)}
          >{LocalizedDate.l(@locale, first, "short_month_day")} – {LocalizedDate.l(
            @locale,
            last,
            "short_month_day"
          )}</span>
        </div>
      </div>
      <p :if={(@data[:country_count] || length(@data.countries)) > length(@lanes)}>
        {t(@locale, "insights.country_ribbon.more_countries", %{
          count: (@data[:country_count] || length(@data.countries)) - length(@lanes)
        })}
      </p>
    </section>
    """
  end

  defp segment_style(first, last, year) do
    start = Date.new!(year, 1, 1)
    size = if Calendar.ISO.leap_year?(year), do: 366, else: 365
    first = Enum.max([first, start], Date)
    last = Enum.min([last, Date.new!(year, 12, 31)], Date)

    "left: #{Date.diff(first, start) / size * 100}%; width: #{max(Date.diff(last, first) + 1, 1) / size * 100}%;"
  end

  defp meters(nil, _), do: 0
  defp meters(heatmap, date), do: Map.get(heatmap.daily, Date.to_iso8601(date), 0)
  defp active?("countries", country, _), do: not is_nil(country)
  defp active?("distance", _, meters), do: meters > 0
  defp active?(_, country, meters), do: country != nil or meters > 0

  defp label(locale, date, country, meters, unit, mode),
    do:
      Enum.join(
        Enum.reject(
          [
            LocalizedDate.l(locale, date, "medium"),
            if(mode != "distance", do: country),
            if(mode != "countries", do: StatsFormat.distance(locale, meters, unit))
          ],
          &is_nil/1
        ),
        ": "
      )

  defp segment(locale, country, first, last),
    do:
      t(locale, "insights.country_ribbon.segment", %{
        country: country,
        from: LocalizedDate.l(locale, first, "short_month_day"),
        to: LocalizedDate.l(locale, last, "short_month_day"),
        count: Date.diff(last, first) + 1
      })
end

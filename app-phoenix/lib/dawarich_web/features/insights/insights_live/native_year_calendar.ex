defmodule DawarichWeb.InsightsLive.NativeYearCalendar do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  alias Dawarich.Insights.Heatmap
  alias DawarichWeb.LocalizedDate
  alias DawarichWeb.InsightsLive.{NativeCalendarData, NativeCalendarControls}
  attr :data, :map, required: true
  attr :heatmap, :any, default: nil
  attr :locale, :string, required: true
  attr :mode, :string, default: "both"
  attr :country, :any, default: nil
  attr :unit, :string, default: "km"

  def render(assigns) do
    heatmap = assigns.heatmap || Heatmap.build([], assigns.data.year, assigns.data.today)
    weeks = Heatmap.weeks(assigns.data.year)

    assigns =
      assign(assigns,
        heatmap: heatmap,
        weeks: weeks,
        labels: Heatmap.month_labels(weeks, assigns.data.year, assigns.locale),
        cells:
          NativeCalendarData.cells(
            assigns.data,
            heatmap,
            assigns.locale,
            assigns.unit,
            assigns.country,
            if(assigns.data.countries == [], do: "distance", else: assigns.mode)
          ),
        colors: NativeCalendarData.colors(assigns.data.countries)
      )

    ~H"""
    <section
      class="card bg-base-200 mb-6"
      data-testid="year-calendar"
      aria-labelledby="year-calendar-title"
      id="native-year-calendar"
      phx-hook="InsightsCalendar"
      data-native-target-date={Heatmap.most_recent(@heatmap.daily)}
      data-native-no-data={t(@locale, "insights.year_calendar.no_data", %{})}
    >
      <div class="card-body p-5 gap-4">
        <div class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
          <h2 id="year-calendar-title" class="flex items-center gap-2 text-xl font-bold min-w-0">
            <.icon name="calendar" class="w-5 h-5 text-base-content/60 shrink-0" /> {t(
              @locale,
              "insights.activity_heatmap.activity_overview",
              %{}
            )}
          </h2>
          <p
            class="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-base-content/70"
            data-testid="year-calendar-streaks"
          >
            <span><strong class="text-base-content tabular-nums">{@heatmap.active_days}</strong> {t(
              @locale,
              "insights.activity_heatmap.active_days",
              %{}
            )}</span>
            <span>
              {t(@locale, "insights.activity_streak.longest_streak", %{})}:
              <strong class="text-base-content tabular-nums">{@heatmap.longest_streak} {t(
                @locale,
                "insights.activity_streak.day",
                %{count: @heatmap.longest_streak}
              )}</strong>
              <span :if={@heatmap.longest_start && @heatmap.longest_end} class="text-base-content/50">({LocalizedDate.l(
                @locale,
                @heatmap.longest_start,
                "short_month_day"
              )} – {LocalizedDate.l(@locale, @heatmap.longest_end, "short_month_day")})</span>
            </span>
            <span><strong class="text-base-content tabular-nums">{@heatmap.current_streak} {t(
              @locale,
              "insights.activity_streak.day",
              %{count: @heatmap.current_streak}
            )}</strong> {t(@locale, "insights.activity_streak.current", %{})}</span>
          </p>
        </div>
        <div class={"grid gap-5 items-start #{if @data.countries != [], do: "lg:grid-cols-[minmax(0,1fr)_14rem]"}"}>
          <div class="relative min-w-0">
            <div class="overflow-x-auto" data-native-calendar-scroller>
              <div
                class="year-calendar mx-auto pb-1"
                style={"--weeks: #{length(@weeks)}"}
                data-mode={if @data.countries == [], do: "distance", else: @mode}
                data-focus={@country}
              >
                <div class="year-calendar__months" aria-hidden="true">
                  <span :for={label <- @labels} style={"grid-column: #{label.index + 2} / span 4"}>{label.name}</span>
                </div>
                <div class="year-calendar__body">
                  <span
                    :for={day <- ["mon", nil, "wed", nil, "fri", nil, nil]}
                    class="year-calendar__day"
                    aria-hidden="true"
                  >{day && t(@locale, "insights.activity_heatmap." <> day, %{})}</span>
                  <i
                    :for={cell <- @cells}
                    class={cell.class}
                    {if cell.style, do: %{style: cell.style}, else: %{}}
                    role={if cell.date, do: "img"}
                    aria-label={cell.aria}
                    data-date={cell.date}
                    data-label={cell.label}
                    data-distance={cell.distance}
                    data-country={cell.country}
                  ></i>
                </div>
              </div>
            </div>
            <div
              class="mt-2 flex items-center justify-end gap-1.5 text-xs text-base-content/60"
              aria-hidden="true"
            >
              <span>{t(@locale, "insights.activity_heatmap.less", %{})}</span>
              <i
                :for={alpha <- [0.32, 0.5, 0.72, 1]}
                class="year-calendar__swatch"
                style={"--a: #{alpha}"}
              ></i>
              <span>{t(@locale, "insights.activity_heatmap.more", %{})}</span>
            </div>
            <div
              data-native-calendar-tooltip
              class="hidden absolute z-10 pointer-events-none rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-xs shadow-lg"
            >
              <div data-native-tooltip-date class="font-semibold"></div>
              <div data-native-tooltip-detail class="text-base-content/70"></div>
            </div>
          </div>
          <NativeCalendarControls.render
            :if={@data.countries != []}
            data={@data}
            colors={@colors}
            mode={@mode}
            country={@country}
            locale={@locale}
          />
        </div>
      </div>
    </section>
    """
  end
end

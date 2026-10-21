defmodule DawarichWeb.InsightsLive.NativeRace do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{LocalizedDate, NumberFormat, InsightsLive.NativeRaceChart}
  attr :race, :map, required: true
  attr :locale, :string, required: true
  attr :unit, :string, required: true
  attr :today, Date, required: true

  def render(assigns) do
    chart = NativeRaceChart.build(assigns.race, assigns.unit, assigns.locale)

    same_day =
      chart.previous &&
        Enum.at(chart.previous, min(length(chart.current) - 1, length(chart.previous) - 1))

    assigns =
      assign(assigns,
        chart: chart,
        same_day: same_day,
        percent:
          if(same_day && same_day > 0,
            do: round((List.last(chart.current) - same_day) / same_day * 100)
          )
      )

    ~H"""
    <section
      class="card bg-base-200 mb-6"
      data-testid="distance-race"
      aria-labelledby="distance-race-title"
      id="native-distance-race"
      phx-hook="InsightsRace"
      data-native-current={Jason.encode!(@chart.current)}
      data-native-previous={Jason.encode!(@chart.previous || [])}
      data-native-year={@race.year}
      data-native-unit={@unit}
    >
      <div class="card-body p-5 gap-4">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 id="distance-race-title" class="text-xl font-bold min-w-0">
            {t(
              @locale,
              if(@chart.previous,
                do: "insights.distance_race.title",
                else: "insights.distance_race.title_single"
              ),
              %{year: @race.year, previous: @race.year - 1}
            )}
          </h2>
          <div class="flex flex-wrap items-center gap-4 text-xs text-base-content/60">
            <span class="flex items-center gap-1.5"><span class="inline-block h-2.5 w-2.5 rounded-sm bg-primary"></span>{@race.year}</span>
            <span :if={@chart.previous} class="flex items-center gap-1.5"><span class="inline-block h-0.5 w-3 border-t-2 border-dashed border-base-content/40"></span>{@race.year -
              1}</span>
          </div>
        </div>
        <div class="grid gap-5">
          <div class="relative min-w-0">
            <div class="overflow-x-auto">
              <svg
                viewBox="0 0 720 240"
                class="block w-full min-w-[34rem] h-auto overflow-visible"
                role="img"
                aria-label={
                  t(@locale, "insights.distance_race.aria", %{
                    year: @race.year,
                    previous: @race.year - 1
                  })
                }
                data-native-race-svg
              >
                <defs>
                  <linearGradient id={"race-fill-#{@race.year}"} x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0" stop-color="oklch(var(--p))" stop-opacity="0.22" /><stop
                      offset="1"
                      stop-color="oklch(var(--p))"
                      stop-opacity="0"
                    />
                  </linearGradient>
                </defs>
                <%= for {label, ty} <- @chart.ticks do %>
                  <line x1="46" x2="708" y1={ty} y2={ty} stroke="oklch(var(--bc) / 0.1)" />
                  <text
                    x="38"
                    y={ty + 4}
                    text-anchor="end"
                    font-size="10.5"
                    fill="oklch(var(--bc) / 0.55)"
                  >
                    {label}
                  </text>
                <% end %>
                <text
                  :for={{label, mx} <- @chart.months}
                  x={mx + 2}
                  y="232"
                  font-size="10.5"
                  fill="oklch(var(--bc) / 0.55)"
                >
                  {label}
                </text>
                <path
                  :if={@chart.previous}
                  d={@chart.previous_path}
                  fill="none"
                  stroke="oklch(var(--bc) / 0.4)"
                  stroke-width="2"
                  stroke-dasharray="4 4"
                  data-race-line="previous"
                />
                <path d={@chart.area_path} fill={"url(#race-fill-#{@race.year})"} />
                <path
                  d={@chart.current_path}
                  fill="none"
                  stroke="oklch(var(--p))"
                  stroke-width="2.6"
                  stroke-linejoin="round"
                  data-race-line="current"
                />
                <%= if @chart.previous do %>
                  <line
                    x1={@chart.today_x}
                    x2={@chart.today_x}
                    y1={@chart.today_current_y}
                    y2={@chart.today_previous_y}
                    stroke={if @race.lead >= 0, do: "oklch(var(--su))", else: "oklch(var(--wa))"}
                    stroke-width="2"
                  />
                  <circle
                    cx={@chart.today_x}
                    cy={@chart.today_previous_y}
                    r="3.5"
                    fill="oklch(var(--bc) / 0.4)"
                  />
                <% end %>
                <circle
                  cx={@chart.today_x}
                  cy={@chart.today_current_y}
                  r="5"
                  fill="oklch(var(--p))"
                  stroke="oklch(var(--b2))"
                  stroke-width="2"
                />
                <g data-native-race-hover visibility="hidden">
                  <line data-native-race-hover-line y1="12" y2="214" stroke="oklch(var(--bc) / 0.35)" />
                </g>
                <rect x="46" y="12" width="662" height="202" fill="transparent" data-native-race-hit />
              </svg>
            </div>
            <div
              data-native-race-tooltip
              class="hidden absolute z-10 pointer-events-none rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-xs tabular-nums shadow-lg"
            >
              <div data-native-tooltip-date class="font-semibold"></div><div data-native-tooltip-current>
              </div><div data-native-tooltip-previous class="text-base-content/60"></div>
            </div>
          </div>
          <div class="grid gap-3 sm:grid-cols-2">
            <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
              <div class="text-[11px] font-bold uppercase tracking-wider text-base-content/60">
                {t(@locale, "insights.distance_race.so_far", %{year: @race.year})}
              </div>
              <div class="text-2xl font-extrabold tabular-nums">
                {distance(@locale, List.last(@chart.current), @unit)}
              </div>
              <div class="text-xs text-base-content/60">
                {t(@locale, "insights.distance_race.by_date", %{
                  date: LocalizedDate.l(@locale, @race.last_date, "short_month_day")
                })}
              </div>
            </div>
            <%= if @chart.previous do %>
              <div class="rounded-xl border border-base-300 bg-base-100 px-4 py-3">
                <div class="text-[11px] font-bold uppercase tracking-wider text-base-content/60">
                  {t(@locale, "insights.distance_race.same_day", %{year: @race.year - 1})}
                </div>
                <div class="text-2xl font-extrabold tabular-nums">
                  {distance(@locale, @same_day, @unit)}
                </div>
                <div class="text-xs text-base-content/60">
                  {t(@locale, "insights.distance_race.ended_at", %{
                    year: @race.year - 1,
                    distance: distance(@locale, List.last(@chart.previous), @unit)
                  })}
                </div>
              </div>
              <span
                data-testid="distance-race-lead"
                class={"badge #{if @race.lead >= 0, do: "badge-success", else: "badge-warning"} badge-outline justify-self-start whitespace-normal h-auto py-1 sm:col-span-2"}
              >
                {t(
                  @locale,
                  if(@race.lead >= 0,
                    do: "insights.distance_race.ahead",
                    else: "insights.distance_race.behind"
                  ),
                  %{
                    distance:
                      distance(@locale, Dawarich.Distance.convert(abs(@race.lead), @unit), @unit)
                  }
                )}{if @percent, do: " (#{if @percent > 0, do: "+"}#{@percent}%)"}
              </span>
            <% else %>
              <p class="text-sm text-base-content/60 sm:self-center">
                {t(@locale, "insights.distance_race.no_previous", %{year: @race.year - 1})}
              </p>
            <% end %>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp distance(locale, value, unit),
    do: NumberFormat.delimited(locale, round(value)) <> " " <> unit
end

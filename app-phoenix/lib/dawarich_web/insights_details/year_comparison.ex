defmodule DawarichWeb.InsightsDetails.YearComparison do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{Icon, LocalizedDate, NumberFormat}
  alias DawarichWeb.InsightsDetails.Format

  def render(assigns) do
    data = assigns.data
    comparison = data.comparison

    assigns =
      assign(assigns,
        previous: comparison && comparison.previous,
        metrics:
          if(comparison,
            do: [
              %{
                name: "distance",
                color: "primary",
                current: data.totals.distance,
                before: comparison.previous.distance,
                change: comparison.distance_change
              },
              %{
                name: "countries",
                color: "secondary",
                current: data.totals.countries,
                before: comparison.previous.countries,
                change: comparison.countries_change
              },
              %{
                name: "days",
                color: "accent",
                current: data.totals.days,
                before: comparison.previous.days,
                change: comparison.days_change
              }
            ],
            else: []
          )
      )

    ~H"""
    <div :if={@data.comparison} class="card bg-base-200">
      <div class="card-body p-5">
        <h2 class="card-title text-lg flex items-center gap-2">
          <Icon.icon name="git-compare" class="w-5 h-5 text-primary" />
          {tr(@locale, "your_journey")} {@data.year} {tr(@locale, "vs")} {@data.year - 1}
        </h2>
        <div :for={metric <- @metrics} class="mt-4">
          <div class="flex justify-between text-sm mb-1">
            <span class="font-medium">{tr(
              @locale,
              if(metric.name == "days", do: "days_traveling", else: metric.name)
            )}</span>
            <span :if={metric.change != 0} class={"text-" <> Format.color(metric.change)}>{difference(
              @locale,
              metric,
              @data.unit
            )}</span>
          </div>
          <div
            class="flex items-center gap-2 text-sm mb-1"
            data-comparison-metric={metric.name}
            data-comparison-year="current"
          >
            <span class="w-10">{@data.year}</span>
            <progress
              class={"progress progress-#{metric.color} flex-1 h-3"}
              value={Format.percentage(metric.current, metric.before)}
              max="100"
            ></progress>
            <span class="w-24 text-right">{value(@locale, metric.name, metric.current, @data.unit)}</span>
          </div>
          <div
            class="flex items-center gap-2 text-sm"
            data-comparison-metric={metric.name}
            data-comparison-year="previous"
          >
            <span class="w-10">{@data.year - 1}</span>
            <div class="flex-1 h-3 bg-base-300 rounded-full overflow-hidden">
              <div
                data-comparison-bar
                class="h-full rounded-full bg-warning"
                style={"width: #{Format.percentage(metric.before, metric.current)}%"}
              >
              </div>
            </div>
            <span class="w-24 text-right">{value(@locale, metric.name, metric.before, @data.unit)}</span>
          </div>
        </div>
        <div
          :if={@data.totals.biggest_month || @previous.biggest_month}
          class="mt-4 pt-4 border-t border-base-300"
        >
          <div class="text-sm font-medium text-base-content/60 mb-2">
            {tr(@locale, "biggest_month")}
          </div>
          <div :if={@data.totals.biggest_month} class="text-sm">
            {@data.year}:
            <span class="text-primary">{month_name(@locale, @data.totals.biggest_month)}</span>
            ({NumberFormat.delimited(@locale, @data.totals.biggest_month.distance)} {@data.unit})
          </div>
          <div :if={@previous.biggest_month} class="text-sm">
            {@data.year - 1}:
            <span class="text-warning">{month_name(@locale, @previous.biggest_month)}</span>
            ({NumberFormat.delimited(@locale, @previous.biggest_month.distance)} {@data.unit})
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp tr(locale, key), do: Format.translation(locale, "year_comparison", key)
  defp value(locale, "distance", n, unit), do: NumberFormat.delimited(locale, n) <> " " <> unit
  defp value(locale, "days", n, _unit), do: "#{n} " <> tr(locale, "days_2")
  defp value(_locale, "countries", n, _unit), do: to_string(n)

  defp difference(locale, %{name: "distance"} = m, unit),
    do:
      (Format.signed(m.current - m.before) <> " #{unit} (" <> Format.signed(m.change) <> "%)")
      |> delimited_difference(locale)

  defp difference(_locale, %{name: "countries"} = m, _unit), do: Format.signed(m.change)

  defp difference(locale, m, _unit),
    do:
      Format.signed(m.current - m.before) <>
        " " <> tr(locale, "days") <> Format.signed(m.change) <> "%)"

  defp delimited_difference(text, locale),
    do:
      Regex.replace(~r/^([+-]?)(\d+)/, text, fn _, sign, n ->
        sign <> NumberFormat.delimited(locale, String.to_integer(n))
      end)

  defp month_name(locale, month), do: LocalizedDate.month_name(locale, month.year, month.month)
end

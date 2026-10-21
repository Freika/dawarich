defmodule DawarichWeb.InsightsLive.NativeMonths do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  alias Dawarich.Analytics.Period
  alias DawarichWeb.{LocalizedDate, NumberFormat}

  @colors ~w(#397bb5 #5A4E9D #3B945E #7BC96F #FFD54F #FFA94D #FF6B6B #FF8C42 #C97E4F #8B4513 #5A2E2E #265d7d)
  attr :data, :map, required: true
  attr :locale, :string, required: true

  def render(assigns) do
    assigns =
      assign(
        assigns,
        :longest,
        Enum.max(Enum.map(assigns.data.consolidated.months, & &1.distance))
      )

    ~H"""
    <section class="card bg-base-200 mb-6" aria-labelledby="insights-months-title">
      <div class="card-body p-5 gap-4">
        <h2 id="insights-months-title" class="text-xl font-bold">
          {t(@locale, "insights.months.title", %{})}
        </h2>
        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-3">
          <%= for month <- @data.consolidated.months do %>
            <div
              :if={month.empty}
              data-testid="insights-month"
              data-empty="true"
              class="rounded-lg border border-dashed border-base-300 px-3 py-2.5 text-base-content/40"
            >
              <div class="truncate text-sm font-medium">
                {LocalizedDate.month_name(@locale, @data.year, month.month)}
              </div>
              <div class="mt-1 text-lg font-semibold">—</div>
              <div class="text-xs" aria-hidden="true">&nbsp;</div>
              <div class="mt-2 h-1 rounded-full bg-base-300/60" aria-hidden="true"></div>
            </div>
            <.link
              :if={!month.empty}
              navigate={"/stats/#{@data.year}/#{month.month}"}
              data-testid="insights-month"
              data-empty="false"
              class="group block min-w-0 rounded-lg border border-base-300 bg-base-100 px-3 py-2.5 transition-colors hover:border-primary/40"
            >
              <div
                class="flex items-center gap-1.5 text-sm font-medium"
                style={"color: #{color(month.month)};"}
              >
                <.icon name={month_icon(month.month)} class="w-4 h-4 shrink-0" />
                <span class="truncate">{LocalizedDate.month_name(@locale, @data.year, month.month)}</span>
              </div>
              <div class="mt-1 text-lg font-semibold tabular-nums text-base-content">
                {NumberFormat.delimited(@locale, Period.rounded(month.distance, @data.unit))}
                <span class="text-xs font-normal text-base-content/60">{@data.unit}</span>
              </div>
              <div
                class="truncate text-xs text-base-content/60"
                title={locations(@locale, month.toponyms)}
              >
                {locations(@locale, month.toponyms)}
              </div>
              <div class="mt-2 h-1 overflow-hidden rounded-full bg-base-300" aria-hidden="true">
                <div
                  class="h-full rounded-full"
                  style={"width: #{share(month.distance, @longest)}%; background-color: #{color(month.month)};"}
                >
                </div>
              </div>
            </.link>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  defp color(month), do: Enum.at(@colors, month - 1)
  defp month_icon(month) when month in [1, 2, 12], do: "snowflake"
  defp month_icon(month) when month in 3..5, do: "flower"
  defp month_icon(month) when month in 6..8, do: "tree-palm"
  defp month_icon(_), do: "leaf"

  defp share(distance, longest),
    do:
      Dawarich.RubyFloat.round(
        max(3.0, min(100.0, if(longest > 0, do: distance / longest * 100, else: 0))),
        1
      )

  defp locations(locale, toponyms) do
    places = Enum.filter(toponyms, &(&1["country"] not in [nil, ""]))

    t(locale, "helpers.stats.countries_and_cities", %{
      countries: places |> Enum.map(& &1["country"]) |> Enum.uniq() |> length(),
      cities: Enum.sum(Enum.map(places, &length(&1["cities"] || [])))
    })
  end
end

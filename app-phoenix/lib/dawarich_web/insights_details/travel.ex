defmodule DawarichWeb.InsightsDetails.Travel do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.{RubyFloat}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.{Icon, StatsFormat}
  alias DawarichWeb.InsightsDetails.{Format, TravelInsight}

  def render(assigns) do
    {:ok, days} = Dawarich.I18n.t(assigns.locale, "date.abbr_day_names")
    days = tl(days) ++ [hd(days)]

    assigns =
      assign(assigns,
        days: days,
        max: Enum.max(assigns.data.weekly),
        insight: TravelInsight.generate(assigns.locale, assigns.data),
        periods: [
          {"night", "00-06"},
          {"morning", "06-12"},
          {"afternoon", "12-18"},
          {"evening", "18-24"}
        ],
        seasons: [
          {"winter", "info"},
          {"spring", "success"},
          {"summer", "warning"},
          {"fall", "error"}
        ]
      )

    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-5">
        <h2 class="card-title text-lg flex items-center gap-2">
          <Icon.icon name="clock" class="w-5 h-5 text-primary" /> {tr(@locale, "when_do_you_travel")}
        </h2>
        <div class="mt-3">
          <div class="text-sm font-medium mb-2">{tr(@locale, "time_of_day_distribution")}</div><div class="space-y-1">
            <div :for={{period, label} <- @periods} class="flex items-center gap-2 text-xs">
              <span class="w-12 text-base-content/60">{label}</span>
              <progress
                class="progress progress-info flex-1 h-2"
                value={@data.time_of_day[period] || 0}
                max="100"
              ></progress>
              <span class="w-8 text-right text-base-content/60">{@data.time_of_day[period] ||
                0}%</span>
            </div>
          </div>
        </div>
        <div class="grid grid-cols-2 gap-4 mt-4">
          <div>
            <div class="text-sm font-medium mb-2">{tr(@locale, "day_of_week")}</div><div class="flex gap-1">
              <div
                :for={{meters, index} <- Enum.with_index(@data.weekly)}
                class="flex-1 bg-info text-info-content rounded text-center py-1"
                style={"opacity: #{opacity(meters, @max)}"}
              >
                <div class="text-xs font-medium">{Enum.at(@days, index)}</div><div class="text-xs">
                  {human(StatsFormat.convert(meters, @data.unit))}
                </div>
              </div>
            </div>
          </div>
          <div>
            <div class="text-sm font-medium mb-2">{tr(@locale, "seasonality")}</div><div class="space-y-1 text-sm">
              <div :for={{season, color} <- @seasons} class="flex items-center gap-2">
                <span class="w-14 capitalize">{t(
                  @locale,
                  "services.insights.travel_insight_generator.seasons." <> season,
                  %{}
                )}</span>
                <progress
                  class={"progress progress-#{color} flex-1 h-2"}
                  value={@data.seasonality[season] || 0}
                  max="100"
                ></progress>
                <span class="w-10 text-right text-base-content/60">{@data.seasonality[
                  season
                ] || 0}%</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    <div :if={@insight} class="alert bg-warning/20 border border-warning/30">
      <div class="flex items-start gap-3">
        <Icon.icon name="lightbulb" class="w-5 h-5 text-warning" /><div>
          <h3 class="font-bold text-warning">{tr(@locale, "insight")}</h3><div class="text-sm">
            {@insight}
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp tr(locale, key), do: Format.translation(locale, "travel_patterns", key)
  defp opacity(_meters, 0), do: "0.4"
  defp opacity(meters, max), do: Ruby.to_s(RubyFloat.round(0.4 + meters / max * 0.6, 2))

  defp human(n) do
    cond do
      abs(n) >= 1_000_000 -> "#{round(n / 1_000_000)}M"
      abs(n) >= 1000 -> "#{round(n / 1000)}k"
      true -> to_string(round(n))
    end
  end
end

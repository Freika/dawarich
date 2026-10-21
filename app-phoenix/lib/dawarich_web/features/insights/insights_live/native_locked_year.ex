defmodule DawarichWeb.InsightsLive.NativeLockedYear do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{StatsFormat, Icon}
  attr :year, :integer, required: true
  attr :unit, :string, required: true
  attr :locale, :string, required: true

  def render(assigns) do
    ~H"""
    <div class="card w-full bg-base-200 shadow-xl" data-testid="insights-locked-year">
      <div class="card-body">
        <h2 class={"card-title justify-between text-#{StatsFormat.header_color(@year)}"}>
          <div>{@year}</div>
          <a
            href="#"
            phx-click="upgrade"
            target="_blank"
            rel="noopener noreferrer"
            class="tooltip tooltip-bottom"
            data-tip={t(@locale, "helpers.application.pro_only", %{})}
            tabindex="0"
          ><span class="badge badge-sm badge-outline gap-1"><Icon.icon name="lock" class="w-3 h-3" />{t(
            @locale,
            "helpers.application.pro_badge",
            %{}
          )}</span></a>
        </h2>
        <div class="relative">
          <div class="opacity-20 blur-[3px] pointer-events-none select-none" aria-hidden="true">
            <DawarichWeb.NativeChart.chart
              id={"chart-year-locked-#{@year}"}
              height="200px"
              data={
                for month <- 1..12,
                    do: [
                      DawarichWeb.LocalizedDate.month_name(@locale, @year, month),
                      5000 + rem(month * 7919, 75000)
                    ]
              }
              revision={to_string(@year)}
              label={to_string(@year)}
              rails
              options={%{suffix: " " <> @unit, colors: DawarichWeb.YearCards.month_colors()}}
            />
          </div>
          <div class="absolute inset-0 flex flex-col items-center justify-center">
            <Icon.icon name="lock" class="w-6 h-6 opacity-30" />
            <p class="text-sm text-base-content/50 mt-1">
              {t(@locale, "stats.locked_year_card.available_on_pro", %{})}
            </p>
            <a
              href="#"
              phx-click="upgrade"
              class="btn btn-sm btn-primary mt-2"
              target="_blank"
              rel="noopener"
            >{t(
              @locale,
              "stats.locked_year_card.upgrade_to_pro",
              %{}
            )}</a>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

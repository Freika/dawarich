defmodule DawarichWeb.InsightsLive.NativeCalendarControls do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  attr :data, :map, required: true
  attr :colors, :map, required: true
  attr :locale, :string, required: true
  attr :mode, :string, required: true
  attr :country, :any, default: nil

  def render(assigns) do
    ~H"""
    <div class="grid gap-3 content-start">
      <div
        class="seg-vertical flex flex-col rounded-lg border border-base-300 bg-base-100 p-1"
        role="group"
        aria-label={t(@locale, "insights.year_calendar.mode", %{})}
      >
        <button
          :for={mode <- ~w(both distance countries)}
          type="button"
          class="btn btn-sm btn-ghost justify-start font-medium aria-pressed:btn-active"
          aria-pressed={to_string(mode == @mode)}
          data-mode={mode}
          phx-click="calendar_mode"
          phx-value-mode={mode}
        >
          {t(@locale, "insights.year_calendar.mode_#{mode}", %{})}
        </button>
      </div>
      <div class="grid gap-0.5" data-testid="year-calendar-countries">
        <button
          :for={country <- @data.countries}
          type="button"
          class="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm hover:bg-base-100 aria-pressed:bg-base-100"
          aria-pressed={to_string(country.name == @country)}
          data-country={country.name}
          phx-click="calendar_country"
          phx-value-country={country.name}
        >
          <span class="h-2.5 w-2.5 shrink-0 rounded-sm" style={"background: #{@colors[country.name]}"}></span>
          <span class="min-w-0 flex-1 truncate">{country.name}<.icon
            :if={country.warning}
            name="triangle-alert"
            class="w-3.5 h-3.5 inline text-warning ml-0.5"
          /></span>
          <span class="shrink-0 tabular-nums text-base-content/60">{country.days}</span>
        </button>
      </div>
      <p
        :if={Enum.any?(@data.countries, & &1.warning)}
        class="flex items-start gap-1.5 text-xs text-base-content/60"
      >
        <.icon name="triangle-alert" class="w-3.5 h-3.5 text-warning shrink-0 mt-0.5" />
        <span>{t(
          @locale,
          "map.residency.show.exceeds_183_day_threshold_common_in_many_tax_jurisdictions",
          %{}
        )}</span>
      </p>
      <p class="text-xs text-base-content/50">
        {t(
          @locale,
          "map.residency.show.distinct_days_with_at_least_one_tracked_point_per_country",
          %{}
        )}
      </p>
      <p
        :if={@data.zone not in ["UTC", "Etc/UTC"]}
        class="text-xs text-base-content/50"
        data-testid="year-calendar-timezone-note"
      >
        {t(@locale, "insights.year_calendar.timezone_note", %{zone: @data.zone})}
      </p>
    </div>
    """
  end
end

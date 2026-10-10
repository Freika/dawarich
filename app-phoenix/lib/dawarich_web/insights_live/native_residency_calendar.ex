defmodule DawarichWeb.InsightsLive.NativeResidencyCalendar do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.LocalizedDate
  attr :data, :map, required: true
  attr :locale, :string, required: true

  def render(assigns) do
    first = Date.new!(assigns.data.year, 1, 1)
    last = Date.new!(assigns.data.year, 12, 31)

    assigns =
      assign(assigns,
        dates: Enum.to_list(Date.range(first, last)),
        daily: Map.new(assigns.data.daily, fn [date, country] -> {date, country} end)
      )

    ~H"""
    <details :if={@data.total > 0} class="min-w-0 my-4">
      <summary class="break-words">
        {t(
          @locale,
          "map.residency.show.distinct_days_with_at_least_one_tracked_point_per_country",
          %{}
        )}
      </summary>
      <div class="grid grid-cols-7 gap-1 min-w-0" role="list">
        <div
          :for={date <- @dates}
          role="listitem"
          data-residency-day={Date.to_iso8601(date)}
          aria-label={LocalizedDate.l(@locale,date,"medium") <> ": " <> (@daily[date] || "–")}
          class={"min-w-0 rounded p-1 text-xs [overflow-wrap:anywhere] #{if @daily[date], do: "bg-primary/20", else: "bg-base-200"}"}
        >
          <span>{LocalizedDate.l(@locale, date, "short_month_day")}</span> <span>{@daily[date]}</span>
        </div>
      </div>
    </details>
    """
  end
end

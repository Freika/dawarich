defmodule DawarichWeb.NativeTimelineDayNav do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.{Icon, LocalizedDate}
  attr :date, :any, required: true
  attr :locale, :string, required: true
  attr :footer, :boolean, default: false

  def nav(assigns) do
    date = if is_binary(assigns.date), do: Date.from_iso8601!(assigns.date), else: assigns.date

    assigns =
      assign(assigns,
        date: date,
        prev: Date.to_iso8601(Date.add(date, -1)),
        next: Date.to_iso8601(Date.add(date, 1))
      )

    ~H"""
    <nav class={[
      "flex flex-wrap items-center gap-2 min-w-0",
      if(@footer, do: "timeline-day-footer", else: "timeline-day-header__nav")
    ]}>
      <button
        type="button"
        class="btn btn-ghost btn-xs btn-square"
        data-direction="prev"
        data-testid={if !@footer, do: "day-prev"}
        phx-click="calendar:day"
        phx-value-date={@prev}
        aria-label={t(@locale, "map.timeline_feeds.day_nav.previous_day", %{})}
      >
        <Icon.icon name="chevron-left" class="w-4 h-4" />
      </button>
      <h3
        :if={!@footer}
        data-testid="day-header-label"
        class="font-semibold text-sm min-w-0 break-words"
      >
        {LocalizedDate.l(@locale, @date, "weekday_month_day")}
      </h3>
      <button
        type="button"
        class="btn btn-ghost btn-xs btn-square"
        data-direction="next"
        data-testid={if !@footer, do: "day-next"}
        phx-click="calendar:day"
        phx-value-date={@next}
        aria-label={t(@locale, "map.timeline_feeds.day_nav.next_day", %{})}
      >
        <Icon.icon name="chevron-right" class="w-4 h-4" />
      </button>
    </nav>
    """
  end
end

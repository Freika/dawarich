defmodule DawarichWeb.NativeTimelineCalendar do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.{Icon, LocalizedDate, TimelineFormat}

  attr :calendar, :map, default: nil
  attr :locale, :string, required: true

  def calendar(%{calendar: nil} = assigns), do: ~H""

  def calendar(assigns) do
    ~H"""
    <section
      id="native-timeline-calendar"
      class="timeline-calendar min-w-0"
      aria-busy={to_string(@calendar.status == :loading)}
    >
      <p :if={match?({:error, _}, @calendar.status)} class="alert alert-error text-xs" role="alert">
        {t(@locale, "javascript.messages.failed_to_load_visit_details", %{})}
      </p>
      <.month :if={@calendar.summary} summary={@calendar.summary} locale={@locale} />
    </section>
    """
  end

  attr :summary, :map, required: true
  attr :locale, :string, required: true

  defp month(assigns) do
    month = Date.from_iso8601!(assigns.summary.month <> "-01")
    {:ok, initials} = Dawarich.I18n.t(assigns.locale, "calendar.weekday_initials")

    assigns =
      assign(assigns,
        prev: month |> Date.shift(month: -1) |> Calendar.strftime("%Y-%m"),
        next: month |> Date.shift(month: 1) |> Calendar.strftime("%Y-%m"),
        title: LocalizedDate.l(assigns.locale, month, "month_year"),
        initials: initials
      )

    ~H"""
    <div class="flex items-center justify-between mb-2 gap-2">
      <button
        id="native-calendar-prev"
        type="button"
        class="btn btn-ghost btn-xs btn-square"
        phx-click="calendar:month"
        phx-value-month={@prev}
        aria-label={t(@locale, "map.timeline_feeds.calendar.previous_month", %{})}
      >
        <Icon.icon name="chevron-left" class="w-4 h-4" />
      </button>
      <div class="font-semibold text-sm min-w-0 text-center" data-testid="calendar-title">
        {@title}
      </div>
      <button
        id="native-calendar-next"
        type="button"
        class="btn btn-ghost btn-xs btn-square"
        phx-click="calendar:month"
        phx-value-month={@next}
        aria-label={t(@locale, "map.timeline_feeds.calendar.next_month", %{})}
      >
        <Icon.icon name="chevron-right" class="w-4 h-4" />
      </button>
    </div>
    <div class="grid grid-cols-7 gap-0.5 text-[10px] text-base-content/60 mb-1">
      <div :for={label <- @initials} class="text-center">{label}</div>
    </div>
    <div class="grid grid-cols-7 gap-0.5">
      <button
        :for={cell <- List.flatten(@summary.weeks)}
        type="button"
        class={TimelineFormat.cell_classes(cell)}
        data-day={cell.date}
        data-tracked-seconds={cell.tracked_seconds}
        disabled={cell.disabled}
        phx-click="calendar:day"
        phx-value-date={cell.date}
      >
        <span class="cal-cell__day">{Date.from_iso8601!(cell.date).day}</span>
      </button>
    </div>
    """
  end
end

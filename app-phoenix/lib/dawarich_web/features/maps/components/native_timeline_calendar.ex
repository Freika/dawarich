defmodule DawarichWeb.NativeTimelineCalendar do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.{Icon, LocalizedDate, TimelineFormat}

  attr :selected_date, :string, default: nil
  attr :calendar, :map, default: nil
  attr :locale, :string, required: true

  def calendar(%{calendar: nil} = assigns), do: ~H""

  def calendar(assigns) do
    loading = assigns.calendar.status == :loading
    summary = if loading, do: preview(assigns.calendar), else: assigns.calendar.summary
    assigns = assign(assigns, display_summary: summary, loading: loading)

    ~H"""
    <div
      id="native-timeline-calendar"
      class={["timeline-calendar", @loading && "timeline-calendar--loading"]}
      data-testid="timeline-calendar"
      data-month={@display_summary && @display_summary.month}
      aria-busy={to_string(@loading)}
    >
      <p :if={match?({:error, _}, @calendar.status)} class="alert alert-error text-xs" role="alert">
        {t(@locale, "javascript.messages.failed_to_load_visit_details", %{})}
      </p>
      <.month
        :if={@display_summary}
        summary={@display_summary}
        loading={@loading}
        locale={@locale}
        selected_date={@selected_date}
      />
    </div>
    """
  end

  attr :selected_date, :string, default: nil
  attr :loading, :boolean, default: false
  attr :summary, :map, required: true
  attr :locale, :string, required: true

  defp month(assigns) do
    month = Date.from_iso8601!(assigns.summary.month <> "-01")
    {:ok, initials} = Dawarich.I18n.t(assigns.locale, "calendar.weekday_initials")

    assigns =
      assign(assigns,
        prev: month |> Date.shift(month: -1) |> Calendar.strftime("%Y-%m"),
        next: month |> Date.shift(month: 1) |> Calendar.strftime("%Y-%m"),
        title:
          LocalizedDate.l(
            if(assigns.loading, do: "en", else: assigns.locale),
            month,
            "month_year"
          ),
        initials: initials
      )

    ~H"""
    <div class="flex items-center justify-between mb-2">
      <.nav
        id="native-calendar-prev"
        testid="calendar-prev"
        month={@prev}
        icon="chevron-left"
        label={t(@locale, "map.timeline_feeds.calendar.previous_month", %{})}
      />
      <div class="font-semibold text-sm" data-testid="calendar-title">{@title}</div>
      <.nav
        id="native-calendar-next"
        testid="calendar-next"
        month={@next}
        icon="chevron-right"
        label={t(@locale, "map.timeline_feeds.calendar.next_month", %{})}
      />
    </div>
    <div class="grid grid-cols-7 gap-0.5 text-[10px] text-base-content/60 mb-1">
      <div :for={label <- @initials} class="text-center">{label}</div>
    </div>
    <div class="grid grid-cols-7 gap-0.5">
      <button
        :for={cell <- List.flatten(@summary.weeks)}
        type="button"
        class={[
          if(@loading, do: skeleton_classes(cell), else: TimelineFormat.cell_classes(cell)),
          cell.date == @selected_date && "cal-cell--selected"
        ]}
        aria-current={if cell.date == @selected_date, do: "date"}
        data-day={cell.date}
        data-testid="calendar-day"
        data-tracked-seconds={cell.tracked_seconds}
        disabled={@loading or cell.disabled}
        phx-click="calendar:day"
        phx-value-date={cell.date}
      >
        <span class="cal-cell__day">{Date.from_iso8601!(cell.date).day}</span>
      </button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :testid, :string, required: true
  attr :month, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp nav(assigns) do
    ~H"""
    <a
      id={@id}
      href="#"
      data-testid={@testid}
      data-target-month={@month}
      class="btn btn-ghost btn-xs btn-square"
      aria-label={@label}
      phx-click="calendar:month"
      phx-value-month={@month}
    >
      <Icon.icon name={@icon} class="w-4 h-4" />
    </a>
    """
  end

  defp skeleton_classes(cell),
    do: "cal-cell heat-0 cal-cell--dark-text" <> if(cell.in_month, do: "", else: " out-of-month")

  defp preview(calendar) do
    with month when is_binary(month) <- calendar[:month],
         {:ok, first} <- Date.from_iso8601(month <> "-01") do
      start = Date.add(first, 1 - Date.day_of_week(first))

      cells =
        for offset <- 0..41 do
          day = Date.add(start, offset)

          %{
            date: Date.to_iso8601(day),
            in_month: day.month == first.month,
            tracked_seconds: nil
          }
        end

      %{month: month, weeks: Enum.chunk_every(cells, 7)}
    else
      _ -> calendar.summary
    end
  end
end

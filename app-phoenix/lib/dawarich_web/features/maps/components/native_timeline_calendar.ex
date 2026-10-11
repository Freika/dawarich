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
    <section
      id="native-timeline-calendar"
      class={["timeline-calendar min-w-0", @loading && "timeline-calendar--loading"]}
      data-month={@display_summary && @display_summary.month}
      aria-busy={to_string(@calendar.status == :loading)}
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
    </section>
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
      <span
        :for={_ <- if @loading, do: 1..42, else: []}
        data-testid="calendar-skeleton"
        aria-hidden="true"
        class="h-8 rounded bg-base-200 animate-pulse"
      ></span>
      <button
        :for={cell <- List.flatten(@summary.weeks)}
        type="button"
        class={[
          TimelineFormat.cell_classes(cell),
          cell.date == @selected_date && "cal-cell--selected"
        ]}
        aria-current={if cell.date == @selected_date, do: "date"}
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

  defp preview(calendar) do
    with month when is_binary(month) <- calendar[:month],
         {:ok, _} <- Date.from_iso8601(month <> "-01") do
      %{month: month, weeks: []}
    else
      _ -> calendar.summary
    end
  end
end

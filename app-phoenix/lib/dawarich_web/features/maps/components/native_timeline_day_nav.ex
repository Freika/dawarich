defmodule DawarichWeb.NativeTimelineDayNav do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.{Icon, LocalizedDate}

  attr :date, :any, required: true
  attr :locale, :string, required: true

  def nav(assigns) do
    assigns = assign(assigns, :date, date(assigns.date))

    ~H"""
    <div class="timeline-day-header__nav">
      <.step date={@date} direction="prev" testid="day-prev" locale={@locale} />
      <div
        class="font-semibold text-sm text-center flex-1"
        data-testid="day-header-label"
        phx-no-format
      >{LocalizedDate.l(@locale, @date, "weekday_month_day")}</div>
      <.step date={@date} direction="next" testid="day-next" locale={@locale} />
    </div>
    """
  end

  attr :date, :any, required: true
  attr :locale, :string, required: true

  def footer(assigns) do
    assigns = assign(assigns, :date, date(assigns.date))

    ~H"""
    <footer class="timeline-day-footer">
      <.step date={@date} direction="prev" type="button" locale={@locale} />
      <.step date={@date} direction="next" type="button" locale={@locale} />
    </footer>
    """
  end

  attr :date, Date, required: true
  attr :direction, :string, required: true
  attr :locale, :string, required: true
  attr :testid, :string, default: nil
  attr :type, :string, default: nil

  defp step(assigns) do
    prev = assigns.direction == "prev"

    assigns =
      assign(assigns,
        target: Date.to_iso8601(Date.add(assigns.date, if(prev, do: -1, else: 1))),
        label:
          t(
            assigns.locale,
            "map.timeline_feeds.day_nav." <> if(prev, do: "previous_day", else: "next_day"),
            %{}
          ),
        icon: if(prev, do: "chevron-left", else: "chevron-right")
      )

    ~H"""
    <button
      type={@type}
      data-testid={@testid}
      data-direction={@direction}
      title={@label}
      aria-label={@label}
      class="btn btn-ghost btn-xs btn-square"
      phx-click="calendar:day"
      phx-value-date={@target}
    >
      <Icon.icon name={@icon} class="w-4 h-4" />
    </button>
    """
  end

  defp date(value) when is_binary(value), do: Date.from_iso8601!(value)
  defp date(value), do: value
end

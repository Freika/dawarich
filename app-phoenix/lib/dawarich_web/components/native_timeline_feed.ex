defmodule DawarichWeb.NativeTimelineFeed do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.{Icon, LocalizedDate, NativeTimelineEntries, TimelineFormat}

  attr :timeline, :map, default: nil
  attr :locale, :string, required: true

  def feed(%{timeline: nil} = assigns), do: ~H""

  def feed(assigns) do
    ~H"""
    <section
      id="native-timeline-feed"
      class="min-w-0"
      aria-busy={to_string(@timeline.status == :loading)}
    >
      <span :if={@timeline.status == :loading} class="loading loading-spinner loading-sm"></span>
      <p :if={match?({:error, _}, @timeline.status)} class="alert alert-error text-sm" role="alert">
        {t(@locale, "javascript.messages.failed_to_load_visit_details", %{})}
      </p>
      <div
        :if={@timeline.feed && @timeline.feed.days == []}
        class="text-center text-base-content/60 py-8"
      >
        <p class="text-sm">{t(@locale, "map.timeline_feeds.feed.no_visits_tracked_this_day", %{})}</p>
      </div>
      <.day
        :for={day <- (@timeline.feed && @timeline.feed.days) || []}
        day={day}
        locale={@locale}
        redetected={@timeline.feed.redetected}
      />
    </section>
    """
  end

  attr :day, :map, required: true
  attr :locale, :string, required: true
  attr :redetected, :boolean, default: false

  defp day(assigns) do
    date = Date.from_iso8601!(assigns.day.date)

    assigns =
      assign(assigns,
        date: date,
        rows: TimelineFormat.with_gaps(assigns.day.entries, assigns.redetected),
        prev: Date.to_iso8601(Date.add(date, -1)),
        next: Date.to_iso8601(Date.add(date, 1))
      )

    ~H"""
    <article class="timeline-day min-w-0" data-day={@day.date}>
      <header class="timeline-day-header flex flex-wrap items-center gap-2">
        <button
          type="button"
          class="btn btn-ghost btn-xs btn-square"
          phx-click="calendar:day"
          phx-value-date={@prev}
          aria-label={t(@locale, "map.timeline_feeds.day_nav.previous_day", %{})}
        >
          <Icon.icon name="chevron-left" class="w-4 h-4" />
        </button>
        <h3 class="font-semibold text-sm min-w-0 break-words">
          {LocalizedDate.l(@locale, @date, "day_month_year")}
        </h3>
        <button
          type="button"
          class="btn btn-ghost btn-xs btn-square"
          phx-click="calendar:day"
          phx-value-date={@next}
          aria-label={t(@locale, "map.timeline_feeds.day_nav.next_day", %{})}
        >
          <Icon.icon name="chevron-right" class="w-4 h-4" />
        </button>
      </header>
      <div :if={@day.summary.mode_distances != %{}} class="flex flex-wrap gap-1 text-xs">
        <span
          :for={{mode, distance} <- Enum.sort(@day.summary.mode_distances)}
          class="badge badge-ghost gap-1"
        >
          <Icon.icon name={TimelineFormat.mode_icon(mode)} class="w-3 h-3" />
          <span class="sr-only">{t(@locale, "transportation_modes.#{mode}", %{})}</span>
          {distance} {@day.summary.distance_unit}
        </span>
      </div>
      <ol class="timeline-entries">
        <%= for entry <- @rows do %>
          <%= case entry.type do %>
            <% "visit" -> %>
              <NativeTimelineEntries.visit entry={entry} locale={@locale} redetected={@redetected} />
            <% "gap" -> %>
              <NativeTimelineEntries.gap entry={entry} locale={@locale} />
            <% _ -> %>
              <NativeTimelineEntries.journey entry={entry} locale={@locale} />
          <% end %>
        <% end %>
      </ol>
    </article>
    """
  end
end

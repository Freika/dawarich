defmodule DawarichWeb.TimelineFeed do
  @moduledoc false
  use DawarichWeb, :html

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  alias DawarichWeb.{
    Icon,
    LocalizedDate,
    StatsCards,
    TimelineEntries,
    TimelineFormat,
    TimelineJourney
  }

  @max_bulk 500

  attr :days, :list, required: true
  attr :requested_date, Date, required: true
  attr :locale, :string, required: true
  attr :ctx, :map, required: true

  def frame(assigns) do
    ~H"""
    <turbo-frame id="timeline-feed-frame">
      <div>
        <div :if={@days == []} class="timeline-day">
          <div class="timeline-day-header">
            <.day_nav date={@requested_date} locale={@locale} />
          </div>
          <div class="text-center text-base-content/60 py-8">
            <StatsCards.plan_alert :if={@ctx.alert_href} locale={@locale} href={@ctx.alert_href} />
            <p class="text-sm">
              {t(@locale, "map.timeline_feeds.feed.no_visits_tracked_this_day", %{})}
            </p>
            <p class="text-xs mt-1">
              {t(
                @locale,
                "map.timeline_feeds.feed.visits_are_auto_detected_daily_from_your_location_data",
                %{}
              )}
            </p>
          </div>
        </div>
        <.day :for={day <- @days} day={day} locale={@locale} ctx={@ctx} />
      </div>
    </turbo-frame>
    """
  end

  attr :day, :map, required: true
  attr :locale, :string, required: true
  attr :ctx, :map, required: true

  def day(assigns) do
    summary = assigns.day.summary
    entries = assigns.day.entries
    gating = assigns.ctx.redetected

    assigns =
      assign(assigns,
        count: summary.confirmed_count + summary.suggested_count + summary.declined_count,
        moving: summary.time_moving_minutes,
        rows: TimelineFormat.with_gaps(entries, gating),
        low:
          Enum.count(
            entries,
            &(&1.type == "visit" and TimelineFormat.low_confidence?(&1, gating))
          )
      )

    ~H"""
    <div
      class="timeline-day"
      data-day={@day.date}
      data-bounds={TimelineFormat.bounds_json(@day.bounds)}
    >
      <div class="timeline-day-header">
        <.day_nav date={Date.from_iso8601!(@day.date)} locale={@locale} />
        <div class="timeline-day-header__meta">
          {s(@locale, "visit_count", %{count: @count})}
          <button
            :if={@count >= 2}
            type="button"
            class="day-select-toggle"
            data-testid="day-select-toggle"
            data-action="click->timeline-feed#enterSelection"
          >
            {s(@locale, "select")}
          </button>
        </div>
      </div>
      <div :if={@day.summary.mode_distances != [] or @moving > 0} class="timeline-day-modes">
        <span :for={{mode, dist} <- @day.summary.mode_distances} class="mode-chip">
          <Icon.icon name={TimelineFormat.mode_icon(mode)} class="mode-chip__icon" />
          <span class="sr-only">{t(@locale, "transportation_modes.#{mode}", %{})}</span>
          {Ruby.to_s(dist)} {@day.summary.distance_unit}
        </span>
        <span :if={@moving > 0} class="mode-chip mode-chip--muted">
          {s(@locale, "moving_duration", %{
            duration: TimelineFormat.duration_short(@locale, @moving * 60)
          })}
        </span>
      </div>
      <.selection_bar locale={@locale} csrf={@ctx.csrf} />
      <%= if @day.entries != [] do %>
        <ol class="timeline-entries">
          <%= for entry <- @rows do %>
            <%= case entry.type do %>
              <% "visit" -> %>
                <TimelineEntries.visit_entry entry={entry} locale={@locale} ctx={@ctx} />
              <% "gap" -> %>
                <TimelineJourney.gap_entry entry={entry} locale={@locale} />
              <% _ -> %>
                <TimelineJourney.journey_entry entry={entry} locale={@locale} />
            <% end %>
          <% end %>
        </ol>
        <button
          :if={@low > 0}
          type="button"
          class="timeline-lowconf-toggle"
          data-testid="lowconf-toggle"
          data-action="click->timeline-feed#toggleLowConfidence"
          aria-expanded="false"
        >
          {s(@locale, "low_confidence_stops", %{count: @low})}
        </button>
        <div class="timeline-entries-empty-filtered hidden" data-timeline-feed-target="emptyFiltered">
          <p class="text-sm text-base-content/70">
            {s(@locale, "no_visits_match_the_current_search_or_filter")}
          </p>
          <button
            type="button"
            class="btn btn-ghost btn-xs"
            data-action="click->timeline-feed#clearVisitFilters"
          >
            {s(@locale, "clear_search_filters")}
          </button>
        </div>
      <% else %>
        <p class="text-center text-sm text-base-content/60 py-6">
          {s(@locale, "no_visits_tracked_this_day")}
        </p>
      <% end %>
      <footer class="timeline-day-footer">
        <button
          type="button"
          class="btn btn-ghost btn-xs btn-square"
          data-action="click->timeline-feed#navigateDay"
          data-direction="prev"
          title={s(@locale, "previous_day")}
          aria-label={s(@locale, "previous_day")}
        >
          <Icon.icon name="chevron-left" class="w-4 h-4" />
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-xs btn-square"
          data-action="click->timeline-feed#navigateDay"
          data-direction="next"
          title={s(@locale, "next_day")}
          aria-label={s(@locale, "next_day")}
        >
          <Icon.icon name="chevron-right" class="w-4 h-4" />
        </button>
      </footer>
    </div>
    """
  end

  attr :date, Date, required: true
  attr :locale, :string, required: true

  def day_nav(assigns) do
    ~H"""
    <div class="timeline-day-header__nav">
      <button
        data-testid="day-prev"
        data-action="click->timeline-feed#navigateDay"
        data-direction="prev"
        title={t(@locale, "map.timeline_feeds.day_nav.previous_day", %{})}
        aria-label={t(@locale, "map.timeline_feeds.day_nav.previous_day", %{})}
        class="btn btn-ghost btn-xs btn-square"
      >
        <Icon.icon name="chevron-left" class="w-4 h-4" />
      </button>
      <div
        class="font-semibold text-sm text-center flex-1"
        data-testid="day-header-label"
        phx-no-format
      >{LocalizedDate.l(@locale, @date, "weekday_month_day")}</div>
      <button
        data-testid="day-next"
        data-action="click->timeline-feed#navigateDay"
        data-direction="next"
        title={t(@locale, "map.timeline_feeds.day_nav.next_day", %{})}
        aria-label={t(@locale, "map.timeline_feeds.day_nav.next_day", %{})}
        class="btn btn-ghost btn-xs btn-square"
      >
        <Icon.icon name="chevron-right" class="w-4 h-4" />
      </button>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :csrf, :string, required: true

  def selection_bar(assigns) do
    assigns = assign(assigns, :max_bulk, @max_bulk)

    ~H"""
    <div
      data-timeline-feed-target="selectionBar"
      data-max-bulk-visits={@max_bulk}
      class="selection-bar"
      hidden
    >
      <span class="selection-bar__count" data-timeline-feed-target="selectionCount">{b(
        @locale,
        "selected"
      )}</span>
      <span class="selection-bar__actions">
        <form
          data-timeline-feed-target="selectionForm"
          data-action="submit->timeline-feed#submitMerge"
          class="selection-bar__form"
          action="/visits/merge"
          accept-charset="UTF-8"
          method="post"
        >
          <input type="hidden" name="authenticity_token" value={@csrf} />
          <button
            type="submit"
            class="selection-bar__action selection-bar__merge"
            data-timeline-feed-target="mergeButton"
            title={b(@locale, "combine_the_selected_visits_into_one")}
            disabled
          >
            {b(@locale, "merge")}
          </button>
        </form>
        <form
          data-timeline-feed-target="deleteForm"
          data-action="submit->timeline-feed#submitBulkDelete"
          class="selection-bar__form"
          action="/visits/bulk_destroy"
          accept-charset="UTF-8"
          method="post"
        >
          <input type="hidden" name="_method" value="delete" />
          <input type="hidden" name="authenticity_token" value={@csrf} />
          <button
            type="submit"
            class="selection-bar__action selection-bar__delete"
            data-timeline-feed-target="deleteButton"
            title={b(@locale, "remove_the_visit_grouping_your_location_points_stay")}
            disabled
          >
            {b(@locale, "delete")}
          </button>
        </form>
        <button
          type="button"
          class="selection-bar__cancel"
          title={b(@locale, "cancel")}
          aria-label={b(@locale, "cancel")}
          data-action="click->timeline-feed#exitSelection"
        >
          <Icon.icon name="x" class="w-3.5 h-3.5" />
        </button>
      </span>
    </div>
    """
  end

  defp s(locale, key, bindings \\ %{}), do: t(locale, "map.timeline_feeds.day." <> key, bindings)
  defp b(locale, key), do: t(locale, "map.timeline_feeds.selection_bar." <> key, %{})
end

defmodule DawarichWeb.NativeTimelineFeed do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  alias DawarichWeb.{
    Icon,
    NativeSelectionActions,
    NativeTimelineDayNav,
    NativeTrackInfo,
    StatsCards,
    TimelineEntries,
    TimelineFormat,
    TimelineJourney
  }

  alias Phoenix.LiveView.JS

  attr :selected_date, :string, default: nil
  attr :timeline, :map, default: nil
  attr :filter, :map, default: nil
  attr :selection, :map, default: nil
  attr :selected_visit, :any, default: nil
  attr :csrf, :string, default: ""
  attr :editing, :map, default: nil
  attr :track_info, :map, default: nil
  attr :unit, :string, default: "km"
  attr :locale, :string, required: true

  def feed(%{timeline: nil} = assigns), do: ~H""

  def feed(assigns) do
    query = String.downcase((assigns.filter || %{})["q"] || "")
    active = (assigns.filter || %{})["tags"] || []
    feed = assigns.timeline.feed
    days = (feed && feed.days) || []
    filtering = query != "" or active != []
    visits = for day <- days, entry <- day.entries, entry.type == "visit", do: entry

    hidden =
      if filtering,
        do: MapSet.new(Enum.reject(visits, &visible?(&1, query, active)), & &1.visit_id),
        else: MapSet.new()

    assigns =
      assign(assigns,
        days: days,
        hidden: hidden,
        clear_day: Enum.find_value(days, &(&1.entries != [] && &1.date)),
        empty_date: feed && feed.days == [] && (feed[:requested_date] || assigns.selected_date),
        alert_href: feed && feed[:alert_href],
        unmatched: filtering and visits != [] and MapSet.size(hidden) == length(visits)
      )

    ~H"""
    <div id="native-timeline-feed" aria-busy={to_string(@timeline.status == :loading)}>
      <span :if={@timeline.status == :loading} class="loading loading-spinner loading-sm"></span>
      <p :if={match?({:error, _}, @timeline.status)} class="alert alert-error text-sm" role="alert">
        {t(@locale, "javascript.messages.failed_to_load_visit_details", %{})}
      </p>
      <div :if={@empty_date} class="timeline-day">
        <div class="timeline-day-header">
          <NativeTimelineDayNav.nav date={@empty_date} locale={@locale} />
        </div>
        <div class="text-center text-base-content/60 py-8">
          <StatsCards.plan_alert :if={@alert_href} locale={@locale} href={@alert_href} />
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
      <.day
        :for={day <- @days}
        day={day}
        first={day.date == @clear_day}
        locale={@locale}
        csrf={@csrf}
        unmatched={@unmatched}
        hidden={@hidden}
        redetected={@timeline.feed.redetected}
        selection={@selection && @selection.day == day.date && @selection}
        selected_visit={@selected_visit}
        editing={@editing}
        track_info={@track_info}
        unit={@unit}
      />
      <button
        :if={@timeline.feed && @timeline.feed[:next_cursor]}
        type="button"
        phx-click="timeline:more"
        disabled={@timeline.status == :loading}
        class="btn btn-sm max-w-full whitespace-normal"
      >
        {Phoenix.HTML.raw(t(@locale, "views.pagination.next", %{}))}
      </button>
    </div>
    """
  end

  defp visible?(entry, query, active) do
    tokens = TimelineFormat.search_tokens(entry)

    String.contains?(tokens, query) and
      (active == [] or Enum.any?(active, &String.contains?(tokens, &1)))
  end

  attr :day, :map, required: true
  attr :first, :boolean, default: false
  attr :locale, :string, required: true
  attr :csrf, :string, default: ""
  attr :unmatched, :boolean, default: false
  attr :hidden, :any, required: true
  attr :redetected, :boolean, default: false
  attr :selection, :any, default: nil
  attr :selected_visit, :any, default: nil
  attr :editing, :map, default: nil
  attr :track_info, :map, default: nil
  attr :unit, :string, default: "km"

  defp day(assigns) do
    summary = assigns.day.summary
    visits = Enum.filter(assigns.day.entries, &(&1.type == "visit"))

    assigns =
      assign(assigns,
        rows: TimelineFormat.with_gaps(assigns.day.entries, assigns.redetected),
        moving: Map.get(summary, :time_moving_minutes, 0),
        modes: Enum.sort(summary.mode_distances),
        count:
          Enum.sum(
            for key <- [:confirmed_count, :suggested_count, :declined_count],
                do: Map.get(summary, key, 0)
          ),
        low: Enum.count(visits, &TimelineFormat.low_confidence?(&1, assigns.redetected)),
        dom_id: "native-day-#{assigns.day.date}",
        ctx: %{redetected: assigns.redetected, csrf: assigns.csrf, api_key: ""},
        checked: (assigns.selection && assigns.selection.ids) || []
      )

    ~H"""
    <div
      id={@dom_id}
      class="timeline-day"
      data-day={@day.date}
      data-bounds={TimelineFormat.bounds_json(@day[:bounds])}
      data-selection-mode={@selection && "true"}
    >
      <div class="timeline-day-header">
        <NativeTimelineDayNav.nav date={@day.date} locale={@locale} />
        <div class="timeline-day-header__meta">
          {t(@locale, "map.timeline_feeds.day.visit_count", %{count: @count})}
          <button
            :if={@count >= 2}
            type="button"
            class="day-select-toggle"
            data-testid="day-select-toggle"
            hidden={!!@selection}
            phx-click="timeline:select_day"
            phx-value-date={@day.date}
          >
            {s(@locale, "select")}
          </button>
        </div>
      </div>
      <div :if={@modes != [] or @moving > 0} class="timeline-day-modes">
        <span :for={{mode, distance} <- @modes} class="mode-chip">
          <Icon.icon name={TimelineFormat.mode_icon(mode)} class="mode-chip__icon" />
          <span class="sr-only">{t(@locale, "transportation_modes.#{mode}", %{})}</span>
          {Ruby.to_s(distance)} {@day.summary.distance_unit}
        </span>
        <span :if={@moving > 0} class="mode-chip mode-chip--muted">
          {s(@locale, "moving_duration", %{
            duration: TimelineFormat.duration_short(@locale, @moving * 60)
          })}
        </span>
      </div>
      <NativeSelectionActions.bar
        ids={@selection && @selection.ids}
        csrf={@csrf}
        cancel="timeline:select_cancel"
        locale={@locale}
      />
      <%= if @day.entries != [] do %>
        <ol class="timeline-entries">
          <%= for entry <- @rows do %>
            <%= case entry.type do %>
              <% "visit" -> %>
                <TimelineEntries.visit_entry
                  entry={entry}
                  locale={@locale}
                  ctx={@ctx}
                  native
                  checked={to_string(entry.visit_id) in @checked}
                  selected={@selected_visit == entry.visit_id}
                  hidden={MapSet.member?(@hidden, entry.visit_id)}
                  editing={
                    @editing && to_string(@editing.id) == to_string(entry.visit_id) && @editing
                  }
                />
              <% "gap" -> %>
                <TimelineJourney.gap_entry entry={entry} locale={@locale} />
              <% _ -> %>
                <TimelineJourney.journey_entry
                  entry={entry}
                  locale={@locale}
                  native
                  open={!!(@track_info && entry.track_id && @track_info.id == entry.track_id)}
                >
                  <:panel>
                    <NativeTrackInfo.card track={@track_info} unit={@unit} locale={@locale} />
                  </:panel>
                </TimelineJourney.journey_entry>
            <% end %>
          <% end %>
        </ol>
        <button
          :if={@low > 0}
          type="button"
          class="timeline-lowconf-toggle"
          data-testid="lowconf-toggle"
          aria-expanded="false"
          phx-click={
            JS.toggle_class("timeline-day--show-lowconf", to: "##{@dom_id}")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
          }
        >
          {s(@locale, "low_confidence_stops", %{count: @low})}
        </button>
        <.empty_filtered first={@first} unmatched={@unmatched} locale={@locale} />
      <% else %>
        <p class="text-center text-sm text-base-content/60 py-6">
          {s(@locale, "no_visits_tracked_this_day")}
        </p>
      <% end %>
      <NativeTimelineDayNav.footer date={@day.date} locale={@locale} />
    </div>
    """
  end

  attr :first, :boolean, required: true
  attr :unmatched, :boolean, required: true
  attr :locale, :string, required: true

  defp empty_filtered(assigns) do
    ~H"""
    <div class={["timeline-entries-empty-filtered", !@unmatched && "hidden"]}>
      <p class="text-sm text-base-content/70">
        {s(@locale, "no_visits_match_the_current_search_or_filter")}
      </p>
      <button
        {if(@first, do: [id: "native-timeline-filter-clear"], else: [])}
        type="button"
        class="btn btn-ghost btn-xs"
        phx-click="timeline:filter"
        phx-value-q=""
        phx-value-clear="true"
      >
        {s(@locale, "clear_search_filters")}
      </button>
    </div>
    """
  end

  defp s(locale, key, bindings \\ %{}), do: t(locale, "map.timeline_feeds.day." <> key, bindings)
end

defmodule DawarichWeb.NativeTimelineFeed do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.{
    Icon,
    NativeTimelineDayNav,
    NativeSelectionActions,
    NativeTimelineEntries,
    TimelineFormat
  }

  alias Phoenix.LiveView.JS

  attr :selected_date, :string, default: nil
  attr :timeline, :map, default: nil
  attr :filter, :map, default: nil
  attr :selection, :map, default: nil
  attr :selected_visit, :any, default: nil
  attr :tags, :list, default: []
  attr :locale, :string, required: true

  def feed(%{timeline: nil} = assigns), do: ~H""

  def feed(assigns) do
    query = String.downcase((assigns.filter || %{})["q"] || "")
    active = (assigns.filter || %{})["tags"] || []
    days = (assigns.timeline.feed && assigns.timeline.feed.days) || []

    days =
      if query == "" and active == [],
        do: days,
        else: Enum.map(days, &keep(&1, query, active))

    visits? = Enum.any?(days, fn day -> Enum.any?(day.entries, &(&1.type == "visit")) end)

    assigns =
      assign(assigns,
        query: query,
        active: active,
        days: days,
        unmatched: (query != "" or active != []) and not visits?
      )

    ~H"""
    <form
      id="native-timeline-filter"
      phx-change="timeline:filter"
      phx-submit="timeline:filter"
      class="flex flex-wrap gap-2 min-w-0"
    >
      <input
        type="search"
        autocomplete="off"
        name="q"
        value={@query}
        class="input input-sm input-bordered min-w-0 flex-1"
        aria-label={t(@locale, "javascript.places.search_placeholder", %{})}
      />
    </form>
    <div :if={@tags != []} id="native-timeline-tags" class="flex flex-wrap gap-1 min-w-0">
      <a
        data-testid="tags-manage-link"
        href="/tags"
        target="_blank"
        rel="noopener"
        class="link min-w-0 [overflow-wrap:anywhere]"
        title={t(@locale, "map.maplibre.settings_panel.manage_tags_in_a_new_tab", %{})}
      >{t(@locale, "map.maplibre.settings_panel.manage", %{})}</a>
      <button
        :for={tag <- @tags}
        type="button"
        class={[
          "tag-chip tag-chip--toggle",
          String.downcase(tag.name) in @active && "tag-chip--active"
        ]}
        data-tag-name={String.downcase(tag.name)}
        aria-pressed={to_string(String.downcase(tag.name) in @active)}
        style={tag_style(tag.color)}
        phx-click="timeline:tag"
        phx-value-tag={tag.name}
      >
        <span class="[overflow-wrap:anywhere]">{if tag.icon not in [nil, ""], do: "#{tag.icon} "}{tag.name}</span>
      </button>
    </div>
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
        <NativeTimelineDayNav.nav :if={@selected_date} date={@selected_date} locale={@locale} />
        <p class="text-sm">{t(@locale, "map.timeline_feeds.feed.no_visits_tracked_this_day", %{})}</p>
      </div>
      <div :if={@unmatched} class="text-center py-4">
        <p class="text-sm text-base-content/70">
          {t(@locale, "map.timeline_feeds.day.no_visits_match_the_current_search_or_filter", %{})}
        </p>
        <button
          id="native-timeline-filter-clear"
          type="button"
          class="btn btn-ghost btn-xs"
          phx-click="timeline:filter"
          phx-value-q=""
          phx-value-clear="true"
        >
          {t(@locale, "map.timeline_feeds.day.clear_search_filters", %{})}
        </button>
      </div>
      <.day
        :for={day <- @days}
        day={day}
        locale={@locale}
        redetected={@timeline.feed.redetected}
        selection={@selection && @selection.day == day.date && @selection}
        selected_visit={@selected_visit}
      />
    </section>
    """
  end

  defp keep(day, query, active) do
    entries =
      Enum.filter(day.entries, fn entry ->
        tokens = entry.type == "visit" && TimelineFormat.search_tokens(entry)

        entry.type != "visit" or
          (String.contains?(tokens, query) and
             (active == [] or Enum.any?(active, &String.contains?(tokens, &1))))
      end)

    %{day | entries: entries}
  end

  defp tag_style(color) when is_binary(color) do
    if color =~ ~r/\A#[0-9a-fA-F]{3,8}\z/, do: "background-color: #{color};"
  end

  defp tag_style(_color), do: nil

  attr :day, :map, required: true
  attr :locale, :string, required: true
  attr :redetected, :boolean, default: false
  attr :selection, :any, default: nil
  attr :selected_visit, :any, default: nil

  defp day(assigns) do
    date = Date.from_iso8601!(assigns.day.date)
    visits = Enum.filter(assigns.day.entries, &(&1.type == "visit"))

    assigns =
      assign(assigns,
        date: date,
        rows: TimelineFormat.with_gaps(assigns.day.entries, assigns.redetected),
        prev: Date.to_iso8601(Date.add(date, -1)),
        next: Date.to_iso8601(Date.add(date, 1)),
        moving: Map.get(assigns.day.summary, :time_moving_minutes, 0),
        visits: length(visits),
        count:
          Enum.sum(
            for key <- [:confirmed_count, :suggested_count, :declined_count],
                do: Map.get(assigns.day.summary, key, 0)
          ),
        low: Enum.count(visits, &TimelineFormat.low_confidence?(&1, assigns.redetected)),
        dom_id: "native-day-#{assigns.day.date}"
      )

    ~H"""
    <article id={@dom_id} class="timeline-day min-w-0" data-day={@day.date}>
      <header class="timeline-day-header flex flex-wrap items-center gap-2">
        <NativeTimelineDayNav.nav date={@date} locale={@locale} />
        <div class="timeline-day-header__meta text-sm min-w-0">
          {t(@locale, "map.timeline_feeds.day.visit_count", %{count: @count})}
        </div>
        <button
          :if={@visits >= 2 and !@selection}
          type="button"
          class="day-select-toggle btn btn-ghost btn-xs"
          phx-click="timeline:select_day"
          phx-value-date={@day.date}
        >
          {t(@locale, "map.timeline_feeds.day.select", %{})}
        </button>
      </header>
      <NativeSelectionActions.bar
        :if={@selection}
        id="native-timeline-selection"
        ids={@selection.ids}
        cancel="timeline:select_cancel"
        locale={@locale}
      />
      <div
        :if={@day.summary.mode_distances != %{} or @moving > 0}
        class="timeline-day-modes flex flex-wrap gap-1 text-xs"
      >
        <span
          :for={{mode, distance} <- Enum.sort(@day.summary.mode_distances)}
          class="mode-chip badge badge-ghost gap-1"
        >
          <Icon.icon name={TimelineFormat.mode_icon(mode)} class="w-3 h-3" />
          <span class="sr-only">{t(@locale, "transportation_modes.#{mode}", %{})}</span>
          {distance} {@day.summary.distance_unit}
        </span>
        <span :if={@moving > 0} class="mode-chip mode-chip--muted">
          {t(@locale, "map.timeline_feeds.day.moving_duration", %{
            duration: TimelineFormat.duration_short(@locale, @moving * 60)
          })}
        </span>
      </div>
      <ol class="timeline-entries">
        <%= for entry <- @rows do %>
          <%= case entry.type do %>
            <% "visit" -> %>
              <NativeTimelineEntries.visit
                entry={entry}
                locale={@locale}
                redetected={@redetected}
                selection={@selection && @selection.ids}
                selected={@selected_visit == entry.visit_id}
              />
            <% "gap" -> %>
              <NativeTimelineEntries.gap entry={entry} locale={@locale} />
            <% _ -> %>
              <NativeTimelineEntries.journey entry={entry} locale={@locale} />
          <% end %>
        <% end %>
      </ol>
      <NativeTimelineDayNav.nav date={@date} locale={@locale} footer />
      <button
        :if={@low > 0}
        type="button"
        class="timeline-lowconf-toggle btn btn-ghost btn-xs"
        aria-expanded="false"
        phx-click={
          JS.toggle_class("timeline-day--show-lowconf", to: "##{@dom_id}")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
      >
        {t(@locale, "map.timeline_feeds.day.low_confidence_stops", %{count: @low})}
      </button>
    </article>
    """
  end
end

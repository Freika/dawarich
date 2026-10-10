defmodule DawarichWeb.NativeTimelineFeed do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.{Icon, LocalizedDate, TimelineFormat}

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
      <.day :for={day <- (@timeline.feed && @timeline.feed.days) || []} day={day} locale={@locale} />
    </section>
    """
  end

  attr :day, :map, required: true
  attr :locale, :string, required: true

  defp day(assigns) do
    ~H"""
    <article class="timeline-day min-w-0" data-day={@day.date}>
      <h3 class="font-semibold text-sm break-words">
        {LocalizedDate.l(@locale, Date.from_iso8601!(@day.date), "day_month_year")}
      </h3>
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
        <li
          :for={entry <- @day.entries}
          class="flex flex-wrap items-center gap-2 py-1 text-sm min-w-0"
          data-entry={entry.type}
          data-track-id={entry[:track_id]}
          data-visit-id={entry[:visit_id]}
        >
          <%= if entry.type == "visit" do %>
            <Icon.icon name="map-pin" class="w-4 h-4" />
            <span class="min-w-0 [overflow-wrap:anywhere]">{entry.name}</span>
          <% else %>
            <button
              type="button"
              class="btn btn-ghost btn-xs gap-1"
              phx-click="segments:open"
              phx-value-track_id={entry.track_id}
            >
              <Icon.icon name={TimelineFormat.mode_icon(entry.dominant_mode)} class="w-4 h-4" />
              {t(@locale, "transportation_modes.#{entry.dominant_mode}", %{})}
            </button>
            <span class="text-xs text-base-content/60 tabular-nums">{entry.distance} {entry.distance_unit}</span>
          <% end %>
        </li>
      </ol>
    </article>
    """
  end
end

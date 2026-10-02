defmodule DawarichWeb.TimelineCalendar do
  @moduledoc false
  use DawarichWeb, :html

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Timeline.Days
  alias DawarichWeb.{Icon, LocalizedDate, TimelineFormat}

  @widths ~w(w-full w-3/4 w-5/6 w-2/3 w-4/5)

  attr :track, :map, required: true
  attr :unit, :string, required: true
  attr :locale, :string, required: true

  def track_info_frame(assigns) do
    track = assigns.track
    unit = assigns.unit

    assigns =
      assign(assigns,
        mode_label:
          if(track.mode,
            do: t(assigns.locale, "transportation_modes.#{track.mode}", %{}),
            else: s(assigns.locale, "unknown")
          ),
        distance: Days.distance(track.distance, unit),
        speed: Days.speed(track.avg_speed || 0.0, unit),
        speed_label:
          t(
            assigns.locale,
            if(unit == "mi", do: "units.miles_per_hour", else: "units.kilometers_per_hour"),
            %{}
          )
      )

    ~H"""
    <turbo-frame id={"track-info-#{@track.id}"}>
      <div class="track-info-card">
        <div class="track-info-card__id">{s(@locale, "track")}{@track.id}</div>
        <div class="track-info-stats">
          <span><span class="track-info-stats__label">{s(@locale, "dist")}</span>
          <strong>{Ruby.to_s(@distance)} {@unit}</strong></span>
          <span><span class="track-info-stats__label">{s(@locale, "avg")}</span>
          <strong>{Ruby.to_s(@speed)} {@speed_label}</strong></span>
          <span :if={(@track.elevation_gain || 0) > 0}><span class="track-info-stats__label">↑</span>
          <strong>{t(@locale, "units.meters", %{value: @track.elevation_gain})}</strong></span>
          <span :if={(@track.elevation_loss || 0) > 0}><span class="track-info-stats__label">↓</span>
          <strong>{t(@locale, "units.meters", %{value: @track.elevation_loss})}</strong></span>
          <span id={"track-info-mode-#{@track.id}"} class="track-info-mode capitalize">{@mode_label}</span>
        </div>
        <div class="track-info-actions">
          <label class="track-info-toggle">
            <input
              type="checkbox"
              class="toggle toggle-xs toggle-success"
              data-track-id={@track.id}
              data-action="change->maps--maplibre#toggleTrackPoints"
            />
            <span>{s(@locale, "show_points")}</span>
          </label>
          <button
            type="button"
            class="btn btn-xs btn-ghost gap-1 px-2"
            data-action="click->maps--maplibre#replayTrack"
            data-track-start={@track.started_at}
          >
            <Icon.icon name="play" id="track-replay-play-icon" class="w-3 h-3" />
            <Icon.icon name="pause" id="track-replay-pause-icon" class="w-3 h-3 hidden" />
            <span id="track-replay-label">{s(@locale, "replay")}</span>
          </button>
          <a
            class="btn btn-xs btn-ghost gap-1 px-2"
            data-turbo-frame="share-link-modal"
            href={"/tracks/#{@track.id}/share_link/new"}
          >
            <Icon.icon name="share" class="w-3 h-3" />
            <span>{s(@locale, "share")}</span>
          </a>
        </div>
        <turbo-frame
          id={"track-#{@track.id}-segments"}
          class="track-info-segments"
          src={"/tracks/#{@track.id}/segments"}
          loading="lazy"
        >
          <.skeleton lines={2} />
        </turbo-frame>
      </div>
    </turbo-frame>
    """
  end

  attr :summary, :map, required: true
  attr :locale, :string, required: true

  def calendar(assigns) do
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
    <turbo-frame id="timeline-calendar-frame">
      <div class="timeline-calendar" data-testid="timeline-calendar">
        <div class="flex items-center justify-between mb-2">
          <a
            data-turbo-stream="true"
            data-testid="calendar-prev"
            data-target-month={@prev}
            data-action="click->timeline-feed#previewMonth"
            class="btn btn-ghost btn-xs btn-square"
            aria-label={t(@locale, "map.timeline_feeds.calendar.previous_month", %{})}
            href={"/map/timeline_feeds/calendar?month=#{@prev}"}
          >
            <Icon.icon name="chevron-left" class="w-4 h-4" />
          </a>
          <div class="font-semibold text-sm" data-testid="calendar-title">{@title}</div>
          <a
            data-turbo-stream="true"
            data-testid="calendar-next"
            data-target-month={@next}
            data-action="click->timeline-feed#previewMonth"
            class="btn btn-ghost btn-xs btn-square"
            aria-label={t(@locale, "map.timeline_feeds.calendar.next_month", %{})}
            href={"/map/timeline_feeds/calendar?month=#{@next}"}
          >
            <Icon.icon name="chevron-right" class="w-4 h-4" />
          </a>
        </div>
        <div class="grid grid-cols-7 gap-0.5 text-[10px] text-base-content/60 mb-1">
          <div :for={label <- @initials} class="text-center">{label}</div>
        </div>
        <div class="grid grid-cols-7 gap-0.5">
          <%= for week <- @summary.weeks, cell <- week do %>
            <button
              type="button"
              class={TimelineFormat.cell_classes(cell)}
              data-day={cell.date}
              data-action="click->timeline-feed#selectDay"
              data-testid="calendar-day"
              data-tracked-seconds={cell.tracked_seconds}
              disabled={cell.disabled}
            >
              <span class="cal-cell__day">{Date.from_iso8601!(cell.date).day}</span>
            </button>
          <% end %>
        </div>
      </div>
    </turbo-frame>
    """
  end

  attr :summary, :map, required: true
  attr :locale, :string, required: true

  def calendar_stream(assigns) do
    ~H"""
    <turbo-stream action="replace" target="timeline-calendar-frame" phx-no-format><template><.calendar summary={@summary} locale={@locale} /></template></turbo-stream>
    """
  end

  attr :lines, :integer, required: true

  def skeleton(assigns) do
    ~H"""
    <div class="space-y-2 p-3">
      <div
        :for={index <- 0..(@lines - 1)}
        class={"h-3 #{width(index)} bg-base-300 rounded animate-pulse"}
      >
      </div>
    </div>
    """
  end

  defp width(index), do: Enum.at(@widths, rem(index, length(@widths)))

  defp s(locale, key), do: t(locale, "map.timeline_feeds.track_info." <> key, %{})
end

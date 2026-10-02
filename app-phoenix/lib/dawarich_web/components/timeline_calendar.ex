defmodule DawarichWeb.TimelineCalendar do
  @moduledoc false
  use DawarichWeb, :html

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Timeline.Days
  alias DawarichWeb.Icon

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

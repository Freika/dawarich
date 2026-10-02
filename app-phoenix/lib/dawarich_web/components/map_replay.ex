defmodule DawarichWeb.MapReplay do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.Icon

  attr :locale, :string, required: true

  def replay_panel(assigns) do
    ~H"""
    <div class="replay-panel hidden" data-maps--maplibre-target="replayPanel">
      <button
        type="button"
        class="replay-close"
        data-action="click->maps--maplibre#toggleReplay"
        title={r(@locale, "close_replay")}
        aria-label={r(@locale, "close_replay")}
      >
        {r(@locale, "times")}
      </button>

      <div class="replay-controls-row">
        <div class="replay-day-nav">
          <div class="replay-day-info">
            <span class="replay-day-display" data-maps--maplibre-target="replayDayDisplay">
              {r(@locale, "no_data_loaded")}
            </span>
            <span class="replay-day-count" data-maps--maplibre-target="replayDayCount"></span>
          </div>
        </div>

        <div class="replay-time-block">
          <span
            class="replay-time-display"
            data-maps--maplibre-target="replayTimeDisplay"
            aria-live="polite"
          >
            --:--
          </span>
          <span class="replay-speed-display" data-maps--maplibre-target="replaySpeedDisplay"></span>
          <span
            class="replay-data-indicator hidden"
            data-maps--maplibre-target="replayDataIndicator"
            role="status"
          >
            {r(@locale, "no_data")}
          </span>
        </div>

        <div class="replay-action-controls">
          <button
            type="button"
            class="replay-play-btn"
            data-maps--maplibre-target="replayPlayButton"
            data-action="click->maps--maplibre#replayTogglePlayback"
            title={r(@locale, "play_pause")}
            aria-label={r(@locale, "play_or_pause_replay")}
          >
            <span class="play-icon" data-maps--maplibre-target="replayPlayIcon">&#9658;</span>
            <span class="pause-icon hidden" data-maps--maplibre-target="replayPauseIcon">&#10074;&#10074;</span>
          </button>
          <button
            type="button"
            class="replay-follow-btn"
            data-maps--maplibre-target="replayFollowButton"
            data-action="click->maps--maplibre#replayRecenterFollow"
            title={r(@locale, "recenter_follow_marker")}
            aria-label={r(@locale, "recenter_and_follow_the_marker")}
          >
            <Icon.icon name="locate-fixed" class="replay-follow-icon" />
          </button>
          <div class="replay-speed-control">
            <input
              type="range"
              class="replay-speed-slider"
              min="1"
              max="4"
              value="2"
              step="1"
              data-maps--maplibre-target="replaySpeedSlider"
              data-action="input->maps--maplibre#replaySpeedChange"
              title={r(@locale, "replay_speed")}
              aria-label={r(@locale, "replay_speed")}
            />
            <span class="replay-speed-label" data-maps--maplibre-target="replaySpeedLabel">2x</span>
          </div>
          <div class="replay-cycle-controls hidden" data-maps--maplibre-target="replayCycleControls">
            <button
              type="button"
              data-action="click->maps--maplibre#replayCyclePrev"
              title={r(@locale, "previous_point")}
              aria-label={r(@locale, "previous_point")}
            >
              {r(@locale, "larr")}
            </button>
            <span class="replay-point-counter" data-maps--maplibre-target="replayPointCounter">
              {r(@locale, "point_1_of_1")}
            </span>
            <button
              type="button"
              data-action="click->maps--maplibre#replayCycleNext"
              title={r(@locale, "next_point")}
              aria-label={r(@locale, "next_point")}
            >
              {r(@locale, "rarr")}
            </button>
          </div>
        </div>
      </div>

      <div class="replay-scrubber-wrapper">
        <span class="replay-time-label">00:00</span>
        <div class="replay-scrubber-track" data-maps--maplibre-target="replayScrubberTrack">
          <div class="replay-density-container" data-maps--maplibre-target="replayDensityContainer">
          </div>
          <input
            type="range"
            class="replay-scrubber"
            min="0"
            max="1439"
            value="720"
            data-maps--maplibre-target="replayScrubber"
            data-action="input->maps--maplibre#replayScrubberHover"
            aria-label={r(@locale, "replay_scrubber_time_of_day")}
          />
        </div>
        <span class="replay-time-label">23:59</span>
      </div>
    </div>
    """
  end

  defp r(locale, key), do: t(locale, "shared.replay_panel." <> key, %{})
end

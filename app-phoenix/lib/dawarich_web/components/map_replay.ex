defmodule DawarichWeb.MapReplay do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.Icon

  attr :locale, :string, required: true
  attr :stimulus, :string, default: "maps--maplibre"
  attr :show_day_nav, :boolean, default: false

  def replay_panel(assigns) do
    ~H"""
    <div class="replay-panel hidden" {target(@stimulus, "replayPanel")}>
      <button
        type="button"
        class="replay-close"
        data-action={"click->#{@stimulus}#toggleReplay"}
        title={r(@locale, "close_replay")}
        aria-label={r(@locale, "close_replay")}
      >
        {r(@locale, "times")}
      </button>

      <div class="replay-controls-row">
        <div class="replay-day-nav">
          <button
            :if={@show_day_nav}
            type="button"
            data-action={"click->#{@stimulus}#replayPrevDay"}
            {target(@stimulus, "replayPrevDayButton")}
            title={r(@locale, "previous_day")}
            aria-label={r(@locale, "previous_day")}
          >
            {r(@locale, "larr")}
          </button>
          <div class="replay-day-info">
            <span class="replay-day-display" {target(@stimulus, "replayDayDisplay")}>
              {r(@locale, "no_data_loaded")}
            </span>
            <span class="replay-day-count" {target(@stimulus, "replayDayCount")}></span>
          </div>
          <button
            :if={@show_day_nav}
            type="button"
            data-action={"click->#{@stimulus}#replayNextDay"}
            {target(@stimulus, "replayNextDayButton")}
            title={r(@locale, "next_day")}
            aria-label={r(@locale, "next_day")}
          >
            {r(@locale, "rarr")}
          </button>
        </div>

        <div class="replay-time-block">
          <span
            class="replay-time-display"
            {target(@stimulus, "replayTimeDisplay")}
            aria-live="polite"
          >
            --:--
          </span>
          <span class="replay-speed-display" {target(@stimulus, "replaySpeedDisplay")}></span>
          <span
            class="replay-data-indicator hidden"
            {target(@stimulus, "replayDataIndicator")}
            role="status"
          >
            {r(@locale, "no_data")}
          </span>
        </div>

        <div class="replay-action-controls">
          <button
            type="button"
            class="replay-play-btn"
            {target(@stimulus, "replayPlayButton")}
            data-action={"click->#{@stimulus}#replayTogglePlayback"}
            title={r(@locale, "play_pause")}
            aria-label={r(@locale, "play_or_pause_replay")}
          >
            <span class="play-icon" {target(@stimulus, "replayPlayIcon")}>&#9658;</span>
            <span class="pause-icon hidden" {target(@stimulus, "replayPauseIcon")}>&#10074;&#10074;</span>
          </button>
          <button
            type="button"
            class="replay-follow-btn"
            {target(@stimulus, "replayFollowButton")}
            data-action={"click->#{@stimulus}#replayRecenterFollow"}
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
              {target(@stimulus, "replaySpeedSlider")}
              data-action={"input->#{@stimulus}#replaySpeedChange"}
              title={r(@locale, "replay_speed")}
              aria-label={r(@locale, "replay_speed")}
            />
            <span class="replay-speed-label" {target(@stimulus, "replaySpeedLabel")}>2x</span>
          </div>
          <div class="replay-cycle-controls hidden" {target(@stimulus, "replayCycleControls")}>
            <button
              type="button"
              data-action={"click->#{@stimulus}#replayCyclePrev"}
              title={r(@locale, "previous_point")}
              aria-label={r(@locale, "previous_point")}
            >
              {r(@locale, "larr")}
            </button>
            <span class="replay-point-counter" {target(@stimulus, "replayPointCounter")}>
              {r(@locale, "point_1_of_1")}
            </span>
            <button
              type="button"
              data-action={"click->#{@stimulus}#replayCycleNext"}
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
        <div class="replay-scrubber-track" {target(@stimulus, "replayScrubberTrack")}>
          <div class="replay-density-container" {target(@stimulus, "replayDensityContainer")}></div>
          <input
            type="range"
            class="replay-scrubber"
            min="0"
            max="1439"
            value="720"
            {target(@stimulus, "replayScrubber")}
            data-action={"input->#{@stimulus}#replayScrubberHover"}
            aria-label={r(@locale, "replay_scrubber_time_of_day")}
          />
        </div>
        <span class="replay-time-label">23:59</span>
      </div>
    </div>
    """
  end

  defp target(stimulus, name), do: [{"data-#{stimulus}-target", name}]

  defp r(locale, key), do: t(locale, "shared.replay_panel." <> key, %{})
end

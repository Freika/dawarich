defmodule DawarichWeb.MapReplay do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  alias DawarichWeb.Icon

  attr :locale, :string, required: true
  attr :stimulus, :string, default: "maps--maplibre"
  attr :show_day_nav, :boolean, default: false
  attr :native, :boolean, default: false
  attr :id, :string, default: nil
  attr :hook, :string, default: "public"

  def replay_panel(assigns) do
    ~H"""
    <div
      id={@id}
      phx-update={@id && "ignore"}
      class="replay-panel hidden"
      {panel(@native && @hook)}
      {target(@native && @hook, @stimulus, "replayPanel")}
    >
      <button
        type="button"
        class="replay-close"
        {action(@native && @hook, @stimulus, "toggleReplay", "click")}
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
            {action(@native && @hook, @stimulus, "replayPrevDay", "click")}
            {target(@native && @hook, @stimulus, "replayPrevDayButton")}
            title={r(@locale, "previous_day")}
            aria-label={r(@locale, "previous_day")}
          >
            {r(@locale, "larr")}
          </button>
          <div class="replay-day-info">
            <span class="replay-day-display" {target(@native && @hook, @stimulus, "replayDayDisplay")}>
              {r(@locale, "no_data_loaded")}
            </span>
            <span class="replay-day-count" {target(@native && @hook, @stimulus, "replayDayCount")}></span>
          </div>
          <button
            :if={@show_day_nav}
            type="button"
            {action(@native && @hook, @stimulus, "replayNextDay", "click")}
            {target(@native && @hook, @stimulus, "replayNextDayButton")}
            title={r(@locale, "next_day")}
            aria-label={r(@locale, "next_day")}
          >
            {r(@locale, "rarr")}
          </button>
        </div>

        <div class="replay-time-block">
          <span
            class="replay-time-display"
            {target(@native && @hook, @stimulus, "replayTimeDisplay")}
            aria-live="polite"
          >
            --:--
          </span>
          <span
            class="replay-speed-display"
            {target(@native && @hook, @stimulus, "replaySpeedDisplay")}
          ></span>
          <span
            class="replay-data-indicator hidden"
            {target(@native && @hook, @stimulus, "replayDataIndicator")}
            role="status"
          >
            {r(@locale, "no_data")}
          </span>
        </div>

        <div class="replay-action-controls">
          <button
            type="button"
            class="replay-play-btn"
            {target(@native && @hook, @stimulus, "replayPlayButton")}
            {action(@native && @hook, @stimulus, "replayTogglePlayback", "click")}
            title={r(@locale, "play_pause")}
            aria-label={r(@locale, "play_or_pause_replay")}
          >
            <span class="play-icon" {target(@native && @hook, @stimulus, "replayPlayIcon")}>&#9658;</span>
            <span class="pause-icon hidden" {target(@native && @hook, @stimulus, "replayPauseIcon")}>&#10074;&#10074;</span>
          </button>
          <button
            type="button"
            class="replay-follow-btn"
            {target(@native && @hook, @stimulus, "replayFollowButton")}
            {action(@native && @hook, @stimulus, "replayRecenterFollow", "click")}
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
              {target(@native && @hook, @stimulus, "replaySpeedSlider")}
              {action(@native && @hook, @stimulus, "replaySpeedChange", "input")}
              title={r(@locale, "replay_speed")}
              aria-label={r(@locale, "replay_speed")}
            />
            <span class="replay-speed-label" {target(@native && @hook, @stimulus, "replaySpeedLabel")}>2x</span>
          </div>
          <div
            class="replay-cycle-controls hidden"
            {target(@native && @hook, @stimulus, "replayCycleControls")}
          >
            <button
              type="button"
              {action(@native && @hook, @stimulus, "replayCyclePrev", "click")}
              title={r(@locale, "previous_point")}
              aria-label={r(@locale, "previous_point")}
            >
              {r(@locale, "larr")}
            </button>
            <span
              class="replay-point-counter"
              {target(@native && @hook, @stimulus, "replayPointCounter")}
            >
              {r(@locale, "point_1_of_1")}
            </span>
            <button
              type="button"
              {action(@native && @hook, @stimulus, "replayCycleNext", "click")}
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
        <div
          class="replay-scrubber-track"
          {target(@native && @hook, @stimulus, "replayScrubberTrack")}
        >
          <div
            class="replay-density-container"
            {target(@native && @hook, @stimulus, "replayDensityContainer")}
          >
          </div>
          <input
            type="range"
            class="replay-scrubber"
            min="0"
            max="1439"
            value="720"
            {target(@native && @hook, @stimulus, "replayScrubber")}
            {action(@native && @hook, @stimulus, "replayScrubberHover", "input")}
            aria-label={r(@locale, "replay_scrubber_time_of_day")}
          />
        </div>
        <span class="replay-time-label">23:59</span>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :locale, :string, required: true

  def opener(assigns) do
    ~H"""
    <button
      type="button"
      data-map-replay-open
      class="btn btn-sm h-auto min-h-10 whitespace-normal"
      aria-controls={@id}
    >{r(@locale, "play_or_pause_replay")}</button>
    """
  end

  defp panel(false), do: []
  defp panel("public"), do: [{"data-public-replay-panel", true}, {"hidden", true}]
  defp panel(hook), do: [{"data-#{hook}-replay-panel", true}]

  defp target(false, stimulus, name), do: [{"data-#{stimulus}-target", name}]
  defp target(hook, _stimulus, name), do: [{"data-#{hook}-replay-target", name}]

  defp action(false, stimulus, name, event),
    do: [{"data-action", "#{event}->#{stimulus}##{name}"}]

  defp action(hook, _stimulus, name, _event), do: [{"data-#{hook}-replay-action", name}]

  defp r(locale, key), do: t(locale, "shared.replay_panel." <> key, %{})
end

defmodule DawarichWeb.NativeMapReplay do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  attr :id, :string, required: true
  attr :locale, :string, required: true
  attr :opener, :boolean, default: true

  def panel(assigns) do
    ~H"""
    <button
      :if={@opener}
      type="button"
      data-map-replay-open
      class="btn btn-sm h-auto min-h-10 whitespace-normal"
      aria-controls={@id}
    >{r(@locale, "play_or_pause_replay")}</button>
    <section
      id={@id}
      phx-update="ignore"
      data-map-replay-panel
      hidden
      class="relative z-10 w-full min-w-0 rounded-lg bg-base-100 p-3 shadow-lg"
    >
      <div class="flex min-w-0 flex-wrap items-center gap-2">
        <button
          type="button"
          data-map-replay-close
          class="btn btn-sm h-auto whitespace-normal"
          aria-label={r(@locale, "close_replay")}
        >{r(@locale, "close_replay")}</button>
        <button
          type="button"
          data-replay="prev"
          class="btn btn-sm"
          aria-label={r(@locale, "previous_day")}
        >←</button>
        <span data-replay="day" class="min-w-0 break-words [overflow-wrap:anywhere]">{r(
          @locale,
          "no_data_loaded"
        )}</span>
        <span data-replay="dayCount" class="min-w-0 break-words [overflow-wrap:anywhere]"></span>
        <button
          type="button"
          data-replay="next"
          class="btn btn-sm"
          aria-label={r(@locale, "next_day")}
        >→</button>
        <span data-replay="time" aria-live="polite">--:--</span>
        <span data-replay="velocity"></span>
        <span
          data-replay="noData"
          hidden
          role="status"
          class="min-w-0 break-words [overflow-wrap:anywhere]"
        >{r(@locale, "no_data")}</span>
        <button
          type="button"
          data-replay="play"
          class="btn btn-sm"
          aria-pressed="false"
          aria-label={r(@locale, "play_or_pause_replay")}
        >▶ / Ⅱ</button>
        <button
          type="button"
          data-replay="follow"
          class="btn btn-sm h-auto whitespace-normal"
          aria-pressed="false"
        >{r(@locale, "recenter_and_follow_the_marker")}</button>
        <input
          type="range"
          data-replay="speed"
          min="1"
          max="4"
          value="2"
          step="1"
          class="range range-xs w-24 max-w-full"
          aria-label={r(@locale, "replay_speed")}
        />
        <span data-replay="speedLabel">2x</span>
        <div data-replay="cycle" hidden class="flex min-w-0 flex-wrap items-center gap-1">
          <button
            type="button"
            data-replay="cyclePrev"
            class="btn btn-sm"
            aria-label={r(@locale, "previous_point")}
          >←</button>
          <span data-replay="cycleCount"></span>
          <button
            type="button"
            data-replay="cycleNext"
            class="btn btn-sm"
            aria-label={r(@locale, "next_point")}
          >→</button>
        </div>
      </div>
      <input
        type="range"
        data-replay="scrubber"
        min="0"
        max="1439"
        value="0"
        step="1"
        class="range range-xs mt-3 w-full min-w-0"
        aria-label={r(@locale, "replay_scrubber_time_of_day")}
      />
      <div
        data-replay-density
        class="mt-2 flex min-w-0 w-full gap-px"
        aria-label={r(@locale, "replay_scrubber_time_of_day")}
      >
      </div>
      <div
        data-replay-photos
        class="pointer-events-auto relative mt-3 h-24 w-full min-w-0 overflow-hidden"
      >
      </div>
    </section>
    """
  end

  defp r(locale, key), do: t(locale, "shared.replay_panel." <> key, %{})
end

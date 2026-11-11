import { ReplayManager } from "maps_maplibre/managers/replay_manager"

/**
 * One scrubber over several days: the day tabs and the tip that names the
 * moment under the pointer.
 * Mixed into ReplayPanel; `this` is the ReplayPanel.
 */
export const range = {
  setupRange() {
    const days = this.rangeDays
    this._rangeDensity = days
      ? this.replayManager.getRangeDensity(
          Math.min(48, Math.round(144 / days.length)),
        )
      : null
    this.c.replayPanelTarget.classList.toggle("replay-panel--range", !!days)
    if (this.c.hasReplayScrubberTarget) {
      this.c.replayScrubberTarget.max = (days?.length || 1) * 1440 - 1
    }
    if (!this.c.hasReplayDaySegmentsTarget) return

    const segments = this.c.replayDaySegmentsTarget
    segments.replaceChildren(
      ...(days || []).map((day) => {
        const button = document.createElement("button")
        button.type = "button"
        button.className = "replay-day-segment"
        button.dataset.day = day
        button.textContent = this.dayLabel(day, { day: "numeric" })
        return button
      }),
    )
    segments.onclick = (event) => {
      const day = event.target.closest("[data-day]")?.dataset.day
      if (!day) return
      this.syncToDay(day)
      this.syncAccordion()
    }
  },

  dayLabel(day, options = {}) {
    return new Date(`${day}T12:00:00`).toLocaleDateString(
      document.documentElement.lang || undefined,
      { weekday: "short", ...options },
    )
  },

  // Hovering the scrubber names the moment under the pointer, and a press or
  // drag lands on exactly that moment (a native range input offsets the value
  // by the thumb width, which is minutes on a multi-day scale).
  bindScrubberTip() {
    if (!this.c.hasReplayScrubberTarget) return
    const scrubber = this.c.replayScrubberTarget
    const track = scrubber.parentElement
    let tip = track.parentElement.querySelector(".replay-scrubber-tip")
    if (!tip) {
      tip = document.createElement("div")
      tip.className = "replay-scrubber-tip"
      tip.hidden = true
      track.parentElement.appendChild(tip)
    }

    const point = (event) => {
      const rect = scrubber.getBoundingClientRect()
      const ratio = Math.min(
        Math.max((event.clientX - rect.left) / rect.width, 0),
        1,
      )
      const value = Math.round(ratio * Number(scrubber.max))
      const time = ReplayManager.formatMinuteToTime(value % 1440)
      const days = this.rangeDays
      tip.textContent = days
        ? `${this.dayLabel(days[Math.floor(value / 1440)])} ${time}`
        : time
      tip.style.left = `${track.offsetLeft + ratio * rect.width}px`
      tip.hidden = false
      return value
    }
    scrubber.onpointerdown = (event) => {
      this._pointerValue = point(event)
    }
    scrubber.onpointermove = (event) => {
      const value = point(event)
      if (this._pointerValue !== null && this._pointerValue !== undefined) {
        this._pointerValue = value
      }
    }
    scrubber.onpointerup = scrubber.onpointercancel = () => {
      this._pointerValue = null
    }
    scrubber.onpointerleave = () => {
      tip.hidden = true
    }
  },
}

import { translate } from "i18n"
import { ReplayManager } from "maps_maplibre/managers/replay_manager"

const KM_PER_MILE = 1.609344

/**
 * Replay readouts: day, time, speed, point count, density and cycle controls.
 * Mixed into ReplayPanel; `this` is the ReplayPanel.
 */
export const displays = {
  updateDayDisplay() {
    if (!this.c.hasReplayDayDisplayTarget || !this.replayManager) return
    this.c.replayDayDisplayTarget.textContent =
      this.replayManager.getCurrentDayDisplay()
  },

  updateDayButtons() {
    if (!this.replayManager) return
    if (this.c.hasReplayPrevDayButtonTarget) {
      this.c.replayPrevDayButtonTarget.disabled =
        !this.replayManager.canGoPrev()
    }
    if (this.c.hasReplayNextDayButtonTarget) {
      this.c.replayNextDayButtonTarget.disabled =
        !this.replayManager.canGoNext()
    }
  },

  updateTimeDisplay(minute, showNoData = false) {
    if (this.c.hasReplayTimeDisplayTarget) {
      this.c.replayTimeDisplayTarget.textContent =
        ReplayManager.formatMinuteToTime(minute)
    }
    if (this.c.hasReplayDataIndicatorTarget) {
      if (showNoData) {
        this.c.replayDataIndicatorTarget.classList.remove("hidden")
        this.c.replayDataIndicatorTarget.textContent = translate(
          "replay.no_data_at_this_time",
        )
      } else {
        this.c.replayDataIndicatorTarget.classList.add("hidden")
      }
    }
  },

  getPointVelocity(point) {
    if (!point) return null
    if (point.properties?.velocity !== undefined)
      return point.properties.velocity
    if (point.velocity !== undefined) return point.velocity
    return null
  },

  updateSpeedDisplay(velocity) {
    if (!this.c.hasReplaySpeedDisplayTarget) return
    if (velocity !== null && velocity !== undefined && velocity !== "") {
      const speedMs = parseFloat(velocity)
      if (!Number.isNaN(speedMs) && speedMs > 0) {
        const kmh = speedMs * 3.6
        this.c.replaySpeedDisplayTarget.textContent =
          this._distanceUnit() === "mi"
            ? translate("replay.speed_mph", {
                speed: Math.round(kmh / KM_PER_MILE),
              })
            : translate("replay.speed", { speed: Math.round(kmh) })
        return
      }
    }
    this.c.replaySpeedDisplayTarget.textContent = ""
  },

  updateDayCount() {
    if (!this.c.hasReplayDayCountTarget || !this.replayManager) return
    const dayCount = this.replayManager.getDayCount()
    const currentIndex = this.replayManager.currentDayIndex + 1
    this.c.replayDayCountTarget.textContent = translate("replay.day_count", {
      current: currentIndex,
      total: dayCount,
    })
  },

  renderDensity() {
    if (!this.c.hasReplayDensityContainerTarget || !this.replayManager) return
    const container = this.c.replayDensityContainerTarget
    const density = this.replayManager.getDataDensity(48)

    while (container.firstChild) container.removeChild(container.firstChild)

    for (const value of density) {
      const bar = document.createElement("div")
      bar.className = "replay-density-bar"
      if (value > 0) {
        bar.classList.add("has-data")
        if (value > 0.5) bar.classList.add("high-density")
      }
      container.appendChild(bar)
    }
  },

  updateCycleControls(minute) {
    if (!this.c.hasReplayCycleControlsTarget || !this.replayManager) return
    const count = this.replayManager.getPointCountAtMinute(minute)
    if (count > 1) {
      this.c.replayCycleControlsTarget.classList.remove("hidden")
      if (this.c.hasReplayPointCounterTarget) {
        const currentIndex = (this.replayManager.cycleIndex % count) + 1
        this.c.replayPointCounterTarget.textContent = translate(
          "replay.point_count",
          { current: currentIndex, total: count },
        )
      }
    } else {
      this.c.replayCycleControlsTarget.classList.add("hidden")
    }
  },

  hideCycleControls() {
    if (this.c.hasReplayCycleControlsTarget) {
      this.c.replayCycleControlsTarget.classList.add("hidden")
    }
  },
}

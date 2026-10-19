import { speedFromSlider } from "./playback.js"
import { createScrubber } from "./scrubber.js"

export function createReplayPanel({ elements, replay, translate }) {
  const { manager } = replay
  const bindings = []
  let currentMinute = 0
  const scrubber = createScrubber({
    input: elements.scrubber,
    onMinute: (minute) => {
      replay.seek(minute)
      showMinute(minute)
    },
  })

  const bind = (element, type, handler) => {
    element.addEventListener(type, handler)
    bindings.push(() => element.removeEventListener(type, handler))
  }

  function hide(element, hidden) {
    if (!element) return
    element.hidden = hidden
    element.classList?.toggle("hidden", hidden)
  }

  function setPlaying(playing) {
    elements.play.setAttribute("aria-pressed", String(playing))
    hide(elements.playIcon, playing)
    hide(elements.pauseIcon, !playing)
  }

  function showMinute(minute) {
    currentMinute = minute
    scrubber.set(minute)
    if (elements.cycle) {
      const count = manager.getPointCountAtMinute(minute)
      hide(elements.cycle, count < 2)
      elements.cycleCount.textContent = translate("replay.point_count", {
        current: (manager.cycleIndex % count) + 1,
        total: count,
      })
    }
    elements.time.textContent = manager.formatCurrentMinute(minute)
    hide(elements.noData, manager.hasDataAtMinute(minute))
    if (!elements.noData.hidden)
      elements.noData.textContent = translate("replay.no_data_at_this_time")
  }

  function showVelocity(point) {
    const value = Number.parseFloat(
      point?.properties?.velocity ?? point?.velocity,
    )
    elements.velocity.textContent =
      value > 0
        ? translate("replay.speed", { speed: Math.round(value * 3.6) })
        : ""
  }

  function refresh() {
    for (const [key, value] of Object.entries({
      "day-count": manager.getDayCount(),
      "day-index": manager.currentDayIndex,
      "point-count": manager.getCurrentDayPointCount(),
    }))
      elements.dayCount.setAttribute?.(`data-replay-${key}`, String(value))
    elements.day.textContent = manager.getCurrentDayDisplay()
    elements.dayCount.textContent = translate("replay.day_count", {
      current: manager.currentDayIndex + 1,
      total: manager.getDayCount(),
    })
    if (elements.prev) elements.prev.disabled = !manager.canGoPrev()
    if (elements.next) elements.next.disabled = !manager.canGoNext()
    scrubber.setRange(manager.getCurrentDayLengthMinutes())
  }

  function changeDay(step) {
    replay.pause()
    setPlaying(false)
    if (!(step < 0 ? manager.prevDay() : manager.nextDay())) return
    refresh()
    const minute = manager.findNearestMinuteWithPoints(0)
    if (minute === null) return
    replay.seek(minute)
    showMinute(minute)
  }

  bind(elements.play, "click", () => {
    if (replay.playing) replay.pause()
    else replay.play()
    setPlaying(replay.playing)
  })
  bind(elements.speed, "input", () => {
    const speed = speedFromSlider(elements.speed.value)
    elements.speedLabel.textContent = `${speed}x`
    replay.setSpeed(speed)
  })
  if (elements.prev) bind(elements.prev, "click", () => changeDay(-1))
  if (elements.next) bind(elements.next, "click", () => changeDay(1))
  bind(elements.follow, "click", () => replay.recenter())

  if (elements.cycle) {
    for (const [element, advance] of [
      [elements.cyclePrev, () => manager.cyclePrev()],
      [elements.cycleNext, () => manager.cycleNext(currentMinute)],
    ])
      bind(element, "click", () => {
        replay.pause()
        setPlaying(false)
        advance()
        replay.seek(currentMinute)
        showMinute(currentMinute)
      })
  }
  refresh()

  return {
    onState({ minute, point, dayChanged }) {
      setPlaying(replay.playing)
      if (dayChanged) refresh()
      if (minute != null) showMinute(minute)
      if (point) showVelocity(point)
    },
    stopped: () => setPlaying(false),
    refresh,
    destroy() {
      setPlaying(false)
      for (const unbind of bindings.splice(0)) unbind()
      scrubber.destroy()
      for (const key of ["day-count", "day-index", "point-count"])
        elements.dayCount.removeAttribute?.(`data-replay-${key}`)
    },
  }
}

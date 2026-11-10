import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/maps_maplibre/managers/replay_panel.js",
      import.meta.url,
    ),
    "utf8",
  )
)
  .replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
  .replace("export class ReplayPanel", "class ReplayPanel")
  .concat("\nglobalThis.ReplayPanel = ReplayPanel\n")

const context = { translate: (key) => key }
vm.runInNewContext(source, context)

// A panel over `dayCount` days whose manager only tracks the current day.
function panel(dayCount, { segments = true } = {}) {
  const days = Array.from({ length: dayCount }, (_, i) => `2026-11-0${i + 1}`)
  const manager = {
    availableDays: days,
    currentDayIndex: 0,
    goToDay(day) {
      const index = days.indexOf(day)
      if (index === -1 || index === this.currentDayIndex) return false
      this.currentDayIndex = index
      return true
    },
    getCurrentDay() {
      return days[this.currentDayIndex]
    },
  }
  const replay = new context.ReplayPanel({
    controller: {
      hasReplayDaySegmentsTarget: segments,
      hasReplayScrubberTarget: true,
      replayScrubberTarget: { value: "0" },
    },
  })
  replay.replayManager = manager
  const minutes = []
  replay.handleMinuteChange = (minute) => minutes.push(minute)
  return { replay, manager, minutes }
}

test("a scrubber over three days turns its value into a day and a minute", () => {
  const { replay, manager, minutes } = panel(3)
  replay.scrubberHover({ target: { value: String(1440 + 801) } })

  assert.equal(manager.getCurrentDay(), "2026-11-02")
  assert.deepEqual(minutes, [801])
})

test("the scrubber position carries the current day's offset", () => {
  const { replay, manager } = panel(3)
  manager.goToDay("2026-11-03")
  replay.setScrubber(65)

  assert.equal(replay.c.replayScrubberTarget.value, 2 * 1440 + 65)
  assert.equal(replay.scrubberMinute, 65)
})

test("a press lands on the pointed moment, not on the native thumb value", () => {
  const { replay, minutes } = panel(3)
  replay._pointerValue = 1440 + 30
  const target = { value: String(1440 + 41) }
  replay.scrubberHover({ target })

  assert.equal(target.value, 1440 + 30)
  assert.deepEqual(minutes, [30])
})

test("one day, a long period, or a host without day labels keep a one-day scrubber", () => {
  for (const { replay, manager, minutes } of [
    panel(1),
    panel(15),
    panel(3, { segments: false }),
  ]) {
    assert.equal(replay.rangeDays, null)
    replay.scrubberHover({ target: { value: "801" } })
    assert.equal(manager.currentDayIndex, 0)
    assert.deepEqual(minutes, [801])
  }
})

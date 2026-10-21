import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

const replaySelector = (key) =>
  ({
    cyclePrev: '[data-native-replay-action="replayCyclePrev"]',
    cycleNext: '[data-native-replay-action="replayCycleNext"]',
  })[key] ?? `[data-native-replay-target="${REPLAY_TARGETS[key]}"]`
const REPLAY_TARGETS = {"play": "replayPlayButton", "speed": "replaySpeedSlider", "speedLabel": "replaySpeedLabel", "day": "replayDayDisplay", "dayCount": "replayDayCount", "time": "replayTimeDisplay", "velocity": "replaySpeedDisplay", "noData": "replayDataIndicator", "follow": "replayFollowButton", "scrubber": "replayScrubber", "prev": "replayPrevDayButton", "next": "replayNextDayButton", "cycle": "replayCycleControls", "cycleCount": "replayPointCounter"}

test("native replay cycles colocated minute points without creating another clock", async () => {
  const f = fixture({
    uiLabels: { "replay.point_count": "Point {current} of {total}" },
  })
  const controls = Object.fromEntries(
    [
      "play",
      "speed",
      "speedLabel",
      "prev",
      "next",
      "day",
      "dayCount",
      "time",
      "velocity",
      "noData",
      "follow",
      "scrubber",
      "cycle",
      "cyclePrev",
      "cycleNext",
      "cycleCount",
    ].map((key) => [key, new Element()]),
  )
  for (const [key, value] of Object.entries(controls))
    f.nodes.set(replaySelector(key), value)
  f.owner.source.snapshot = async () => ({
    points: [13, 14].map((longitude) => ({
      timestamp: 1774861200,
      longitude,
      latitude: 52,
    })),
  })
  await f.owner.mount()
  await f.owner.replay.open()
  assert.equal(controls.cycle.hidden, false)
  assert.equal(controls.cycleCount.textContent, "Point 1 of 2")
  controls.cycleNext.emit("click")
  assert.equal(
    f.sources.get("native-replay-marker").data.geometry.coordinates[0],
    14,
  )
  assert.equal(controls.cycleCount.textContent, "Point 2 of 2")
  controls.cyclePrev.emit("click")
  assert.equal(
    f.sources.get("native-replay-marker").data.geometry.coordinates[0],
    13,
  )
  f.owner.replay.close()
  assert.equal(controls.cycleNext.listeners.get("click").size, 0)
  f.owner.destroy()
})

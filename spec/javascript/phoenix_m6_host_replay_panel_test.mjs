import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

const replaySelector = (key) =>
  ({
    cyclePrev: '[data-native-replay-action="replayCyclePrev"]',
    cycleNext: '[data-native-replay-action="replayCycleNext"]',
  })[key] ?? `[data-native-replay-target="${REPLAY_TARGETS[key]}"]`
const REPLAY_TARGETS = {"play": "replayPlayButton", "speed": "replaySpeedSlider", "speedLabel": "replaySpeedLabel", "day": "replayDayDisplay", "dayCount": "replayDayCount", "time": "replayTimeDisplay", "velocity": "replaySpeedDisplay", "noData": "replayDataIndicator", "follow": "replayFollowButton", "scrubber": "replayScrubber", "prev": "replayPrevDayButton", "next": "replayNextDayButton", "cycle": "replayCycleControls", "cycleCount": "replayPointCounter"}

test("native map host replay binds day scrubber and speed then unbinds panel on close", async () => {
  const f = fixture()
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
    ].map((key) => [key, new Element()]),
  )
  for (const [key, control] of Object.entries(controls))
    f.nodes.set(replaySelector(key), control)
  await f.owner.mount()
  f.owner.source.snapshot = async () => ({
    points: [
      { timestamp: 1774861200, longitude: 13, latitude: 52 },
      { timestamp: 1774947600, longitude: 14, latitude: 53 },
    ],
  })
  await f.owner.replay.open()
  assert.ok(controls.day.textContent)
  controls.next.emit("click")
  assert.equal(f.owner.replay.manager.currentDayIndex, 1)
  controls.scrubber.value = "500"
  controls.scrubber.emit("input")
  assert.ok(controls.time.textContent)
  controls.speed.value = "4"
  controls.speed.emit("input")
  assert.equal(controls.speedLabel.textContent, "10x")
  f.owner.replay.close()
  assert.equal(controls.next.listeners.get("click").size, 0)
  assert.equal(controls.scrubber.listeners.get("input").size, 0)
  f.owner.destroy()
})

test("native replay wrapper forwards the admitted reconnect receipt", async () => {
  const { installHostReplay } = await import(
    "../../app-phoenix/assets/js/map/replay/host.js"
  )
  let received, dispose
  const owner = {
    config: { range: {} },
    update: async () => "ready",
    reconnect: async (receipt) => {
      received = receipt
      return "ready"
    },
  }
  installHostReplay({
    owner,
    map: {},
    root: {
      querySelector: () => null,
      addEventListener() {},
      removeEventListener() {},
    },
    lifetime: {
      own: (callback) => {
        dispose = callback
      },
    },
  })
  const receipt = { kinds: ["points"] }
  assert.equal(await owner.reconnect(receipt), "ready")
  assert.equal(received, receipt)
  dispose()
})

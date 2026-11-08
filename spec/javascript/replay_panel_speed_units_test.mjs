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

const phrases = {
  "replay.speed": "%{speed} km/h",
  "replay.speed_mph": "%{speed} mph",
}
const context = {
  translate: (key, values) =>
    phrases[key].replace("%{speed}", String(values.speed)),
}
vm.runInNewContext(source, context)

function speedShown(distanceUnit, metersPerSecond) {
  const display = { textContent: "" }
  const panel = new context.ReplayPanel({
    controller: {
      hasReplaySpeedDisplayTarget: true,
      replaySpeedDisplayTarget: display,
    },
    distanceUnit,
  })
  panel.updateSpeedDisplay(metersPerSecond)
  return display.textContent
}

test("shows km/h by default", () => {
  assert.equal(speedShown(undefined, 10), "36 km/h")
})

test("shows km/h for kilometre users", () => {
  assert.equal(
    speedShown(() => "km", 10),
    "36 km/h",
  )
})

test("shows mph for mile users", () => {
  assert.equal(
    speedShown(() => "mi", 10),
    "22 mph",
  )
})

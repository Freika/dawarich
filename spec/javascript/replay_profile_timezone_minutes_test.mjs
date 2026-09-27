import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

process.env.TZ = "Europe/Berlin"

const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const importSource = (source) =>
  import(
    `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
  )

const managerSource = (
  await read("maps_maplibre/managers/replay_manager.js")
).replace(/^import.*\n/gm, "")
const { ReplayManager } = await importSource(managerSource)
const panelSource = (
  await read("maps_maplibre/managers/replay_panel.js")
).replace(/^import.*\n/gm, "")
const { ReplayPanel } = await importSource(panelSource)

const dateManagerSource = await read(
  "controllers/maps/maplibre/date_manager.js",
)
const importedNames = []
const mapBody = (await read("controllers/maps/maplibre_controller.js")).replace(
  /^import\s+([\s\S]*?)\s+from\s+"[^"]+"\n/gm,
  (_statement, clause) => {
    const named = clause.match(/\{([\s\S]*)\}/)?.[1] ?? ""
    for (const part of named.split(",")) {
      if (part.trim()) importedNames.push(part.trim())
    }
    const defaultName = clause.replace(/\{[\s\S]*\}/, "").trim()
    if (defaultName) importedNames.push(defaultName)
    return ""
  },
)
const stubs = importedNames.map((name) => {
  if (name === "Controller") return "class Controller {}"
  if (name === "DateManager")
    return dateManagerSource.replace("export class", "class")
  if (name === "timeOverlapOpacityExpr")
    return "const timeOverlapOpacityExpr = (...args) => args"
  return `const ${name} = new Proxy(function () {}, { get: () => () => {}, construct: () => anything })`
})
const anything = `const anything = new Proxy(function () {}, {
  get: (_target, property) => (property === "then" ? undefined : anything),
  apply: () => anything,
  construct: () => anything,
})`
const { default: MapController } = await importSource(
  `${anything}\n${stubs.join("\n")}\n${mapBody}`,
)

const point = (timestamp) => ({
  geometry: { coordinates: [0, 0] },
  properties: { timestamp },
})

function replayManager() {
  const manager = new ReplayManager({ timezone: "America/Los_Angeles" })
  manager.setPoints([
    point("2020-04-18T03:00:00Z"),
    point("2020-04-18T04:00:00Z"),
    point("2020-04-18T05:00:00Z"),
  ])
  return manager
}

function replayPanel(manager) {
  const panel = new ReplayPanel({
    controller: {
      hasReplayScrubberTarget: true,
      replayScrubberTarget: { value: 1320 },
    },
    timezone: "America/Los_Angeles",
  })
  panel.replayManager = manager
  panel.showMarker = () => {}
  panel.flyToPoint = () => {}
  panel.highlightPoint = () => {}
  panel.setFollowActive = () => {}
  panel.setPlayingState = () => {}
  panel.updateSpeedDisplay = () => {}
  panel.hideCycleControls = () => {}
  panel.showMarkerAt = () => {}
  panel.panToFollow = () => {}
  panel.updateRevealedPhotos = () => {}
  return panel
}

test("replay manager indexes 05:00Z as 22:00 in the profile timezone", () => {
  const manager = replayManager()

  assert.equal(manager.minuteOfDay(new Date("2020-04-18T05:00:00Z")), 1320)
})

test("replay manager defaults minutes to UTC without a profile timezone", () => {
  const manager = new ReplayManager()
  manager.setPoints([point("2020-04-18T05:00:00Z")])

  assert.equal(manager.minuteOfDay(new Date("2020-04-18T05:00:00Z")), 300)
  assert.equal(manager.getCurrentDayLengthMinutes(), 1440)
})

test("replay manager uses elapsed minutes across the fall-back hour", () => {
  const manager = new ReplayManager({ timezone: "America/Los_Angeles" })
  manager.setPoints([
    point("2020-11-01T08:50:00Z"),
    point("2020-11-01T09:10:00Z"),
    point("2020-11-02T07:40:00Z"),
  ])

  assert.equal(manager.minuteOfDay(new Date("2020-11-01T08:50:00Z")), 110)
  assert.equal(manager.minuteOfDay(new Date("2020-11-01T09:10:00Z")), 130)
  assert.equal(manager.getCurrentDayLengthMinutes(), 1500)
  assert.ok(manager.getDataDensity(48)[47] > 0)
  assert.equal(manager.formatCurrentMinute(110), "01:50 PDT")
  assert.equal(manager.formatCurrentMinute(130), "01:10 PST")
})

test("replay manager uses the shortened spring-forward day", () => {
  const manager = new ReplayManager({ timezone: "America/Los_Angeles" })
  manager.setPoints([point("2020-03-08T10:30:00Z")])

  assert.equal(manager.minuteOfDay(new Date("2020-03-08T10:30:00Z")), 150)
  assert.equal(manager.getCurrentDayLengthMinutes(), 1380)
  assert.equal(manager.formatCurrentMinute(150), "03:30")
})

test("replay panel scales its scrubber to the current local day", () => {
  const manager = new ReplayManager({ timezone: "America/Los_Angeles" })
  manager.setPoints([
    point("2020-11-01T08:50:00Z"),
    point("2020-11-01T09:10:00Z"),
    point("2020-11-03T08:00:00Z"),
  ])
  const panel = replayPanel(manager)

  panel.setInitialScrubberPosition()

  assert.equal(panel.c.replayScrubberTarget.max, 1499)
  panel.goToDay("2020-11-03")
  assert.equal(panel.c.replayScrubberTarget.max, 1439)
})

test("replay panel uses profile minutes when jumping and starting playback", (t) => {
  const manager = replayManager()
  const panel = replayPanel(manager)
  const oldRequestAnimationFrame = globalThis.requestAnimationFrame
  globalThis.requestAnimationFrame = () => 1
  t.after(() => {
    globalThis.requestAnimationFrame = oldRequestAnimationFrame
  })
  panel.replayPoints = manager.getPointsForDay("2020-04-17")

  panel.jumpToMinute(1260)
  assert.equal(panel.replayPointIndex, 1)

  panel.startPlayback()
  assert.equal(panel.replayPointIndex, 2)
})

test("replay panel updates the scrubber with the profile minute", (t) => {
  const manager = replayManager()
  const panel = replayPanel(manager)
  const oldRequestAnimationFrame = globalThis.requestAnimationFrame
  globalThis.requestAnimationFrame = () => 1
  t.after(() => {
    globalThis.requestAnimationFrame = oldRequestAnimationFrame
  })
  panel.replayActive = true
  panel.replaySpeed = 2
  panel.replayPoints = manager.getPointsForDay("2020-04-17")
  panel.replayPointIndex = 1
  panel.replayLastTime = 0
  panel.replaySegmentDurationMs = 1
  panel.replayCurrentCoords = { lon: 0, lat: 0 }
  panel.replayNextCoords = { lon: 0, lat: 0 }

  panel.frame()

  assert.equal(panel.c.replayScrubberTarget.value, 1320)
})

test("track replay seeds the scrubber with the profile minute", async () => {
  const minutes = []
  const map = Object.create(MapController.prototype)
  Object.assign(map, {
    hasReplayPanelTarget: true,
    replayPanelTarget: { classList: { contains: () => true } },
    timezoneValue: "America/Los_Angeles",
    _ensureReplayPanel() {},
    replayPanel: {
      isPlaying: false,
      manager: {
        hasData: () => true,
        minuteOfDay: () => 1320,
      },
      ensureOpen: async () => {},
      goToDay() {},
      setMinute: (minute) => minutes.push(minute),
      startPlayback() {},
    },
  })

  await map.replayTrack({
    currentTarget: { dataset: { trackStart: "2020-04-18T05:00:00Z" } },
  })

  assert.deepEqual(minutes, [1320])
})

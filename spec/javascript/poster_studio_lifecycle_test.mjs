import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/poster_studio_editor_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const prelude = `
class Controller {}
const translate = (key) => key
`
const moduleUrl = `data:text/javascript;base64,${Buffer.from(`${prelude}\n${source}`).toString("base64")}`
const { default: PosterStudioController } = await import(moduleUrl)

test("poster studio cannot switch to video during a range reload", () => {
  const calls = []
  const controller = new PosterStudioController()
  controller.rangeLoading = true
  controller.provider = { id: "map" }
  controller.close = () => calls.push("close")
  const originalDocument = globalThis.document
  globalThis.document = { dispatchEvent: () => calls.push("dispatch") }

  try {
    controller.switchToVideo()
  } finally {
    globalThis.document = originalDocument
  }

  assert.deepEqual(calls, [])
})

test("poster range reload disables its studio switch", () => {
  const controller = new PosterStudioController()
  controller.hasLoadButtonTarget = false
  controller.hasSwitchButtonTarget = true
  controller.switchButtonTarget = { disabled: false }

  controller.setLoadBusy(true)

  assert.equal(controller.rangeLoading, true)
  assert.equal(controller.switchButtonTarget.disabled, true)
})

function textController({ textOn = true, statsOn, statsLabel = "" }) {
  const controller = new PosterStudioController()
  controller.textToggleTarget = { checked: textOn }
  controller.titleInputTarget = { value: " Batumi " }
  controller.subtitleInputTarget = { value: "" }
  controller.coordsToggleTarget = { checked: false }
  controller.hasStatsToggleTarget = statsOn !== undefined
  controller.statsToggleTarget = { checked: statsOn }
  controller.statsLabelValue = statsLabel
  return controller
}

test("poster text carries the trip stats only when the block is switched on", () => {
  const on = textController({
    statsOn: true,
    statsLabel: "27.4 km · 8 Aug 2026",
  })
  const off = textController({
    statsOn: false,
    statsLabel: "27.4 km · 8 Aug 2026",
  })

  assert.equal(on.posterText().stats, "27.4 km · 8 Aug 2026")
  assert.equal(off.posterText().stats, "")
})

test("poster text drops the trip stats with the rest of the text", () => {
  const controller = textController({
    textOn: false,
    statsOn: true,
    statsLabel: "27.4 km",
  })

  assert.equal(controller.posterText().stats, "")
})

test("poster text has no stats where the studio has no stats block", () => {
  assert.equal(textController({}).posterText().stats, "")
})

test("save to gallery sends the switched-on trip stats to the server render", () => {
  const controller = textController({ statsOn: true, statsLabel: "27.4 km" })
  const field = () => ({ value: "" })
  for (const name of [
    "saveStats",
    "saveTitle",
    "saveName",
    "saveTheme",
    "saveLat",
    "saveLon",
    "saveDistance",
    "saveStartAt",
    "saveEndAt",
    "saveSource",
    "saveOpacity",
    "saveWidth",
  ])
    controller[`${name}Target`] = field()
  controller.saveButtonTarget = { disabled: false }
  controller.trackOpacityTarget = { value: "100" }
  controller.trackWidthTarget = { value: "100" }
  controller.previewMap = {
    getCenter: () => ({ lat: 52.5, lng: 13.4 }),
    getBounds: () => ({ getNorth: () => 52.6, getSouth: () => 52.4 }),
  }
  controller.provider = {
    dateRange: () => ({ startAt: "2026-08-08", endAt: "2026-08-09" }),
    trackSource: () => "routes",
  }
  let submitted = false
  controller.saveFormTarget = {
    requestSubmit: () => {
      submitted = true
    },
  }
  controller.setStatus = () => {}

  controller.saveToGallery()

  assert.equal(submitted, true)
  assert.equal(controller.saveStatsTarget.value, "27.4 km")
})

test("switching the text off also disables the trip stats toggle", () => {
  const controller = textController({ textOn: false, statsOn: true })
  const statsToggle = { checked: true, disabled: false }
  controller.statsToggleTargets = [statsToggle]
  controller.fontSelectTarget = {}
  controller.redrawOverlay = () => {}

  controller.textChanged()

  assert.equal(statsToggle.disabled, true)
})

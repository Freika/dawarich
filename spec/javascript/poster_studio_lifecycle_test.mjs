import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

process.env.TZ = "Europe/Berlin"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/poster_studio_editor_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const dateRangeSource = await readFile(
  new URL("../../app/javascript/video_studio/date_range.js", import.meta.url),
  "utf8",
)
const prelude = `
class Controller {}
const translate = (key) => key
${dateRangeSource}
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

test("poster range fields show profile wall time", () => {
  const controller = new PosterStudioController()
  controller.hasDateStartTarget = true
  controller.hasDateEndTarget = true
  controller.dateStartTarget = { value: "" }
  controller.dateEndTarget = { value: "" }
  controller.provider = {
    dateRange: () => ({
      startAt: "2020-04-17T07:00:00Z",
      endAt: "2020-04-18T06:59:00Z",
    }),
    timeZone: () => "America/Los_Angeles",
  }

  controller.seedDateInputs()

  assert.equal(controller.dateStartTarget.value, "2020-04-17T00:00")
  assert.equal(controller.dateEndTarget.value, "2020-04-17T23:59")
})

test("poster Today preset starts at the profile's midnight", () => {
  const RealDate = globalThis.Date
  globalThis.Date = class extends RealDate {
    constructor(...args) {
      super(...(args.length ? args : ["2020-04-18T05:00:00Z"]))
    }
  }
  try {
    const controller = new PosterStudioController()
    controller.provider = { timeZone: () => "America/Los_Angeles" }
    controller.dateStartTarget = { value: "" }
    controller.dateEndTarget = { value: "" }
    controller.applyDates = () => {}

    controller.presetRange({ currentTarget: { dataset: { range: "today" } } })

    assert.deepEqual(
      [controller.dateStartTarget.value, controller.dateEndTarget.value],
      ["2020-04-17T00:00", "2020-04-17T22:00"],
    )
  } finally {
    globalThis.Date = RealDate
  }
})

test("poster subtitle names the selected day in the profile timezone", () => {
  const controller = new PosterStudioController()
  controller.provider = {
    dateRange: () => ({
      startAt: "2020-04-17T00:00-07:00",
      endAt: "2020-04-17T23:59-07:00",
    }),
    timeZone: () => "America/Los_Angeles",
  }

  assert.equal(controller.dateRangeLabel(), "17 Apr 2020 – 17 Apr 2020")
})

import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const dateRangeSource = await readFile(
  new URL("../../app/javascript/video_studio/date_range.js", import.meta.url),
  "utf8",
)
const dateRangeUrl = `data:text/javascript;base64,${Buffer.from(dateRangeSource).toString("base64")}`
const { toLocalDateTimeInput } = await import(dateRangeUrl)
globalThis.__mapControlsToLocalDateTimeInput = toLocalDateTimeInput

const controllerSource = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/map_controls_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import .*\n/gm, "")
const prelude = `
class Controller {}
const toLocalDateTimeInput = globalThis.__mapControlsToLocalDateTimeInput
`
const controllerUrl = `data:text/javascript;base64,${Buffer.from(`${prelude}\n${controllerSource}`).toString("base64")}`
const { default: MapControlsController } = await import(controllerUrl)

test("date navigation keeps the shared map range controls synchronized", () => {
  const controller = new MapControlsController()
  controller.startTarget = { value: "" }
  controller.endTarget = { value: "" }
  controller.hasMobileLabelTarget = true
  controller.mobileLabelTarget = { textContent: "" }
  controller.localeValue = "en-GB"
  controller.timezoneValue = "Europe/Berlin"

  controller.dateNavigated({
    detail: {
      startAt: "2026-07-11T12:30:00Z",
      endAt: "2026-07-11T16:45:00Z",
    },
  })

  assert.equal(controller.startTarget.value, "2026-07-11T14:30")
  assert.equal(controller.endTarget.value, "2026-07-11T18:45")
  assert.match(controller.mobileLabelTarget.textContent, /11 July 2026/)
})

test("offset-less timeline navigation preserves its wall-clock fields", () => {
  const controller = new MapControlsController()
  controller.startTarget = { value: "" }
  controller.endTarget = { value: "" }
  controller.hasMobileLabelTarget = true
  controller.mobileLabelTarget = { textContent: "" }
  controller.localeValue = "en-GB"
  controller.timezoneValue = "Pacific/Auckland"

  controller.dateNavigated({
    detail: {
      startAt: "2026-07-11T00:00:00",
      endAt: "2026-07-11T23:59:59",
    },
  })

  assert.equal(controller.startTarget.value, "2026-07-11T00:00")
  assert.equal(controller.endTarget.value, "2026-07-11T23:59")
  assert.match(controller.mobileLabelTarget.textContent, /11 July 2026/)
})

import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const dateRangeSource = await readFile(
  new URL("../../app/javascript/video_studio/date_range.js", import.meta.url),
  "utf8",
)
const dateRangeUrl = `data:text/javascript;base64,${Buffer.from(dateRangeSource).toString("base64")}`
const { formatDateTimeRange, selectableDateTimeRange, toLocalDateTimeInput } =
  await import(dateRangeUrl)

const controllerSource = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/video_studio_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const controllerPrelude = `
class Controller {}
const selectableDateTimeRange = ${selectableDateTimeRange.toString()}
const translate = (key) => key
`
const controllerUrl = `data:text/javascript;base64,${Buffer.from(`${controllerPrelude}\n${controllerSource}`).toString("base64")}`
const { default: VideoStudioController } = await import(controllerUrl)

test("datetime picker seed keeps the local date and minute", () => {
  assert.equal(toLocalDateTimeInput("2026-07-11T14:30:45"), "2026-07-11T14:30")
})

test("selected range keeps both chosen times", () => {
  assert.deepEqual(
    selectableDateTimeRange("2026-07-11T14:30", "2026-07-11T18:45"),
    { start: "2026-07-11T14:30", end: "2026-07-11T18:45" },
  )
})

test("selected range rejects missing, equal, backwards, or invalid times", () => {
  assert.equal(selectableDateTimeRange("", "2026-07-11T18:45"), null)
  assert.equal(
    selectableDateTimeRange("2026-07-11T14:30", "2026-07-11T14:30"),
    null,
  )
  assert.equal(
    selectableDateTimeRange("2026-07-11T18:45", "2026-07-11T14:30"),
    null,
  )
  assert.equal(selectableDateTimeRange("not-a-date", "also-not-a-date"), null)
})

test("range label shows the start and end times", () => {
  const label = formatDateTimeRange(
    "2026-07-11T14:30",
    "2026-07-11T18:45",
    "en-GB",
  )
  assert.match(label, /14:30/)
  assert.match(label, /18:45/)
})

test("studio reloads from the exact date and time selected", async () => {
  const calls = []
  const controller = new VideoStudioController()
  controller.provider = {
    supportsDateNavigation: true,
    applyDates: async (start, end) => calls.push(["apply", start, end]),
  }
  controller.dateStartTarget = { value: "2026-07-11T14:30" }
  controller.dateEndTarget = {
    value: "2026-07-11T18:45",
    setCustomValidity: () => {},
  }
  controller.nameInputTarget = { value: "old range" }
  controller.statusTarget = { textContent: "" }
  controller.dateRangeLabel = () =>
    calls.some(([name]) => name === "apply") ? "new range" : "old range"
  controller.setRangeBusy = (busy) => calls.push(["busy", busy])
  controller.reloadTrack = async () => calls.push(["reload"])
  controller.clearResult = () => calls.push(["clear"])
  controller.refreshStyle = async () => calls.push(["style"])
  controller.renderStats = () => calls.push(["stats"])

  await controller.applyDateTimeRange()

  assert.deepEqual(calls, [
    ["busy", true],
    ["apply", "2026-07-11T14:30", "2026-07-11T18:45"],
    ["reload"],
    ["clear"],
    ["style"],
    ["stats"],
    ["busy", false],
  ])
  assert.equal(controller.statusTarget.textContent, "")
  assert.equal(controller.nameInputTarget.value, "new range")
})

test("studio rejects an end time that is not later than the start", async () => {
  const calls = []
  const controller = new VideoStudioController()
  controller.provider = {
    supportsDateNavigation: true,
    applyDates: async () => calls.push("apply"),
  }
  controller.dateStartTarget = { value: "2026-07-11T18:45" }
  controller.dateEndTarget = {
    value: "2026-07-11T14:30",
    setCustomValidity: (message) => calls.push(["validity", message]),
    reportValidity: () => calls.push(["report"]),
  }

  await controller.applyDateTimeRange()

  assert.deepEqual(calls, [
    ["validity", "datetime.start_before_end"],
    ["report"],
  ])
})

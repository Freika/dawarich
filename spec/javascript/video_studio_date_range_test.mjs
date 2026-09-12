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
globalThis.__videoStudioSelectableDateTimeRange = selectableDateTimeRange

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
const selectableDateTimeRange = globalThis.__videoStudioSelectableDateTimeRange
const translate = (key) => key
const normalizeSettings = (settings) => settings
const defaultSettings = () => ({})
const readProvenance = (settings) => settings?.provenance
const rangeRestorePlan = (provenance) => provenance
const Flash = { show: () => {} }
const ensureHudFonts = async () => []
const loadThemeTokens = (...args) => globalThis.__videoStudioLoadThemeTokens(...args)
`
const controllerUrl = `data:text/javascript;base64,${Buffer.from(`${controllerPrelude}\n${controllerSource}`).toString("base64")}`
const { default: VideoStudioController } = await import(controllerUrl)

test("datetime picker seed keeps the local date and minute", () => {
  assert.equal(toLocalDateTimeInput("2026-07-11T14:30:45"), "2026-07-11T14:30")
})

test("datetime picker seed uses the configured timezone", () => {
  assert.equal(
    toLocalDateTimeInput("2026-07-11T12:30:45Z", "Europe/Berlin"),
    "2026-07-11T14:30",
  )
})

test("selected range keeps both chosen times", () => {
  assert.deepEqual(
    selectableDateTimeRange("2026-07-11T14:30", "2026-07-11T18:45"),
    { start: "2026-07-11T14:30", end: "2026-07-11T18:45" },
  )
})

test("selected range carries the configured timezone offset", () => {
  assert.deepEqual(
    selectableDateTimeRange(
      "2026-07-11T14:30",
      "2026-07-11T18:45",
      "Europe/Berlin",
    ),
    {
      start: "2026-07-11T14:30+02:00",
      end: "2026-07-11T18:45+02:00",
    },
  )
})

test("selected range rejects a wall time skipped by daylight saving", () => {
  assert.equal(
    selectableDateTimeRange(
      "2026-03-29T02:30",
      "2026-03-29T04:00",
      "Europe/Berlin",
    ),
    null,
  )
})

test("selected range rejects an ambiguous wall time repeated by daylight saving", () => {
  assert.equal(
    selectableDateTimeRange(
      "2026-10-25T02:30",
      "2026-10-25T04:00",
      "Europe/Berlin",
    ),
    null,
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

test("range label uses the configured timezone", () => {
  const label = formatDateTimeRange(
    "2026-07-11T12:30:00Z",
    "2026-07-11T16:45:00Z",
    "en-GB",
    "Europe/Berlin",
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
  controller.syncDateTimeControls = () => calls.push(["sync-dates"])
  controller.clearResult = () => calls.push(["clear"])
  controller.refreshStyle = async () => calls.push(["style"])
  controller.renderStats = () => calls.push(["stats"])

  await controller.applyDateTimeRange()

  assert.deepEqual(calls, [
    ["clear"],
    ["busy", true],
    ["apply", "2026-07-11T14:30", "2026-07-11T18:45"],
    ["reload"],
    ["sync-dates"],
    ["style"],
    ["stats"],
    ["busy", false],
  ])
  assert.equal(controller.statusTarget.textContent, "")
  assert.equal(controller.nameInputTarget.value, "new range")
})

test("studio ignores another range change while one is loading", async () => {
  const calls = []
  const controller = new VideoStudioController()
  controller.rangeLoading = true
  controller.provider = {
    supportsDateNavigation: true,
    applyDates: async () => calls.push("apply"),
  }

  await controller.applyDateTimeRange()

  assert.deepEqual(calls, [])
})

test("studio cannot switch to poster while a range is loading", () => {
  const calls = []
  const controller = new VideoStudioController()
  controller.rangeLoading = true
  controller.provider = { id: "map" }
  controller.close = () => calls.push("close")
  const originalDocument = globalThis.document
  globalThis.document = { dispatchEvent: () => calls.push("dispatch") }

  try {
    controller.switchToPoster()
  } finally {
    globalThis.document = originalDocument
  }

  assert.deepEqual(calls, [])
})

test("initial studio load locks range actions until it finishes", async () => {
  const calls = []
  const controller = new VideoStudioController()
  controller.element = {
    classList: {
      contains: () => true,
      remove: () => calls.push("show"),
    },
  }
  controller.syncDateTimeControls = () => calls.push("sync-dates")
  controller.setRangeBusy = (busy) => calls.push(["busy", busy])
  controller.reloadTrack = async () => calls.push("reload")
  controller.nameInputTarget = { value: "existing name" }
  controller.refreshStyle = async () => calls.push("style")
  controller.renderStats = () => calls.push("stats")
  controller.syncSupport = () => calls.push("support")
  controller.fontsValue = {}
  await controller.open({ supportsDateNavigation: true })

  assert.deepEqual(calls.slice(0, 4), [
    "show",
    "sync-dates",
    ["busy", true],
    "reload",
  ])
  assert.deepEqual(calls.at(-1), ["busy", false])
})

test("closing invalidates an unfinished initial load", async () => {
  const calls = []
  let finishReload
  const controller = new VideoStudioController()
  controller.element = {
    classList: {
      contains: () => true,
      remove: () => calls.push("show"),
      add: () => calls.push("hide"),
    },
  }
  controller.syncDateTimeControls = () => {}
  controller.setRangeBusy = (busy) => calls.push(["busy", busy])
  controller.reloadTrack = () =>
    new Promise((resolve) => {
      finishReload = resolve
    })
  controller.cancel = () => calls.push("cancel")
  controller.teardown = () => calls.push("teardown")
  controller.nameInputTarget = { value: "" }
  controller.refreshStyle = async () => calls.push("style")

  const opening = controller.open({ supportsDateNavigation: true })
  controller.close()
  finishReload()
  await opening

  assert.deepEqual(calls, [
    "show",
    ["busy", true],
    "cancel",
    "teardown",
    ["busy", false],
    "hide",
  ])
})

test("an invalidated theme load cannot mutate a reopened studio", async () => {
  let finishTheme
  globalThis.__videoStudioLoadThemeTokens = () =>
    new Promise((resolve) => {
      finishTheme = resolve
    })
  const controller = new VideoStudioController()
  controller.operationVersion = 1
  controller.settings = { theme: "old" }

  const refreshing = controller.refreshStyle(1)
  controller.invalidateOperation()
  finishTheme({ name: "stale theme" })
  await refreshing

  assert.equal(controller.themeTokens, undefined)
  assert.equal(controller.style, undefined)
})

test("studio preserves automatic naming across a failed range reload", async () => {
  const calls = []
  const controller = new VideoStudioController()
  controller.provider = {
    supportsDateNavigation: true,
    timeZone: () => undefined,
    applyDates: async () => {
      calls.push("apply")
      if (calls.filter((call) => call === "apply").length === 1) {
        throw new Error("reload failed")
      }
    },
  }
  controller.dateStartTarget = { value: "2026-07-11T14:30" }
  controller.dateEndTarget = {
    value: "2026-07-11T18:45",
    setCustomValidity: () => {},
  }
  controller.hasRangeLabelTarget = true
  controller.rangeLabelTarget = { textContent: "old range" }
  controller.nameInputTarget = { value: "old range" }
  controller.statusTarget = { textContent: "" }
  controller.dateRangeLabel = () => "new range"
  controller.setRangeBusy = () => {}
  controller.clearResult = () => {}
  controller.reloadTrack = async () => {
    controller.rangeLabelTarget.textContent = "new range"
  }
  controller.syncDateTimeControls = () => {}
  controller.refreshStyle = async () => {}
  controller.renderStats = () => {}

  await controller.applyDateTimeRange()
  assert.equal(controller.nameInputTarget.value, "old range")

  await controller.applyDateTimeRange()
  assert.equal(controller.nameInputTarget.value, "new range")
})

test("restoring a recipe synchronizes the datetime controls", async () => {
  const calls = []
  const controller = new VideoStudioController()
  controller.provider = {
    dateRange: () => ({ startAt: "old", endAt: "old" }),
    applyDates: async (start, end) => calls.push(["apply", start, end]),
  }
  controller.statusTarget = { textContent: "" }
  controller.syncControls = () => calls.push(["sync-settings"])
  controller.clearResult = () => calls.push(["clear"])
  controller.setRangeBusy = (busy) => calls.push(["busy", busy])
  controller.reloadTrack = async () => calls.push(["reload"])
  controller.settingsChanged = async () => calls.push(["settings-changed"])
  controller.syncDateTimeControls = () => calls.push(["sync-dates"])

  await controller.restoreSettings({
    currentTarget: {
      dataset: {
        settings: JSON.stringify({
          provenance: {
            action: "restore",
            start_at: "2026-07-11T14:30+02:00",
            end_at: "2026-07-11T18:45+02:00",
          },
        }),
      },
    },
  })

  assert.deepEqual(calls, [
    ["sync-settings"],
    ["clear"],
    ["busy", true],
    ["apply", "2026-07-11T14:30+02:00", "2026-07-11T18:45+02:00"],
    ["reload"],
    ["busy", false],
    ["settings-changed"],
    ["sync-dates"],
  ])
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

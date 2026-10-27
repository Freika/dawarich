import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const i18nSource = await readFile(
  new URL("../../app/javascript/i18n.js", import.meta.url),
  "utf8",
)
const dateRangeSource = await readFile(
  new URL("../../app/javascript/video_studio/date_range.js", import.meta.url),
  "utf8",
)
const dateRangeUrl = `data:text/javascript;base64,${Buffer.from(
  `${i18nSource}\n${dateRangeSource}`.replace(/^import .*\n/gm, ""),
).toString("base64")}`
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
${i18nSource.replace(/^export /gm, "")}
`
const controllerUrl = `data:text/javascript;base64,${Buffer.from(`${prelude}\n${controllerSource}`).toString("base64")}`
const { default: MapControlsController } = await import(controllerUrl)

test("date navigation keeps the shared map range controls synchronized", () => {
  const controller = new MapControlsController()
  controller.dayLinkTargets = []
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
  controller.dayLinkTargets = []
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

for (const [name, format, months, expected] of [
  [
    "English",
    "%e %B %Y",
    "January February March April May June July August September October November December".split(
      " ",
    ),
    ["31 December 2026", " 2 January 2027"],
  ],
  [
    "German",
    "%-d. %B %Y",
    "Januar Februar März April Mai Juni Juli August September Oktober November Dezember".split(
      " ",
    ),
    ["31. Dezember 2026", "2. Januar 2027"],
  ],
  ["numeric preference", "%Y-%m-%d", [], ["2026-12-31", "2027-01-02"]],
]) {
  test(`date navigation refreshes map arrow URLs and exact ${name} human dates`, (t) => {
    const originals = {
      window: globalThis.window,
      document: globalThis.document,
      sessionStorage: globalThis.sessionStorage,
    }
    globalThis.document = new EventTarget()
    globalThis.sessionStorage = { getItem: () => null }
    globalThis.window = {
      location: new URL(
        "https://example.test/map/v2?start_at=2027-01-01T00:00&end_at=2027-01-01T23:59&import_id=42&panel=timeline&date=2027-01-01",
      ),
    }
    const controller = new MapControlsController()
    t.after(() => {
      controller.disconnect()
      Object.assign(globalThis, originals)
    })
    controller.dayLinkTargets = []
    controller.startTarget = { value: "" }
    controller.endTarget = { value: "" }
    controller.timezoneValue = "Pacific/Auckland"
    controller.dayLinkTargets = [-1, 1].map((delta) => ({
      href: `https://example.test/map/v2?import_id=42`,
      dataset: { dayOffset: String(delta) },
      closest: () => tips[delta],
    }))
    const tips = { "-1": { dataset: {} }, 1: { dataset: {} } }
    controller.dateFormatValue = format
    controller.monthNamesValue = [null, ...months]
    controller.abbrMonthNamesValue = [
      null,
      ...months.map((month) => month.slice(0, 3)),
    ]
    controller.connect()
    document.dispatchEvent(
      new CustomEvent("timeline-feed:date-navigated", {
        detail: {
          startAt: "2027-01-01T00:00:00",
          endAt: "2027-01-01T23:59:59",
        },
      }),
    )
    for (const [index, link] of controller.dayLinkTargets.entries()) {
      const params = new URL(link.href).searchParams
      const day = index === 0 ? "2026-12-31" : "2027-01-02"
      assert.equal(params.get("start_at"), `${day}T00:00:00`)
      assert.equal(params.get("end_at"), `${day}T23:59:59`)
      assert.equal(params.get("import_id"), "42")
      assert.equal(params.get("panel"), "timeline")
      assert.equal(params.has("date"), false)
      assert.equal(tips[link.dataset.dayOffset].dataset.tip, expected[index])
    }
  })
}

test("map day arrows keep the seconds of an absolute range applied by Studio", (t) => {
  const originals = {
    window: globalThis.window,
    document: globalThis.document,
    sessionStorage: globalThis.sessionStorage,
  }
  globalThis.document = new EventTarget()
  globalThis.sessionStorage = { getItem: () => null }
  globalThis.window = { location: new URL("https://example.test/map/v2") }
  const controller = new MapControlsController()
  t.after(() => {
    controller.disconnect()
    Object.assign(globalThis, originals)
  })
  controller.startTarget = { value: "" }
  controller.endTarget = { value: "" }
  controller.timezoneValue = "Europe/Berlin"
  controller.dateFormatValue = "%Y-%m-%d"
  controller.monthNamesValue = []
  controller.abbrMonthNamesValue = []
  controller.dayLinkTargets = [
    {
      href: "https://example.test/map/v2",
      dataset: { dayOffset: "1" },
      closest: () => ({ dataset: {} }),
    },
  ]
  controller.connect()
  document.dispatchEvent(
    new CustomEvent("timeline-feed:date-navigated", {
      detail: {
        startAt: "2026-10-15T22:00:00.000Z",
        endAt: "2026-10-16T21:59:59.000Z",
      },
    }),
  )
  const params = new URL(controller.dayLinkTargets[0].href).searchParams
  assert.equal(params.get("start_at"), "2026-10-17T00:00:00")
  assert.equal(params.get("end_at"), "2026-10-17T23:59:59")
})

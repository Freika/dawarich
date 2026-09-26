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

const dateManagerSource = await read(
  "controllers/maps/maplibre/date_manager.js",
)
const { DateManager } = await importSource(dateManagerSource)
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
  return `const ${name} = new Proxy(function () {}, { get: () => () => {} })`
})
const { default: MapController } = await importSource(
  `${stubs.join("\n")}\n${mapBody}`,
)

function buildMap(t, timezone = "America/Los_Angeles") {
  const oldDocument = globalThis.document
  globalThis.document = { getElementById: () => null }
  t.after(() => {
    globalThis.document = oldDocument
  })

  const frame = {
    attributes: {},
    getAttribute(name) {
      return this.attributes[name] ?? null
    },
    hasAttribute(name) {
      return name in this.attributes
    },
    removeAttribute(name) {
      delete this.attributes[name]
    },
    set src(value) {
      this.attributes.src = value
    },
  }
  const map = Object.create(MapController.prototype)
  Object.assign(map, {
    timezoneValue: timezone,
    hasTimelineFeedContainerTarget: true,
    timelineFeedContainerTarget: frame,
    startDateValue: "2020-04-01T00:00:00-07:00",
    endDateValue: "2020-04-30T23:59:59-07:00",
    layerManager: { getLayer: () => null },
    settings: {},
    loadMapData: async () => {},
    debouncedLoadFamilyHistory() {},
    element: { querySelector: () => ({}) },
  })
  return { map, frame }
}

function requestedRange(frame) {
  const params = new URL(frame.attributes.src, "http://localhost").searchParams
  return [params.get("start_at"), params.get("end_at")]
}

test("initial map instant is rendered with the profile offset", () => {
  const instant = new Date("2020-04-17T00:00:00-07:00")
  assert.equal(
    DateManager.formatDateForAPI(instant, "America/Los_Angeles"),
    "2020-04-17T00:00-07:00",
  )
})

test("Friday navigation requests Friday in the profile timezone", async (t) => {
  const { map, frame } = buildMap(t)
  await map.navigateTimelineDateRange({
    startAt: "2020-04-17T00:00:00",
    endAt: "2020-04-17T23:59:59",
  })
  assert.deepEqual(requestedRange(frame), [
    "2020-04-17T00:00-07:00",
    "2020-04-17T23:59-07:00",
  ])
})

test("Thursday and Friday navigation produce adjacent profile days", async (t) => {
  const { map, frame } = buildMap(t)
  for (const day of ["2020-04-16", "2020-04-17"]) {
    await map.navigateTimelineDateRange({
      startAt: `${day}T00:00:00`,
      endAt: `${day}T23:59:59`,
    })
    assert.deepEqual(requestedRange(frame), [
      `${day}T00:00-07:00`,
      `${day}T23:59-07:00`,
    ])
  }
})

test("month navigation uses the profile offset on both sides of DST", (t) => {
  const { map, frame } = buildMap(t)
  map.monthChanged({ target: { value: "2020-03" } })
  assert.deepEqual(requestedRange(frame), [
    "2020-03-01T00:00-08:00",
    "2020-03-31T23:59-07:00",
  ])
})

test("explicit UTC range retains its instant in the profile timezone", async (t) => {
  const { map, frame } = buildMap(t)
  await map.navigateTimelineDateRange({
    startAt: "2020-04-17T07:00:00Z",
    endAt: "2020-04-18T06:59:00Z",
  })
  assert.deepEqual(requestedRange(frame), [
    "2020-04-17T00:00-07:00",
    "2020-04-17T23:59-07:00",
  ])
})

test("spring DST day uses each boundary's profile offset", async (t) => {
  const { map, frame } = buildMap(t)
  await map.navigateTimelineDateRange({
    startAt: "2020-03-08T00:00:00",
    endAt: "2020-03-08T23:59:59",
  })
  assert.deepEqual(requestedRange(frame), [
    "2020-03-08T00:00-08:00",
    "2020-03-08T23:59-07:00",
  ])
})

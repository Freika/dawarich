import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

async function loadImmichEnrichController() {
  const source = await readFile(
    new URL(
      "../../app/javascript/controllers/maps/immich_enrich_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
  const withoutImports = source.replace(/^import .*\n/gm, "")
  const dependencies = `
    class Controller {}
    const formatDateTime = (value) => value
    const translate = (key) => key
    const maplibregl = {}
    const Flash = { show() {} }
  `
  const url = `data:text/javascript;base64,${Buffer.from(`${dependencies}\n${withoutImports}`).toString("base64")}`

  return (await import(`${url}#${Date.now()}`)).default
}

class ClassList {
  constructor(...names) {
    this.names = new Set(names)
  }
  toggle(name) {
    if (this.names.has(name)) this.names.delete(name)
    else this.names.add(name)
  }
  add(name) {
    this.names.add(name)
  }
  remove(name) {
    this.names.delete(name)
  }
  contains(name) {
    return this.names.has(name)
  }
}

const section = () => ({ classList: new ClassList("hidden"), textContent: "" })

async function buildPanel({ start, end, mapController }) {
  const ImmichEnrichController = await loadImmichEnrichController()
  const controller = new ImmichEnrichController()
  controller.element = { classList: new ClassList("hidden") }
  controller.startDateTarget = { value: start }
  controller.endDateTarget = { value: end }
  controller.toleranceTarget = { value: "30" }
  controller.hasStartDateTarget = true
  controller.hasEndDateTarget = true
  controller.hasScanButtonTarget = false
  for (const name of ["scanForm", "loading", "loadingText", "results"]) {
    controller[`${name}Target`] = section()
  }
  controller.toggleBtnValue = ""
  controller.application = {
    getControllerForElementAndIdentifier: () => mapController,
  }
  globalThis.document = Object.assign(new EventTarget(), {
    querySelector: () => ({}),
  })
  globalThis.window = {
    location: { href: "http://localhost/map/v2" },
    history: { replaceState() {} },
  }
  controller.connect()
  return controller
}

function mapShowing(start, end) {
  return {
    startDateValue: start,
    endDateValue: end,
    loadMapData() {},
  }
}

const nextTick = () => new Promise((resolve) => setImmediate(resolve))

test("opening the panel takes the dates the map moved to after page load", async () => {
  const map = {
    startDateValue: "2026-04-12T00:00:00+00:00",
    endDateValue: "2026-04-15T23:59:00+00:00",
  }
  const panel = await buildPanel({
    start: "2026-04-12",
    end: "2026-04-15",
    mapController: map,
  })

  map.startDateValue = "2026-03-01T00:00:00+00:00"
  map.endDateValue = "2026-03-31T23:59:00+00:00"
  panel.toggle()

  assert.equal(panel.startDateTarget.value, "2026-03-01")
  assert.equal(panel.endDateTarget.value, "2026-03-31")
})

test("opening the panel keeps dates the user typed", async () => {
  const map = {
    startDateValue: "2026-04-12T00:00:00+00:00",
    endDateValue: "2026-04-15T23:59:00+00:00",
  }
  const panel = await buildPanel({
    start: "2026-04-12",
    end: "2026-04-15",
    mapController: map,
  })

  panel.toggle()
  panel.startDateTarget.value = "2026-01-05"
  panel.toggle()
  map.startDateValue = "2026-03-01T00:00:00+00:00"
  map.endDateValue = "2026-03-31T23:59:00+00:00"
  panel.toggle()

  assert.equal(panel.startDateTarget.value, "2026-01-05")
  assert.equal(panel.endDateTarget.value, "2026-04-15")
})

test("opening the panel keeps the server dates while the map controller is not connected", async () => {
  const panel = await buildPanel({
    start: "2026-04-12",
    end: "2026-04-15",
    mapController: null,
  })

  panel.toggle()

  assert.equal(panel.startDateTarget.value, "2026-04-12")
  assert.equal(panel.endDateTarget.value, "2026-04-15")
})

test("the open panel follows a day picked on the timeline", async () => {
  const map = mapShowing(
    "2026-04-12T00:00:00+00:00",
    "2026-04-15T23:59:00+00:00",
  )
  const panel = await buildPanel({
    start: "2026-04-12",
    end: "2026-04-15",
    mapController: map,
  })
  panel.toggle()

  document.dispatchEvent(new CustomEvent("timeline-feed:date-navigated"))
  map.startDateValue = "2026-04-20T00:00:00+00:00"
  map.endDateValue = "2026-04-20T23:59:00+00:00"
  await nextTick()

  assert.equal(panel.startDateTarget.value, "2026-04-20")
  assert.equal(panel.endDateTarget.value, "2026-04-20")
})

test("after a scan the panel follows the map again", async () => {
  const map = mapShowing(
    "2026-04-12T00:00:00+00:00",
    "2026-04-15T23:59:00+00:00",
  )
  const panel = await buildPanel({
    start: "2026-04-12",
    end: "2026-04-15",
    mapController: map,
  })
  globalThis.fetch = async () => {
    throw new Error("offline")
  }
  const consoleError = console.error
  console.error = () => {}

  panel.toggle()
  panel.startDateTarget.value = "2026-01-05"
  await panel.scan()
  console.error = consoleError
  map.startDateValue = "2026-03-01T00:00:00+00:00"
  map.endDateValue = "2026-03-31T23:59:00+00:00"
  panel.toggle()
  panel.toggle()

  assert.equal(panel.startDateTarget.value, "2026-03-01")
  assert.equal(panel.endDateTarget.value, "2026-03-31")
})

test("while the map shows its page-load range the panel shows the dates the server rendered it with", async () => {
  const map = mapShowing(
    "2026-04-11T17:00:00-07:00",
    "2026-04-15T16:59:00-07:00",
  )
  map.defaultDateRange = {
    startValue: map.startDateValue,
    endValue: map.endDateValue,
    startDate: "2026-04-12",
    endDate: "2026-04-15",
  }
  const panel = await buildPanel({
    start: "2026-04-01",
    end: "2026-04-02",
    mapController: map,
  })

  assert.equal(panel.startDateTarget.value, "2026-04-12")
  assert.equal(panel.endDateTarget.value, "2026-04-15")
})

test("reconnecting after a Turbo visit takes the dates of the new map", async () => {
  const map = mapShowing(
    "2026-04-20T00:00:00+02:00",
    "2026-04-20T23:59:00+02:00",
  )
  const panel = await buildPanel({
    start: "2026-04-12",
    end: "2026-04-15",
    mapController: map,
  })

  assert.equal(panel.startDateTarget.value, "2026-04-20")
  assert.equal(panel.endDateTarget.value, "2026-04-20")
})

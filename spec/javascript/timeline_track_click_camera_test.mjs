import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/timeline_feed_controller.js",
    import.meta.url,
  ),
  "utf8",
)
const stubbedSource = source
  .replace(
    'import { Controller } from "@hotwired/stimulus"',
    "class Controller {}",
  )
  .replace('import { translate } from "i18n"', "const translate = (key) => key")
const { default: TimelineFeedController } = await import(
  `data:text/javascript;base64,${Buffer.from(stubbedSource).toString("base64")}`
)

const mapControllerSource = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre_controller.js",
    import.meta.url,
  ),
  "utf8",
)

function installBrowserStubs(t) {
  const events = []
  const originals = {
    document: globalThis.document,
    window: globalThis.window,
    CustomEvent: globalThis.CustomEvent,
  }
  globalThis.CustomEvent = class {
    constructor(type, init = {}) {
      this.type = type
      this.detail = init.detail
    }
  }
  globalThis.document = {
    querySelector: () => null,
    getElementById: () => null,
    dispatchEvent: (event) => events.push(event),
  }
  globalThis.window = {
    location: { search: "?start_at=2026-09-01T00:00&end_at=2026-09-18T23:59" },
    history: { pushState: () => {} },
  }
  t.after(() => {
    globalThis.document = originals.document
    globalThis.window = originals.window
    globalThis.CustomEvent = originals.CustomEvent
  })
  return events
}

function buildTimeline({ dayBounds } = {}) {
  const controller = new TimelineFeedController()
  const dayElement = dayBounds
    ? { dataset: { bounds: JSON.stringify(dayBounds) } }
    : null
  controller.element = { querySelectorAll: () => [], querySelector: () => null }
  controller.hasVisitListFrameTarget = true
  controller.emptyFilteredTargets = []
  controller.hasSearchInputTarget = false
  const attributes = {}
  controller.visitListFrameTarget = {
    querySelector: (selector) =>
      selector === ".timeline-day" ? dayElement : null,
    querySelectorAll: () => [],
    getAttribute: (name) => attributes[name] ?? null,
    setAttribute: (name, value) => {
      attributes[name] = value
    },
    removeAttribute: (name) => {
      delete attributes[name]
    },
    reload: () => {},
  }
  controller.selectedDate = "2026-09-16"
  return controller
}

const bounds = { sw_lat: 51.3, sw_lng: 12.33, ne_lat: 51.35, ne_lng: 12.41 }

test("a track click on another day navigates the map without refitting the camera", (t) => {
  const events = installBrowserStubs(t)
  const timeline = buildTimeline()

  timeline.handleOpenTrack({
    detail: {
      trackId: 39,
      date: "2026-09-17",
      startAt: "2026-09-17T07:30:00Z",
    },
  })

  const navigated = events.find(
    (e) => e.type === "timeline-feed:date-navigated",
  )
  assert.ok(navigated, "the map is told to load the track's day")
  assert.equal(navigated.detail.date, "2026-09-17")
  assert.equal(navigated.detail.fitBounds, false)
})

test("calendar navigation to a day still refits the camera", (t) => {
  const events = installBrowserStubs(t)
  const timeline = buildTimeline()

  timeline.navigateToDay("2026-09-17")

  const navigated = events.find(
    (e) => e.type === "timeline-feed:date-navigated",
  )
  assert.notEqual(navigated.detail.fitBounds, false)
})

test("the day's bounds are not sent to the map while a clicked track is pending", (t) => {
  const events = installBrowserStubs(t)
  const timeline = buildTimeline({ dayBounds: bounds })
  timeline.pendingTrackId = 39

  timeline.handleVisitFrameLoad()

  const daySelected = events.filter(
    (e) => e.type === "timeline-feed:day-selected" && e.detail?.bounds,
  )
  assert.equal(daySelected.length, 0)
})

test("a refresh of the clicked track's day does not refit the camera after the track opened", (t) => {
  const events = installBrowserStubs(t)
  const timeline = buildTimeline({ dayBounds: bounds })

  timeline.handleOpenTrack({
    detail: {
      trackId: 39,
      date: "2026-09-17",
      startAt: "2026-09-17T07:30:00Z",
    },
  })
  timeline.pendingTrackId = null
  timeline.handleVisitFrameLoad()
  timeline.handleVisitFrameLoad()

  const daySelected = events.filter(
    (e) => e.type === "timeline-feed:day-selected" && e.detail?.bounds,
  )
  assert.equal(daySelected.length, 0)
})

test("navigating to another day after a track click refits the camera again", (t) => {
  const events = installBrowserStubs(t)
  const timeline = buildTimeline({ dayBounds: bounds })

  timeline.handleOpenTrack({
    detail: {
      trackId: 39,
      date: "2026-09-17",
      startAt: "2026-09-17T07:30:00Z",
    },
  })
  timeline.pendingTrackId = null
  timeline.navigateToDay("2026-09-18")
  timeline.handleVisitFrameLoad()

  const daySelected = events.find(
    (e) => e.type === "timeline-feed:day-selected" && e.detail?.bounds,
  )
  assert.deepEqual(daySelected?.detail.bounds, bounds)
})

test("the day's bounds are sent to the map for an ordinary day switch", (t) => {
  const events = installBrowserStubs(t)
  const timeline = buildTimeline({ dayBounds: bounds })

  timeline.handleVisitFrameLoad()

  const daySelected = events.find(
    (e) => e.type === "timeline-feed:day-selected" && e.detail?.bounds,
  )
  assert.deepEqual(daySelected?.detail.bounds, bounds)
})

test("the map honours fitBounds from a timeline navigation", () => {
  const start = mapControllerSource.indexOf("async navigateTimelineDateRange(")
  const navigate = mapControllerSource.slice(
    start,
    mapControllerSource.indexOf("this.refreshTimelineFeedIfActive", start),
  )

  assert.match(
    navigate,
    /navigateTimelineDateRange\(\{[^}]*fitBounds = true[^}]*\}\)/,
  )
  assert.match(navigate, /this\.loadMapData\(\{ fitBounds \}\)/)
})

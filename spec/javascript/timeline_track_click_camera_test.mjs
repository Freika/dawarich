import assert from "node:assert/strict"
import test from "node:test"

import TimelineFeedController from "controllers/timeline_feed_controller"

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
    querySelectorAll: () => [],
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

// Opening the Timeline tab reloads its list, but Turbo marks the frame busy
// only after the click handler returns. A track clicked then must still open
// once the new list arrives, not in the list being replaced.
test("a track opened while the Timeline list loads expands in the loaded list", (t) => {
  installBrowserStubs(t)
  const frames = []
  const originalRaf = globalThis.requestAnimationFrame
  globalThis.requestAnimationFrame = (callback) => frames.push(callback)
  t.after(() => {
    globalThis.requestAnimationFrame = originalRaf
  })
  const timeline = buildTimeline()
  let busy = false
  timeline.visitListFrameTarget.hasAttribute = (name) => name === "busy" && busy
  const frame = { classList: { contains: (name) => name === "hidden" } }
  const leg = { dataset: { frameId: "track-info-39" }, closest: () => null }
  timeline.element.querySelector = (selector) =>
    selector === '.journey-leg[data-track-id="39"]' ? leg : null
  globalThis.document.getElementById = (id) =>
    id === "track-info-39" ? frame : null
  const opened = []
  timeline.toggleTrackInfo = ({ currentTarget }) => opened.push(currentTarget)

  timeline.handleOpenTrack({
    detail: {
      trackId: 39,
      date: "2026-09-16",
      startAt: "2026-09-16T07:30:00Z",
    },
  })
  busy = true // Turbo starts the reload after the click handler returns
  for (const callback of frames.splice(0)) callback()
  assert.deepEqual(opened, [], "nothing opens in the list being replaced")

  // One click can start several reloads (opening the tab, the day, the map's
  // own refresh); a list that lands while another is still on its way is
  // replaced, so only the last one may open the track.
  timeline.handleVisitFrameLoad()
  assert.deepEqual(
    opened,
    [],
    "nothing opens while another reload is on its way",
  )

  busy = false
  timeline.handleVisitFrameLoad()

  assert.deepEqual(opened, [leg])
})

// The map skips its own Timeline refresh for these, so the flag is a contract.
test("the Timeline's day navigation tells the map its list is already loading", (t) => {
  const events = installBrowserStubs(t)
  const timeline = buildTimeline()

  timeline.navigateToDay("2026-09-17")

  const navigated = events.find(
    (e) => e.type === "timeline-feed:date-navigated",
  )
  assert.equal(navigated.detail.timelineLoaded, true)
})

test("the Timeline's period navigation tells the map its list is already loading", (t) => {
  const events = installBrowserStubs(t)
  const timeline = buildTimeline()
  timeline.showRange = () => true

  timeline.navigateToPeriod("2026-09-01T00:00:00", "2026-09-18T23:59:59")

  const navigated = events.find(
    (e) => e.type === "timeline-feed:date-navigated",
  )
  assert.equal(navigated.detail.timelineLoaded, true)
})

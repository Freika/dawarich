import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const importSource = (source) =>
  import(
    `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
  )

const { default: TimelineFeedController } = await importSource(
  (await read("controllers/timeline_feed_controller.js"))
    .replace(
      'import { Controller } from "@hotwired/stimulus"',
      "class Controller {}",
    )
    .replace(
      'import { translate } from "i18n"',
      "const translate = (key) => key",
    ),
)

const dateManagerSource = (
  await read("controllers/maps/maplibre/date_manager.js")
).replace("export class", "class")
const importedNames = []
const mapBody = (await read("controllers/maps/maplibre_controller.js")).replace(
  /^import\s+([\s\S]*?)\s+from\s+"[^"]+"\n/gm,
  (_statement, clause) => {
    const named = clause.match(/\{([\s\S]*)\}/)?.[1] ?? ""
    for (const part of named.split(",")) {
      const name = part.trim()
      if (name) importedNames.push(name)
    }
    const defaultName = clause.replace(/\{[\s\S]*\}/, "").trim()
    if (defaultName) importedNames.push(defaultName)
    return ""
  },
)
const stubs = importedNames.map((name) => {
  if (name === "Controller") return "class Controller {}"
  if (name === "DateManager") return dateManagerSource
  return `const ${name} = new Proxy(function () {}, { get: () => () => {} })`
})
const { default: MapController } = await importSource(
  `${stubs.join("\n")}\n${mapBody}`,
)

const ORIGIN = "http://localhost:3000"
const TRACK_ID = 39
const TRACK_DAY = "2026-09-17"
const TRACK_INFO_FRAME = `track_info_frame_${TRACK_ID}`
const TRACK_INFO_URL = `/map/timeline_feeds/${TRACK_ID}/track_info`
const SEPTEMBER = {
  start: "2026-09-01T00:00+00:00",
  end: "2026-09-18T23:59+00:00",
}
const TRACK_DAY_ON_MAP = {
  start: `${TRACK_DAY}T00:00+00:00`,
  end: `${TRACK_DAY}T23:59+00:00`,
}
const feedUrl = (start, end) =>
  `/map/timeline_feeds?start_at=${encodeURIComponent(start)}&end_at=${encodeURIComponent(end)}`
const timelineDayUrl = feedUrl(`${TRACK_DAY}T00:00:00`, `${TRACK_DAY}T23:59:59`)
const mapRangeUrl = (map) => feedUrl(map.startDateValue, map.endDateValue)
const showsTrackDay = (url) =>
  new URL(url, ORIGIN).searchParams.get("start_at").startsWith(TRACK_DAY)
const flush = () => new Promise((resolve) => setImmediate(resolve))

function installPage(t) {
  const listeners = new Map()
  const elements = new Map([
    ["timeline-feed-skeleton", { innerHTML: "<div>skeleton</div>" }],
  ])
  const saved = {
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
  globalThis.window = { location: { search: "" }, history: { pushState() {} } }
  globalThis.document = {
    addEventListener(type, fn) {
      listeners.set(type, [...(listeners.get(type) ?? []), fn])
    },
    removeEventListener(type, fn) {
      listeners.set(
        type,
        (listeners.get(type) ?? []).filter((listener) => listener !== fn),
      )
    },
    dispatchEvent(event) {
      for (const fn of listeners.get(event.type) ?? []) fn(event)
      return true
    },
    getElementById: (id) => elements.get(id) ?? null,
    querySelector: () => null,
  }
  t.after(() => Object.assign(globalThis, saved))
  return elements
}

function trackInfoFrame() {
  const classes = new Set(["hidden"])
  return {
    url: null,
    classList: {
      contains: (name) => classes.has(name),
      add: (name) => classes.add(name),
      remove: (name) => classes.delete(name),
    },
    getAttribute(name) {
      return name === "src" ? this.url : null
    },
    set src(url) {
      this.url = url
    },
  }
}

function turboFrame(elements) {
  const listeners = {}
  return {
    attributes: {},
    inFlight: null,
    rendered: null,
    abortedTrackInfo: 0,
    getAttribute(name) {
      return this.attributes[name] ?? null
    },
    hasAttribute(name) {
      return name in this.attributes
    },
    setAttribute(name, value) {
      this.attributes[name] = value
      if (name === "src") this.inFlight = value
    },
    removeAttribute(name) {
      delete this.attributes[name]
      if (name === "src") this.inFlight = null
    },
    get src() {
      return this.getAttribute("src")
    },
    set src(value) {
      this.setAttribute("src", value)
    },
    set innerHTML(_html) {
      this.show(null)
    },
    reload() {
      this.inFlight = this.attributes.src
    },
    show(url) {
      if (elements.get(TRACK_INFO_FRAME)?.url) this.abortedTrackInfo += 1
      elements.delete(TRACK_INFO_FRAME)
      this.rendered = url
      if (url && showsTrackDay(url)) {
        elements.set(TRACK_INFO_FRAME, trackInfoFrame())
      }
    },
    respond() {
      const url = this.inFlight
      assert.ok(url, "a timeline feed request is in flight")
      this.inFlight = null
      this.attributes.src = new URL(url, ORIGIN).href
      this.show(url)
      this.emit("turbo:frame-load")
    },
    fail(type) {
      this.inFlight = null
      this.emit(type)
    },
    emit(type, target = this) {
      for (const fn of listeners[type] ?? []) fn({ type, target })
    },
    addEventListener(type, fn) {
      listeners[type] = [...(listeners[type] ?? []), fn]
    },
    removeEventListener(type, fn) {
      listeners[type] = (listeners[type] ?? []).filter((l) => l !== fn)
    },
    querySelector: () => null,
    querySelectorAll: () => [],
  }
}

function journeyToggle() {
  return {
    dataset: { frameId: TRACK_INFO_FRAME, trackId: String(TRACK_ID) },
    querySelector: () => null,
    closest: () => ({ dataset: {}, scrollIntoView() {} }),
  }
}

function buildPage(t, { panelFirst, mapRange }) {
  const elements = installPage(t)
  const frame = turboFrame(elements)

  let finishMapData
  const mapData = new Promise((resolve) => {
    finishMapData = resolve
  })
  const map = Object.create(MapController.prototype)
  Object.assign(map, {
    hasTimelineFeedContainerTarget: true,
    timelineFeedContainerTarget: frame,
    startDateValue: mapRange.start,
    endDateValue: mapRange.end,
    element: {
      querySelector: (selector) =>
        selector.includes('data-tab-content="timeline-feed"') ? {} : null,
    },
    hasVisitsToggleTarget: false,
    layerManager: { getLayer: () => null },
    settings: {},
    loadMapData: () => mapData,
    debouncedLoadFamilyHistory() {},
  })
  document.addEventListener("map-panel:tab-changed", (e) =>
    map.handleTabChanged(e),
  )
  document.addEventListener("timeline-feed:date-navigated", (e) =>
    map.handleTimelineDateNavigated(e),
  )

  const openTimelineTab = () =>
    document.dispatchEvent(
      new CustomEvent("map-panel:tab-changed", {
        detail: { tab: "timeline-feed" },
      }),
    )
  if (panelFirst)
    document.addEventListener("timeline:open-track", openTimelineTab)

  const timeline = new TimelineFeedController()
  Object.assign(timeline, {
    element: {
      querySelectorAll: () => [],
      querySelector: (selector) =>
        selector === `.journey-leg[data-track-id="${TRACK_ID}"]` &&
        elements.has(TRACK_INFO_FRAME)
          ? journeyToggle()
          : null,
    },
    hasVisitListFrameTarget: true,
    visitListFrameTarget: frame,
    hasSearchInputTarget: false,
    emptyFilteredTargets: [],
  })
  timeline.connect()
  if (!panelFirst) {
    document.addEventListener("timeline:open-track", openTimelineTab)
  }

  return {
    elements,
    frame,
    map,
    timeline,
    openTimelineTab,
    finishLoadingMapData: async () => {
      finishMapData()
      await flush()
    },
  }
}

function clickTrack() {
  document.dispatchEvent(
    new CustomEvent("timeline:open-track", {
      detail: {
        trackId: TRACK_ID,
        date: TRACK_DAY,
        startAt: `${TRACK_DAY}T07:30:00Z`,
      },
    }),
  )
}

function assertTrackCardOpenOnTrackDay(page) {
  assert.equal(page.frame.inFlight, null, "no further feed load is pending")
  assert.equal(page.frame.rendered, timelineDayUrl)
  assert.equal(page.frame.abortedTrackInfo, 0, "track_info was aborted")
  assert.equal(page.elements.get(TRACK_INFO_FRAME)?.url, TRACK_INFO_URL)
}

const orders = [
  ["the panel listener runs first", true],
  ["the timeline listener runs first", false],
]

for (const [order, panelFirst] of orders) {
  for (const mapLandsLast of [true, false]) {
    const landing = mapLandsLast
      ? "the map's data lands last"
      : "the map's data lands first"

    test(`a track click on another day ends on the track's day with its card open (${order}, ${landing})`, async (t) => {
      const page = buildPage(t, { panelFirst, mapRange: SEPTEMBER })

      clickTrack()
      if (mapLandsLast) {
        page.frame.respond()
        await page.finishLoadingMapData()
      } else {
        await page.finishLoadingMapData()
        page.frame.respond()
      }
      if (page.frame.inFlight) page.frame.respond()

      assertTrackCardOpenOnTrackDay(page)
    })
  }

  test(`a track click on the day the timeline already shows opens its card (${order})`, async (t) => {
    const page = buildPage(t, { panelFirst, mapRange: TRACK_DAY_ON_MAP })
    page.timeline.selectedDate = TRACK_DAY
    page.frame.src = timelineDayUrl
    page.frame.respond()

    clickTrack()
    if (page.frame.inFlight) page.frame.respond()

    assertTrackCardOpenOnTrackDay(page)
  })
}

test("a calendar day click is not reloaded with the map's range after the map's data lands", async (t) => {
  const page = buildPage(t, { panelFirst: true, mapRange: SEPTEMBER })
  page.openTimelineTab()
  page.frame.respond()

  page.timeline.navigateToDay(TRACK_DAY)
  page.frame.respond()
  await page.finishLoadingMapData()

  assert.equal(page.frame.inFlight, null)
  assert.equal(page.frame.rendered, timelineDayUrl)
})

test("switching to the timeline tab without a track click loads the map's range", (t) => {
  const page = buildPage(t, { panelFirst: true, mapRange: SEPTEMBER })

  page.openTimelineTab()
  page.frame.respond()

  assert.equal(page.frame.rendered, feedUrl(SEPTEMBER.start, SEPTEMBER.end))
})

test("a date change from outside the timeline reloads the open feed with the map's new range", async (t) => {
  const page = buildPage(t, { panelFirst: true, mapRange: SEPTEMBER })
  page.openTimelineTab()
  page.frame.respond()

  document.dispatchEvent(
    new CustomEvent("timeline-feed:date-navigated", {
      detail: { startAt: "2026-08-01T00:00", endAt: "2026-08-31T23:59" },
    }),
  )
  await page.finishLoadingMapData()

  assert.match(page.map.startDateValue, /^2026-08-01T00:00/)
  assert.equal(page.frame.inFlight, mapRangeUrl(page.map))
})

for (const settled of [
  "turbo:frame-load",
  "turbo:fetch-request-error",
  "turbo:frame-missing",
]) {
  test(`once the timeline's day load ends with ${settled}, switching tabs loads the map's range again`, async (t) => {
    const page = buildPage(t, { panelFirst: true, mapRange: SEPTEMBER })
    page.timeline.navigateToDay(TRACK_DAY)
    if (settled === "turbo:frame-load") {
      page.frame.respond()
    } else {
      page.frame.fail(settled)
    }
    await page.finishLoadingMapData()

    page.openTimelineTab()

    assert.equal(page.frame.inFlight, mapRangeUrl(page.map))
  })
}

test("a nested frame loading inside the list does not end the timeline's day load", async (t) => {
  const page = buildPage(t, { panelFirst: true, mapRange: SEPTEMBER })
  page.timeline.navigateToDay(TRACK_DAY)
  await page.finishLoadingMapData()

  page.frame.emit("turbo:frame-load", trackInfoFrame())
  page.openTimelineTab()

  assert.equal(page.frame.inFlight, timelineDayUrl)
})

test("a month change while the timeline's day load is pending keeps the timeline's request", async (t) => {
  const page = buildPage(t, { panelFirst: true, mapRange: SEPTEMBER })
  page.timeline.navigateToDay(TRACK_DAY)
  await page.finishLoadingMapData()

  page.map.monthChanged({ target: { value: "2026-08" } })

  assert.equal(page.frame.inFlight, timelineDayUrl)
})

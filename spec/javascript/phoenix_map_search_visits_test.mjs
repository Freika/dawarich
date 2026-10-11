import assert from "node:assert/strict"
import { test } from "node:test"
import { filterVisits } from "../../app-phoenix/assets/js/map/ui/filters.js"
import {
  overlayAwarePadding,
  panelPadding,
} from "../../app-phoenix/assets/js/map/ui/padding.js"
import {
  createVisitResults,
  groupVisitsByYear,
} from "../../app-phoenix/assets/js/map/ui/search_visits.js"

const deferred = () => {
  let resolve
  let reject
  const promise = new Promise((ok, fail) => {
    resolve = ok
    reject = fail
  })
  return { promise, resolve, reject }
}

function element(tag) {
  const listeners = new Map()
  const node = {
    tag,
    children: [],
    textContent: "",
    hidden: false,
    attributes: {},
    addEventListener: (type, fn) => listeners.set(type, fn),
    setAttribute(name, value) {
      node.attributes[name] = value
    },
    append(...children) {
      node.children.push(...children)
    },
    replaceChildren(...children) {
      node.children = children
    },
    listeners,
  }
  return node
}

const all = (node) => [node, ...node.children.flatMap(all)]
const texts = (node) => all(node).map((child) => child.textContent)
const translate = (key, vars = {}) => `${key}${JSON.stringify(vars)}`

const location = {
  place_name: "Cafe <b>",
  coordinates: [52.5, 13.4],
  total_visits: 2,
  visits: [
    {
      date: "2023-12-31T23:30:00Z",
      coordinates: [52.51, 13.41],
      duration_estimate: "1h",
      visit_details: {
        start_time: "2023-12-31T23:30:00Z",
        end_time: "2024-01-01T00:30:00Z",
      },
    },
    { date: "2022-06-01T10:00:00Z", duration_estimate: "2h" },
  ],
}

test("visit results group by profile-zone year and open a prefilled create dialog", async () => {
  assert.deepEqual(
    Object.keys(groupVisitsByYear(location.visits, "Europe/Berlin")),
    ["2022", "2024"],
  )
  assert.deepEqual(Object.keys(groupVisitsByYear(location.visits, "UTC")), [
    "2022",
    "2023",
  ])

  const container = element("div")
  const flights = []
  const pushed = []
  const request = deferred()
  const results = createVisitResults({
    container,
    document: { createElement: element },
    translate,
    timezone: () => "Europe/Berlin",
    search: { visits: () => request.promise },
    flyTo: (target) => flights.push(target),
    pushEvent: (event, payload) => pushed.push([event, payload]),
  })

  const opened = results.open({ name: "Cafe", lat: 52.5, lon: 13.4 })
  assert.deepEqual(flights, [{ lat: 52.5, lon: 13.4, zoom: 15 }])
  request.resolve({ total_locations: 1, locations: [location] })
  await opened

  assert.ok(texts(container).includes("Cafe <b>"))
  assert.ok(all(container).some((node) => node.tag === "details"))
  const visit = all(container).find(
    (node) => node.attributes["data-visit-index"] === "0",
  )
  visit.listeners.get("click")()
  assert.deepEqual(flights.at(-1), { lat: 52.51, lon: 13.41, zoom: 18 })
  assert.deepEqual(pushed, [
    [
      "visit:new",
      {
        name: "Cafe <b>",
        latitude: 52.51,
        longitude: 13.41,
        started_at: "2023-12-31T23:30:00Z",
        ended_at: "2024-01-01T00:30:00Z",
      },
    ],
  ])

  results.destroy()
  visit.listeners.get("click")()
  assert.equal(pushed.length, 1)
})

test("older visit lookup cannot replace the newer location", async () => {
  const container = element("div")
  const requests = []
  const results = createVisitResults({
    container,
    document: { createElement: element },
    translate,
    timezone: () => "UTC",
    search: {
      visits: (_location, { signal }) => {
        const request = deferred()
        requests.push({ request, signal })
        return request.promise
      },
    },
    flyTo: () => {},
    pushEvent: () => {},
  })

  const older = results.open({ name: "Old", lat: 1, lon: 1 })
  const newer = results.open({ name: "New", lat: 2, lon: 2 })
  assert.equal(requests[0].signal.aborted, true)
  requests[1].request.resolve({ total_locations: 0, locations: [] })
  requests[0].request.resolve({ total_locations: 1, locations: [location] })
  await Promise.all([older, newer])
  assert.ok(!texts(container).includes("Cafe <b>"))
  assert.ok(
    texts(container).some((text) => text.startsWith("visits.none_found")),
  )

  const failing = results.open({ name: "Err", lat: 3, lon: 3 })
  requests[2].request.reject(new Error("boom"))
  await failing
  assert.ok(
    texts(container).some((text) =>
      text.startsWith("search.visits_load_failed"),
    ),
  )
})

test("visit filter matches name, place name and status", () => {
  const visits = [
    { id: 1, name: "Morning Cafe", status: "confirmed" },
    { id: 2, name: "Gym", place: { name: "City CAFE" }, status: "suggested" },
    { id: 3, name: "Office", status: "confirmed" },
  ]
  const ids = (list) => list.map((visit) => visit.id)
  assert.deepEqual(
    ids(filterVisits(visits, { query: "cafe", status: "all" })),
    [1, 2],
  )
  assert.deepEqual(
    ids(filterVisits(visits, { query: "", status: "confirmed" })),
    [1, 3],
  )
  assert.deepEqual(
    ids(filterVisits(visits, { query: " CAFE ", status: "suggested" })),
    [2],
  )
  assert.deepEqual(ids(filterVisits(visits, {})), [1, 2, 3])
})

test("panel padding clears the overlay measured at fit time", () => {
  assert.deepEqual(
    overlayAwarePadding(
      { left: 0, right: 1280, top: 100, bottom: 720 },
      { left: 12, right: 64, top: 112, bottom: 336 },
    ),
    { top: 50, right: 50, bottom: 50, left: 76 },
  )
  assert.deepEqual(overlayAwarePadding(null, null), {
    top: 50,
    right: 50,
    bottom: 50,
    left: 50,
  })

  let right = 300
  const padding = panelPadding({
    container: { getBoundingClientRect: () => ({ left: 0, right: 1280 }) },
    overlay: () => ({ getBoundingClientRect: () => ({ left: 0, right }) }),
  })
  assert.equal(padding().left, 312)
  right = 500
  assert.equal(padding().left, 512)
  assert.equal(
    panelPadding({ container: null, overlay: () => null })().left,
    50,
  )
})

test("native panels above or below the resized map do not offset route fits", () => {
  const map = { left: 0, right: 390, top: 400, bottom: 800 }
  const baseline = { top: 50, right: 50, bottom: 50, left: 50 }
  assert.deepEqual(
    overlayAwarePadding(map, { left: 0, right: 390, top: 0, bottom: 400 }),
    baseline,
  )
  assert.deepEqual(
    overlayAwarePadding(map, { left: 0, right: 390, top: 800, bottom: 900 }),
    baseline,
  )
  assert.equal(
    overlayAwarePadding(map, { left: 0, right: 100, top: 400, bottom: 800 })
      .left,
    112,
  )
})

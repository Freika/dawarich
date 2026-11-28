import assert from "node:assert/strict"
import test from "node:test"
import { TimelineMapBridge } from "controllers/maps/maplibre/timeline_map_bridge"

function buildBridge({ visitsVisible = false, allVisits = [] } = {}) {
  const paint = {}
  const visits = {
    visible: visitsVisible,
    data: { type: "FeatureCollection", features: [{ id: "before" }] },
    updates: [],
    update(data) {
      this.updates.push(data)
      this.data = data
    },
    show() {
      this.visible = true
    },
    hide() {
      this.visible = false
    },
    setLabelOpacity() {},
  }
  const bridge = new TimelineMapBridge({
    map: {
      getLayer: () => true,
      setPaintProperty: (id, property, value) => {
        paint[`${id}.${property}`] = value
      },
      fitBounds() {},
    },
    layerManager: {
      getLayer: (name) => (name === "visits" ? visits : null),
    },
    filterManager: { allVisits },
    dataLoader: {
      visitsToGeoJSON: (list) => ({ features: list }),
    },
  })
  return { bridge, paint, visits }
}

const entry = {
  entryType: "journey",
  startedAt: "2026-03-14T08:00:00Z",
  endedAt: "2026-03-14T09:00:00Z",
}

test("leaving an entry restores the highlighted day", () => {
  const { bridge, paint } = buildBridge()
  bridge.applyDayHighlight("2026-03-14")
  const dayPaint = paint["tracks-mvt.line-opacity"]

  bridge.handleEntryHover({ detail: entry })
  assert.notDeepEqual(paint["tracks-mvt.line-opacity"], dayPaint)

  bridge.handleEntryUnhover()
  assert.deepEqual(paint["tracks-mvt.line-opacity"], dayPaint)
})

test("leaving an entry with no day highlighted restores full opacity", () => {
  const { bridge, paint } = buildBridge()

  bridge.handleEntryHover({ detail: entry })
  bridge.handleEntryUnhover()

  assert.equal(paint["tracks-mvt.line-opacity"], 1)
  assert.equal(paint["visits.circle-opacity"], 0.9)
})

test("hovering a visit keeps only that visit at full opacity", () => {
  const { bridge, paint } = buildBridge()

  bridge.handleEntryHover({
    detail: { ...entry, entryType: "visit", visitId: "7" },
  })

  assert.deepEqual(paint["visits.circle-opacity"], [
    "case",
    ["==", ["get", "id"], 7],
    1,
    0.15,
  ])
})

test("collapsing a day puts a hidden visits layer back the way it was", async () => {
  const day = "2026-03-14"
  const { bridge, visits } = buildBridge({
    allVisits: [{ id: 1, started_at: `${day}T10:00:00Z` }],
  })
  const before = visits.data

  bridge.handleDayExpanded({ detail: { day } })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(visits.visible, true)

  bridge.handleDayCollapsed()

  assert.equal(visits.visible, false)
  assert.equal(visits.data, before)
  assert.equal(bridge.highlightedDay, null)
})

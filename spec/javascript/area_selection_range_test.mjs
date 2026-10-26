import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

let source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/area_selection_manager.js",
    import.meta.url,
  ),
  "utf8",
)
source = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const stubs = `
const translate = (key) => key
const Toast = { info() {}, success() {}, warning() {}, error() {} }
const pointsToGeoJSON = () => ({ type: "FeatureCollection", features: [] })
const anomaliesVisible = () => false
`
const { AreaSelectionManager } = await import(
  `data:text/javascript;base64,${Buffer.from(stubs + source).toString("base64")}`
)

function buildManager({ allTime }) {
  const visitRequests = []
  const checkbox = { checked: allTime }
  const controller = {
    map: {},
    startDateValue: "2026-10-26T00:00:00Z",
    endDateValue: "2026-10-26T23:59:59Z",
    hasSelectAllTimeCheckboxTarget: true,
    selectAllTimeCheckboxTarget: checkbox,
    api: {
      fetchPointsInArea: async () => ({
        points: [{ id: 1 }],
        truncated: false,
      }),
      fetchVisitsInArea: async (params) => {
        visitRequests.push(params)
        return []
      },
    },
  }
  const manager = new AreaSelectionManager(controller)
  manager.selectionLayer = {
    disableSelectionMode() {},
    currentRect: { start: { lat: 1, lng: 1 }, end: { lat: 2, lng: 2 } },
  }
  manager.selectedPointsLayer = { updateSelectedPoints() {}, show() {} }
  manager.displaySelectedVisits = () => {}
  return { manager, checkbox, visitRequests }
}

test("refreshing visits keeps the range the area was selected with", async () => {
  const { manager, checkbox, visitRequests } = buildManager({ allTime: true })

  await manager.handleAreaSelected({
    minLng: 1,
    maxLng: 2,
    minLat: 1,
    maxLat: 2,
  })
  checkbox.checked = false
  await manager.refreshSelectedVisits()

  assert.equal(visitRequests.length, 2)
  for (const params of visitRequests) {
    assert.equal(params.start_at, undefined)
    assert.equal(params.end_at, undefined)
  }
})

test("refreshing visits of a dated selection keeps the map range", async () => {
  const { manager, visitRequests } = buildManager({ allTime: false })

  await manager.handleAreaSelected({
    minLng: 1,
    maxLng: 2,
    minLat: 1,
    maxLat: 2,
  })
  await manager.refreshSelectedVisits()

  assert.equal(visitRequests.length, 2)
  for (const params of visitRequests) {
    assert.equal(params.start_at, "2026-10-26T00:00:00Z")
    assert.equal(params.end_at, "2026-10-26T23:59:59Z")
  }
})

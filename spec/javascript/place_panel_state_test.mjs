import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

async function load() {
  const source = await readFile(
    new URL(
      "../../app/javascript/maps_maplibre/editing/place_editor_state.js",
      import.meta.url,
    ),
    "utf8",
  )
  return import(
    `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
  )
}

test("panel transitions open another place and close without retaining edit mode", async () => {
  const { panelState } = await load()
  assert.deepEqual(panelState(null, { id: 42, edit: true }), {
    id: 42,
    open: true,
    editing: true,
  })
  assert.deepEqual(panelState({ id: 42, editing: true }, { id: 7 }), {
    id: 7,
    open: true,
    editing: false,
  })
  assert.deepEqual(panelState({ id: 42, editing: true }, { close: true }), {
    id: null,
    open: false,
    editing: false,
  })
})

test("place parameters are consumed once while preserving unrelated query and hash", async () => {
  const { consumePlaceParams } = await load()
  const result = consumePlaceParams(
    "https://example.test/map/v2?place_id=42&edit=1&panel=timeline#day",
  )
  assert.deepEqual(result, {
    id: 42,
    edit: true,
    url: "/map/v2?panel=timeline#day",
  })
  assert.equal(consumePlaceParams(`https://example.test${result.url}`), null)
  for (const id of ["nope", "-1", "0", "1.5", "Infinity"]) {
    assert.equal(
      consumePlaceParams(`https://example.test/map/v2?place_id=${id}`),
      null,
    )
  }
})

test("radius handles stay on the geodesic circle at high latitude and across the date line", async () => {
  const { radiusHandle, radiusFromHandle, radiusCircle } = await load()
  assert.ok(
    Math.abs(radiusHandle([0, 0], 1000)[0] - 0.008993216059187304) < 1e-10,
  )
  for (const center of [
    [13.4, 52.5],
    [179.999, 80],
    [-179.999, -80],
  ]) {
    const handle = radiusHandle(center, 1250)
    assert.ok(handle[0] >= -180 && handle[0] <= 180)
    assert.equal(radiusFromHandle(center, handle, 50000), 1250)
    const ring = radiusCircle(center, 1250)
    assert.equal(ring.length, 65)
    assert.deepEqual(ring[0], ring.at(-1))
    for (const point of ring)
      assert.equal(radiusFromHandle(center, point, 50000), 1250)
  }
})

test("radius dragging clamps and rounds to the server supplied bounds", async () => {
  const { radiusFromHandle, radiusHandle } = await load()
  const center = [13.4, 52.5]
  assert.equal(radiusFromHandle(center, center, 50000), 1)
  assert.equal(
    radiusFromHandle(center, radiusHandle(center, 75000), 50000),
    50000,
  )
  assert.equal(radiusFromHandle(center, radiusHandle(center, 20.7), 30), 21)
  assert.equal(radiusFromHandle(center, radiusHandle(center, 100), 30), 30)
})

test("place navigation remembers the original tab and visibility across replacement opens", async () => {
  const { panelState } = await load()
  const returnTo = { tab: "timeline-feed", open: false, scrollTop: 120 }
  const first = panelState(null, { id: 2, returnTo })
  const second = panelState(first, {
    id: 3,
    returnTo: { tab: "place", open: true },
  })
  assert.deepEqual(second.returnTo, returnTo)
  assert.equal(second.id, 3)
  assert.equal(panelState(second, { close: true }).open, false)
  assert.equal(panelState(second, { close: true }).returnTo, undefined)
})

test("external place links centre once while map clicks preserve the camera", async () => {
  const { shouldCenterPlace } = await load()
  assert.equal(shouldCenterPlace({ origin: "link", edit: false }), true)
  assert.equal(shouldCenterPlace({ origin: "link", edit: true }), true)
  assert.equal(shouldCenterPlace({ origin: "map", edit: false }), false)
  assert.equal(shouldCenterPlace({ origin: "map", edit: true }), true)
})

test("place camera bounds contain the radius including date-line places", async () => {
  const { placeBounds, radiusCircle } = await load()
  for (const place of [
    { longitude: 13.4, latitude: 52.5, visit_radius: 125 },
    { longitude: 179.999, latitude: 80, visit_radius: 1250 },
  ]) {
    const [sw, ne] = placeBounds(place)
    assert.ok(ne[0] - sw[0] < 1)
    for (const [lng, lat] of radiusCircle(
      [place.longitude, place.latitude],
      place.visit_radius,
    )) {
      assert.ok(lng >= sw[0] && lng <= ne[0])
      assert.ok(lat >= sw[1] && lat <= ne[1])
    }
    assert.ok(sw[0] < place.longitude && ne[0] > place.longitude)
    assert.ok(sw[1] < place.latitude && ne[1] > place.latitude)
  }
})

test("place camera padding accounts for an overlapping left panel without double counting a shrunken map", async () => {
  const { placeCameraOptions } = await load()
  const mapRect = { left: 0, right: 1440, width: 1440, height: 700 }
  const panelRect = { left: 0, right: 480 }
  const overlay = placeCameraOptions(mapRect, panelRect)
  assert.ok(overlay.padding.left >= 500)
  assert.ok(overlay.padding.right < 100)
  assert.equal(overlay.maxZoom, 17)
  const shrunk = placeCameraOptions(
    { ...mapRect, left: 480, width: 960 },
    panelRect,
  )
  assert.ok(shrunk.padding.left < 100)
  const phone = placeCameraOptions(
    { left: 160, right: 390, width: 230, height: 650 },
    { left: 0, right: 160 },
    { left: 170, right: 214 },
  )
  assert.ok(phone.padding.left >= 60)
  assert.ok(phone.padding.left + phone.padding.right < 230)
  assert.ok(phone.padding.top + phone.padding.bottom < 650)
})

test("selected place features show the owner's geometry and amber geofence independently of enabled layers", async () => {
  const { selectedPlaceFeatures } = await load()
  const place = {
    id: 2,
    longitude: 13.4,
    latitude: 52.5,
    visit_radius: 125,
    geofence: true,
    color: "#123456",
  }
  const selected = selectedPlaceFeatures(place)
  assert.equal(selected.type, "FeatureCollection")
  assert.equal(selected.features.length, 2)
  const point = selected.features.find((f) => f.geometry.type === "Point")
  const boundary = selected.features.find((f) => f.geometry.type === "Polygon")
  assert.deepEqual(point.geometry.coordinates, [13.4, 52.5])
  assert.equal(point.properties.id, 2)
  assert.equal(point.properties.color, "#123456")
  assert.equal(boundary.properties.color, "#f59e0b")
  assert.equal(boundary.geometry.coordinates[0].length, 65)
  const ordinary = selectedPlaceFeatures({ ...place, geofence: false })
  assert.equal(ordinary.features[1].properties.color, "#123456")
  assert.deepEqual(selectedPlaceFeatures(null).features, [])
  assert.deepEqual(
    selectedPlaceFeatures({ ...place, latitude: null }).features,
    [],
  )
})

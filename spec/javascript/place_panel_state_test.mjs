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

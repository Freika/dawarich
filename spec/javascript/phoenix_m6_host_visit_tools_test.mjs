import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

test("native map host creates visits and routes tile point addresses", async () => {
  const f = fixture()
  const button = new Element()
  f.nodes.set('[data-testid="native-create-visit"]', button)
  await f.owner.mount()
  button.emit("click")
  f.map.emit("click", { lngLat: { lat: 52, lng: 13 } })
  assert.equal(
    f.pushed.some((item) => item.event === "visit:new"),
    true,
  )
  f.map.emit("click:points-mvt", { features: [{ properties: { id: 7 } }] })
  assert.deepEqual(
    f.pushed.find((item) => item.event === "address:open").payload,
    { id: 7 },
  )
  f.owner.destroy()
  assert.equal(f.listeners.get("click:points-mvt").size, 0)
})

test("native tile click opens only an individual point and ignores aggregate counts", async () => {
  const f = fixture()
  await f.owner.mount()
  for (const properties of [
    { id: 8, count: 4 },
    { id: 9, point_count: 3 },
    { id: 10, cluster: true },
    { id: 11, count: 1, point_count: 1 },
  ])
    f.map.emit("click:points-mvt", { features: [{ properties }] })
  assert.deepEqual(
    f.pushed
      .filter((item) => item.event === "address:open")
      .map((item) => item.payload),
    [{ id: 11 }],
  )
  f.owner.destroy()
})

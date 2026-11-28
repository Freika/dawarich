import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"

const moduleData = (source) =>
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const h3Url = moduleData(
  readFileSync(
    new URL("../../vendor/javascript/h3-js.js", import.meta.url),
    "utf8",
  ),
)
const source = readFileSync(
  new URL(
    "../../app/javascript/maps_maplibre/layers/fog_hexagon_source.js",
    import.meta.url,
  ),
  "utf8",
).replace('import("h3-js")', `import(${JSON.stringify(h3Url)})`)
const { FogHexagonSource } = await import(moduleData(source))
const h3 = await import(h3Url)

test("fog preserves exact resolution-nine openings at every zoom and highlights only first discoveries", async () => {
  const id = h3.latLngToCell(52.51, 13.35, 9)
  const parent = h3.cellToParent(id, 5)
  const source = new FogHexagonSource()
  await source.load(
    {
      fetchFogHexagons: async () => ({
        h3_indexes: [id, parent],
        new_h3_indexes: [id],
        metadata: { status: "ready", snapshot_id: 1 },
      }),
    },
    {},
  )
  for (const zoom of [1, 5, 10, 18]) {
    const cells = source.boundariesFor(zoom)
    assert.equal(cells.length, 1)
    assert.equal(cells[0].id, id)
    assert.equal(cells[0].newlyOpened, true)
    assert.deepEqual(cells[0].coords, h3.cellToBoundary(id, true))
  }
})

test("a dateline cell follows short edges instead of clearing the whole world", async () => {
  const id = h3.latLngToCell(1, 179.9999, 9)
  const source = new FogHexagonSource()
  await source.load(
    { fetchFogHexagons: async () => ({ h3_indexes: [id] }) },
    {},
  )
  const coords = source.boundariesFor(2)[0].coords
  for (let i = 0; i < coords.length; i++)
    assert.ok(Math.abs(coords[i][0] - coords[(i + 1) % coords.length][0]) < 1)
})

test("a delayed old date-range response cannot replace a newer published snapshot", async () => {
  let finish
  const source = new FogHexagonSource()
  const pending = source.load(
    {
      fetchFogHexagons: () =>
        new Promise((resolve) => {
          finish = resolve
        }),
    },
    {},
  )
  const id = h3.latLngToCell(52, 13, 9)
  await source.load(
    {
      fetchFogHexagons: async () => ({
        h3_indexes: [id],
        metadata: { snapshot_id: 2 },
      }),
    },
    {},
  )
  finish({ h3_indexes: [], metadata: { snapshot_id: 1 } })
  assert.equal(await pending, false)
  assert.deepEqual(source.rawCellIds, [id])
  assert.equal(source.metadata.snapshot_id, 2)
})

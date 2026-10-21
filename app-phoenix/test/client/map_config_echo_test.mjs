import assert from "node:assert/strict"
import test from "node:test"
import { createReader } from "../../assets/js/map/data/reader.js"
import { fixture } from "../../../spec/javascript/support/native_m6_host_fixture.mjs"

const track = {
  type: "Feature",
  properties: { id: 9, revision: 0 },
  geometry: { type: "LineString", coordinates: [[13, 52], [14, 53]] },
}
const points = [{ id: 7, longitude: 13, latitude: 52, revision: 0 }]

test("an identical config echo preserves an in-flight editor selection and reader generation", async () => {
  const reads = []
  const reader = createReader({
    origin: "https://native.test",
    fetch: (url) => new Promise(resolve => reads.push({ url, resolve })),
  })
  const f = fixture({ editEnabled: true }, { reader })
  try {
    await f.owner.mount()
    const generation = reader.revision
    const selecting = f.owner.editor.selectTrack(9)
    const result = selecting.then(() => "selected", error => error.name)
    assert.equal(reads.length, 2)
    await f.owner.update(structuredClone(f.owner.config))
    for (const read of reads) read.resolve(new Response(JSON.stringify(
      new URL(read.url).pathname.endsWith("/points") ? points : { type: "FeatureCollection", features: [track] },
    ), { headers: { "x-total-pages": "1" } }))
    assert.equal(await result, "selected")
    assert.equal(reader.revision, generation)
    assert.equal(f.owner.editor.trackId, 9)
  } finally {
    f.owner.destroy()
  }
})

test("an identical config echo preserves the selected timeline overlay", async () => {
  const f = fixture({ editEnabled: true })
  f.reader.read = async () => ({ data: track })
  try {
    await f.owner.mount()
    await f.owner.timeline.select({ id: 9 })
    const selected = f.sources.get("native-selected-track")
    assert.ok(selected)
    await f.owner.update(structuredClone(f.owner.config))
    assert.equal(f.sources.get("native-selected-track"), selected)
  } finally {
    f.owner.destroy()
  }
})

import assert from "node:assert/strict"
import { test } from "node:test"
import { fixture } from "./support/native_m6_host_fixture.mjs"

test("map host timeline hover reads the canonical track and clears on range replacement", async () => {
  const f = fixture()
  try {
    await f.owner.mount()
    f.root.emit("pointerover", {
      target: { closest: () => ({ dataset: { trackId: "7" } }) },
    })
    await new Promise((resolve) => setImmediate(resolve))
    assert.deepEqual(
      f.reads.find(({ resource }) => resource === "track"),
      { resource: "track", params: { id: "7" } },
    )
    assert.equal(
      f.sources.get("native-timeline-hover").data.geometry.coordinates.length,
      2,
    )
    await f.owner.update({ ...f.owner.config, revision: 2 })
    assert.equal(f.sources.has("native-timeline-hover"), false)
    f.owner.destroy()
    assert.equal(f.root.listeners.get("pointerover").size, 0)
  } finally {
    f.owner.destroy()
  }
})

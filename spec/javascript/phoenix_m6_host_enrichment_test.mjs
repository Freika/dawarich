import assert from "node:assert/strict"
import test from "node:test"
import { fixture } from "./support/native_m6_host_fixture.mjs"

test("native host owns enrichment marker replies and removes them on range replacement", async () => {
  const f = fixture()
  await f.owner.mount()
  f.owner.enrichment.matches({
    matches: [{ immich_asset_id: "synthetic", latitude: 52, longitude: 13 }],
  })
  assert.equal(
    f.sources.get("native-enrichment-matches").data.features.length,
    1,
  )
  await f.owner.update({ ...f.owner.config, revision: 2 })
  assert.equal(f.sources.has("native-enrichment-matches"), false)
  f.owner.destroy()
})

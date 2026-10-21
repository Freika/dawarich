import assert from "node:assert/strict"
import test from "node:test"
import { fixture } from "./support/native_m6_host_fixture.mjs"

test("native host settings change style and rebuild owned tiles", async () => {
  const f = fixture()
  let applied
  f.map.setStyle = (style) => {
    applied = style
    f.map.emit("style.load")
  }
  await f.owner.mount()
  await f.owner.settings({
    settings: { maps_maplibre_style: "dark", tracks: true, points: true },
  })
  assert.equal(applied.version, 8)
  assert.equal(f.layers.has("points-mvt"), true)
  assert.equal(f.owner.config.styleName, "dark")
  f.owner.destroy()
})

test("layer settings preserve the active style and selected overlays", async () => {
  const f = fixture({
    styleName: "light",
    styleUrl: "/maps_maplibre/styles/light.json",
  })
  let replacements = 0
  f.map.setStyle = () => {
    replacements++
    f.layers.clear()
    f.sources.clear()
  }
  await f.owner.mount()
  f.map.addLayer({ id: "selected-overlay" })
  await f.owner.settings({
    settings: { enabled_map_layers: ["Points", "Tracks"] },
  })
  assert.equal(replacements, 0)
  assert.equal(f.layers.has("selected-overlay"), true)
  assert.equal(f.owner.config.tracksEnabled, true)
  f.owner.destroy()
})

test("an unconfigured photo layer leaves the map and base layers usable", async () => {
  const f = fixture({ photosEnabled: true, pointsEnabled: true })
  f.map.querySourceFeatures = () => []
  f.reader.pages = async () => {
    throw Object.assign(new Error("unconfigured"), {
      status: 401,
      code: "photos_unconfigured",
    })
  }
  assert.equal(await f.owner.mount(), "ready")
  assert.equal(f.layers.has("points-mvt"), true)
  assert.equal(f.sources.get("photos-source").data.features.length, 0)
  assert.equal(
    f.pushed.some(({ payload }) => payload.code === "photos_unconfigured"),
    true,
  )
  f.owner.destroy()
})

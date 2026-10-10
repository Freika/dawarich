import assert from "node:assert/strict"
import test from "node:test"
import { fixture } from "./support/native_m6_host_fixture.mjs"

test("native host applies custom style tokens categories track color and next-creation globe", async () => {
  const f = fixture()
  let applied, color
  f.map.setStyle = style => {applied = style}
  f.map.setPaintProperty = (id, name, value) => {if (id === "tracks-mvt" && name === "line-color") color = value}
  await f.owner.mount()
  await f.owner.settings({settings: {maps_maplibre_style: "custom", maps_maplibre_custom_theme: {base: "noir", tokens: {bg: "#123456", water: "#223344", parks: "#334455", road_default: "#444444"}}, track_color: "#abcdef", globe_projection: true, maps: {hidden_tile_categories: ["buildings"], disabled_poi_groups: ["food_drink"]}}})
  assert.equal(applied.layers.find(layer => layer.type === "background").paint["background-color"], "#123456")
  assert.equal(applied.layers.some(layer => layer.id === "poster_buildings"), false)
  assert.equal(color, "#abcdef")
  assert.deepEqual(f.owner.config.mapOptions.projection, {type: "globe"})
  assert.deepEqual(f.owner.config.disabledPoiGroups, ["food_drink"])
  f.owner.destroy()
})

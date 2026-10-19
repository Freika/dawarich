import assert from "node:assert/strict"
import test from "node:test"
import { applyMapStyle } from "../../assets/js/map/style/map_style.js"

const rails =
  '<a href="https://github.com/protomaps/basemaps">Protomaps</a> © <a href="https://openstreetmap.org">OpenStreetMap</a>'

test("the basemap credits Protomaps and OpenStreetMap like the Rails map", () => {
  const style = {
    version: 8,
    sources: {
      protomaps: { type: "vector", tiles: ["https://t/{z}/{x}/{y}.mvt"] },
    },
    layers: [],
  }
  assert.equal(applyMapStyle(style, {}).sources.protomaps.attribution, rails)
})

test("a style that names its own attribution keeps it", () => {
  const style = {
    version: 8,
    sources: { protomaps: { type: "vector", attribution: "Own" } },
    layers: [],
  }
  assert.equal(applyMapStyle(style, {}).sources.protomaps.attribution, "Own")
})

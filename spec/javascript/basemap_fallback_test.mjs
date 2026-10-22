import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/basemap_fallback.js",
    import.meta.url,
  ),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { composeVectorFallback, composeRasterFallback, CUSTOM_SOURCE_ID } =
  await import(moduleUrl)

const DEFAULT_URL = "https://tyles.dwri.xyz/planet/{z}/{x}/{y}.mvt"
const CUSTOM_URL = "https://tiles.example.de/{z}/{x}/{y}.mvt"
const CUSTOM_RASTER_URL = "https://tiles.example.de/{z}/{x}/{y}.png"

function baseStyle() {
  return {
    version: 8,
    glyphs: "https://example.com/{fontstack}/{range}.pbf",
    sprite: "https://example.com/sprite",
    sources: {
      protomaps: {
        type: "vector",
        tiles: [DEFAULT_URL],
        minzoom: 0,
        maxzoom: 15,
        attribution: "Protomaps",
      },
    },
    layers: [
      {
        id: "background",
        type: "background",
        paint: { "background-color": "#ccc" },
      },
      {
        id: "earth",
        type: "fill",
        source: "protomaps",
        "source-layer": "earth",
      },
      {
        id: "buildings",
        type: "fill",
        source: "protomaps",
        "source-layer": "buildings",
      },
      {
        id: "place_labels",
        type: "symbol",
        source: "protomaps",
        "source-layer": "places",
      },
    ],
  }
}

test("vector fallback keeps the default source and adds the custom one", () => {
  const composed = composeVectorFallback(baseStyle(), CUSTOM_URL)

  assert.deepEqual(composed.sources.protomaps.tiles, [DEFAULT_URL])
  assert.deepEqual(composed.sources[CUSTOM_SOURCE_ID].tiles, [CUSTOM_URL])
  assert.equal(composed.sources[CUSTOM_SOURCE_ID].type, "vector")
})

test("vector fallback does not attribute the user's tiles to Protomaps", () => {
  const composed = composeVectorFallback(baseStyle(), CUSTOM_URL)

  assert.equal(composed.sources.protomaps.attribution, "Protomaps")
  assert.equal(composed.sources[CUSTOM_SOURCE_ID].attribution, "")
})

test("vector fallback never duplicates the background layer", () => {
  const composed = composeVectorFallback(baseStyle(), CUSTOM_URL)
  const backgrounds = composed.layers.filter((l) => l.type === "background")

  assert.equal(backgrounds.length, 1)
  assert.equal(backgrounds[0].id, "background")
})

test("vector fallback re-points every duplicated layer at the custom source", () => {
  const composed = composeVectorFallback(baseStyle(), CUSTOM_URL)
  const duplicated = composed.layers.filter((l) => l.id.endsWith("__custom"))

  assert.equal(duplicated.length, 3)
  for (const layer of duplicated) {
    assert.equal(layer.source, CUSTOM_SOURCE_ID)
  }
  assert.deepEqual(
    duplicated.map((l) => l.id),
    ["earth__custom", "buildings__custom", "place_labels__custom"],
  )
})

test("vector fallback draws the custom stack above every default layer", () => {
  const composed = composeVectorFallback(baseStyle(), CUSTOM_URL)
  const firstCustom = composed.layers.findIndex((l) =>
    l.id.endsWith("__custom"),
  )
  const lastDefault = composed.layers.reduce(
    (last, layer, index) => (layer.id.endsWith("__custom") ? last : index),
    -1,
  )

  assert.ok(firstCustom > lastDefault)
})

test("vector fallback leaves layers bound to other sources alone", () => {
  const style = baseStyle()
  style.sources.other = {
    type: "geojson",
    data: { type: "FeatureCollection", features: [] },
  }
  style.layers.push({ id: "extra", type: "circle", source: "other" })

  const composed = composeVectorFallback(style, CUSTOM_URL)

  assert.equal(
    composed.layers.filter((l) => l.id === "extra__custom").length,
    0,
  )
})

test("vector fallback does not mutate the style it was given", () => {
  const style = baseStyle()
  composeVectorFallback(style, CUSTOM_URL)

  assert.equal(style.layers.length, 4)
  assert.equal(Object.keys(style.sources).length, 1)
})

test("raster fallback keeps the whole default basemap below the raster layer", () => {
  const composed = composeRasterFallback(baseStyle(), CUSTOM_RASTER_URL)
  const ids = composed.layers.map((l) => l.id)

  assert.deepEqual(ids.slice(0, 4), [
    "background",
    "earth",
    "buildings",
    "place_labels",
  ])
  assert.equal(ids.at(-1), "basemap-raster")
  assert.equal(composed.layers.at(-1).type, "raster")
})

test("raster fallback points its raster source at the custom tiles", () => {
  const composed = composeRasterFallback(baseStyle(), CUSTOM_RASTER_URL)
  const raster = composed.sources[CUSTOM_SOURCE_ID]

  assert.equal(raster.type, "raster")
  assert.deepEqual(raster.tiles, [CUSTOM_RASTER_URL])
  assert.equal(raster.attribution, "")
  assert.equal(composed.layers.at(-1).source, CUSTOM_SOURCE_ID)
})

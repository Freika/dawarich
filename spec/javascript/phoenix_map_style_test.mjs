import assert from "node:assert/strict"
import { test } from "node:test"
import {
  fetchStyle,
  installStyleFallback,
} from "../../app-phoenix/assets/js/map/style/load_style.js"

const base = {
  version: 8,
  glyphs: "glyphs/{fontstack}/{range}.pbf",
  sprite: "sprites/light",
  sources: {
    protomaps: {
      type: "vector",
      tiles: ["https://tiles.test/{z}/{x}/{y}.mvt"],
    },
  },
  layers: [{ id: "background", type: "background" }],
}
const response = (ok = true) => ({
  ok,
  json: async () => structuredClone(base),
})

test("native style loader preserves raster vector overlays and resolves relative style assets", async () => {
  const fetch = async () => response()
  const raster = await fetchStyle(
    { tilesUrl: "https://r.test/{z}/{x}/{y}.png" },
    { fetch },
  )
  assert.equal(raster.sources.protomaps.type, "raster")
  const fallback = await fetchStyle(
    { tilesUrl: "https://v.test/{z}/{x}/{y}.mvt", tilesFallback: true },
    { fetch },
  )
  assert.ok(fallback.sources.protomaps_custom)
  const custom = await fetchStyle(
    { tilesUrl: "https://style.test/path/style.json" },
    { fetch },
  )
  assert.equal(custom.sprite, "https://style.test/path/sprites/light")
  assert.equal(
    custom.glyphs,
    "https://style.test/path/glyphs/{fontstack}/{range}.pbf",
  )
})

test("style-document failure falls back but individual tile failure does not discard style", async () => {
  const handlers = new Map(),
    styles = []
  const map = {
    on: (event, fn) => handlers.set(event, fn),
    off: (event) => handlers.delete(event),
    setStyle: (style) => styles.push(style),
  }
  const owner = installStyleFallback({
    map,
    getConfig: () => ({ tilesUrl: "https://style.test/map.json" }),
    load: async () => base,
  })
  await handlers.get("error")({ error: { url: "https://tile.test/tile.pbf" } })
  assert.equal(styles.length, 0)
  await handlers.get("error")({ error: { url: "https://style.test/map.json" } })
  assert.equal(styles.length, 1)
  owner.destroy()
  assert.equal(handlers.size, 0)
})

test("destroy during fallback style fetch cannot set style on removed map", async () => {
  let resolve
  const pending = new Promise((r) => {
    resolve = r
  })
  const handlers = new Map(),
    styles = []
  const map = {
    on: (e, f) => handlers.set(e, f),
    off: (e) => handlers.delete(e),
    setStyle: (s) => styles.push(s),
  }
  const owner = installStyleFallback({
    map,
    getConfig: () => ({ tilesUrl: "https://style.test/map.json" }),
    load: () => pending,
  })
  const run = handlers.get("error")({
    error: { url: "https://style.test/map.json" },
  })
  owner.destroy()
  resolve(base)
  await run
  assert.equal(styles.length, 0)
})

import assert from "node:assert/strict"
import { test } from "node:test"
import { resolveTheme } from "../../app-phoenix/assets/js/poster/data/theme_loader.js"
import {
  drawOverlay,
  POSTER_ATTRIBUTION,
} from "../../app-phoenix/assets/js/poster/render/overlay.js"
import {
  buildBasemapStyle,
  buildPosterStyle,
  TRACK_SOURCE_ID,
} from "../../app-phoenix/assets/js/poster/render/style_builder.js"
import {
  formatCoords,
  layoutPosterText,
  titleShrink,
} from "../../app-phoenix/assets/js/poster/render/text_layout.js"

const theme = resolveTheme({
  bg: "#101010",
  text: "#fafafa",
  water: "#0000ff",
  parks: "#00ff00",
  road_motorway: "#111111",
  road_primary: "#222222",
  road_secondary: "#333333",
  road_tertiary: "#444444",
  road_residential: "#555555",
  road_default: "#666666",
})

test("poster style hides live-map extras by default and keeps the track on top", () => {
  const geojson = { type: "FeatureCollection", features: [] }
  const style = buildPosterStyle({
    theme,
    trackGeojson: geojson,
    trackOpacity: 0.5,
    trackWidth: 2,
  })
  const ids = style.layers.map((layer) => layer.id)
  assert.deepEqual(ids.slice(0, 5), [
    "poster_bg",
    "poster_earth",
    "poster_parks",
    "poster_water",
    "poster_water_lines",
  ])
  assert.ok(!ids.includes("poster_buildings"))
  assert.deepEqual(ids.slice(-2), ["poster_track_casing", "poster_track"])
  assert.equal(style.sources[TRACK_SOURCE_ID].data, geojson)
  const track = style.layers.at(-1)
  assert.equal(track.paint["line-color"], theme.route)
  assert.equal(track.paint["line-opacity"], 0.5)
  assert.deepEqual(track.paint["line-width"].slice(3), [8, 3, 12, 5.2, 16, 9.2])
  assert.equal(style.layers.at(-2).paint["line-color"], theme.casing)
  assert.equal(
    buildPosterStyle({ theme, trackColor: "#abcdef" }).layers.at(-1).paint[
      "line-color"
    ],
    "#abcdef",
  )
})

test("hidden base-map categories drop their layers and extras add live-map layers", () => {
  const ids = buildBasemapStyle({
    theme,
    extras: true,
    hiddenCategories: ["water", "roads", "rail"],
  }).layers.map((layer) => layer.id)
  assert.deepEqual(ids, [
    "poster_bg",
    "poster_earth",
    "poster_parks",
    "poster_buildings",
    "poster_boundaries",
  ])
  assert.throws(() => buildBasemapStyle({}), /resolved theme/)
  const roads = buildBasemapStyle({ theme, roadScale: 2 }).layers.find(
    (layer) => layer.id === "poster_roads_highway",
  )
  assert.equal(roads.paint["line-color"], "#111111")
  assert.deepEqual(roads.paint["line-width"].slice(3, 5), [5, 0.8])
})

test("title shrink keeps long titles within the poster width", () => {
  assert.equal(titleShrink("Berlin"), 1)
  assert.equal(titleShrink("  twelve chars  "), 1)
  assert.equal(titleShrink("x".repeat(24)), 0.5)
  assert.equal(titleShrink("x".repeat(100)), 0.45)
  const long = layoutPosterText({
    width: 1200,
    height: 1600,
    title: "x".repeat(24),
  })
  assert.equal(long.titleSize, 45)
})

test("text stack collapses empty lines from the bottom margin", () => {
  assert.deepEqual(
    layoutPosterText({
      width: 1200,
      height: 1600,
      title: "Berlin",
      subtitle: "Germany",
      coords: "52.5200° N / 13.4050° E",
    }),
    {
      coordsY: 1528,
      subY: 1490,
      dividerY: 1443,
      titleY: 1393,
      titleSize: 90,
      subSize: 31,
      coordsSize: 20,
      letterSpacing: 16,
      dividerHalfWidth: 144,
      dividerWidth: 2,
    },
  )
  const titleOnly = layoutPosterText({ width: 1200, height: 1600, title: "A" })
  assert.equal(titleOnly.titleY, 1505)
  assert.equal(titleOnly.subY, undefined)
  assert.equal(titleOnly.coordsY, undefined)
})

test("coordinates format hemispheres with four decimals", () => {
  assert.equal(
    formatCoords({ lat: 52.52, lng: 13.405 }),
    "52.5200° N / 13.4050° E",
  )
  assert.equal(
    formatCoords({ lat: -33.8688, lng: -70.1 }),
    "33.8688° S / 70.1000° W",
  )
  assert.equal(formatCoords(null), "")
})

test("overlay draws an uppercase centred title with tracking compensation and a subtle attribution", () => {
  const calls = []
  const context = {
    letterSpacing: "0px",
    createLinearGradient: () => ({ addColorStop: () => {} }),
    fillRect: (...args) => calls.push(["fillRect", context.fillStyle, ...args]),
    fillText: (...args) =>
      calls.push(["fillText", context.font, context.letterSpacing, ...args]),
    beginPath() {},
    moveTo() {},
    lineTo() {},
    stroke() {},
    save() {},
    restore() {},
  }
  const canvas = { width: 1200, height: 1600, getContext: () => context }
  drawOverlay(canvas, {
    theme,
    title: "Berlin",
    font: "Poster",
    margin: 0.05,
  })
  const texts = calls.filter((call) => call[0] === "fillText")
  assert.deepEqual(texts[0], [
    "fillText",
    "700 90px Poster",
    "16px",
    "BERLIN",
    608,
    1505,
  ])
  assert.equal(texts.at(-1)[3], POSTER_ATTRIBUTION)
  assert.equal(texts.at(-1)[1], "400 16px Poster")
  assert.deepEqual(calls[0], ["fillRect", "#101010", 0, 0, 1200, 60])
})

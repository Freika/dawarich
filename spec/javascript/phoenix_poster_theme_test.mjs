import assert from "node:assert/strict"
import { test } from "node:test"
import {
  DEFAULT_FONT_KEY,
  ensurePosterFont,
  fontByKey,
  POSTER_FONTS,
} from "../../app-phoenix/assets/js/poster/data/fonts.js"
import {
  PRINT_PRODUCTS,
  printProductFor,
} from "../../app-phoenix/assets/js/poster/data/print_products.js"
import {
  DEFAULT_TILE_URL,
  PARK_KINDS,
  ROAD_BUCKETS,
  SOURCE_MAX_ZOOM,
} from "../../app-phoenix/assets/js/poster/data/protomaps_schema.js"
import {
  DEFAULT_ROUTE_COLOR,
  extendTokens,
  loadThemeTokens,
  resolveTheme,
} from "../../app-phoenix/assets/js/poster/data/theme_loader.js"

const tokens = {
  name: "Synthetic",
  bg: "#000000",
  text: "#ffffff",
  water: "#0000ff",
  parks: "#00ff00",
  road_motorway: "#111111",
  road_primary: "#222222",
  road_secondary: "#333333",
  road_tertiary: "#444444",
  road_residential: "#555555",
  road_default: "#666666",
}

test("derived building, railway and boundary tokens mix toward the text colour", () => {
  assert.deepEqual(extendTokens(tokens), {
    buildings: "#141414",
    railway: "#666666",
    boundaries: "#4d4d4d",
  })
  assert.equal(
    extendTokens({ ...tokens, buildings: "#abcdef" }).buildings,
    "#abcdef",
  )
  assert.equal(extendTokens({ ...tokens, bg: "bad" }).buildings, "bad")
})

test("theme resolution keeps the print route and casing colours", () => {
  const theme = resolveTheme(tokens)
  assert.equal(theme.route, DEFAULT_ROUTE_COLOR)
  assert.equal(theme.casing, "#000000")
  assert.equal(theme.gradientColor, "#000000")
  assert.equal(theme.roads.default, "#666666")
  assert.equal(theme.roads.motorway, "#111111")
  assert.equal(resolveTheme({ ...tokens, route: "#123456" }).route, "#123456")
  assert.equal(
    resolveTheme({ ...tokens, gradient_color: "#fedcba" }).gradientColor,
    "#fedcba",
  )
})

test("theme tokens load once per key from the static theme path", async () => {
  const requests = []
  const fetch = async (url, options) => {
    requests.push([url, options?.signal])
    return url.endsWith("broken_theme_key.json")
      ? { ok: false, status: 404 }
      : { ok: true, json: async () => ({ ...tokens, name: url }) }
  }
  const signal = new AbortController().signal
  const first = await loadThemeTokens("synthetic_theme_key", { fetch, signal })
  const second = await loadThemeTokens("synthetic_theme_key", { fetch })
  assert.equal(first, second)
  assert.deepEqual(requests, [
    ["/poster_themes/synthetic_theme_key.json", signal],
  ])
  await assert.rejects(
    loadThemeTokens("broken_theme_key", { fetch }),
    /broken_theme_key.*404/,
  )
  await assert.rejects(loadThemeTokens("broken_theme_key", { fetch }), /404/)
  assert.equal(requests.length, 3)
})

test("poster fonts load both weights once per font set and fall back to the first family", async () => {
  const added = []
  const fonts = { add: (face) => added.push(face) }
  class FakeFace {
    constructor(family, source, { weight }) {
      Object.assign(this, { family, source, weight })
    }
    async load() {
      return this
    }
  }
  const urls = { "oswald-400": "/o4.woff2", "oswald-700": "/o7.woff2" }
  const family = await ensurePosterFont("oswald", urls, {
    fonts,
    FontFace: FakeFace,
  })
  await ensurePosterFont("oswald", urls, { fonts, FontFace: FakeFace })
  assert.equal(family, "Poster Oswald")
  assert.deepEqual(
    added.map((face) => [face.source, face.weight]),
    [
      ["url(/o4.woff2)", "400"],
      ["url(/o7.woff2)", "700"],
    ],
  )
  const other = []
  await ensurePosterFont("oswald", urls, {
    fonts: { add: (face) => other.push(face) },
    FontFace: FakeFace,
  })
  assert.equal(other.length, 2)
  assert.equal(fontByKey("missing").key, POSTER_FONTS[0].key)
  assert.equal(DEFAULT_FONT_KEY, "oswald")
})

test("only the three large print layouts are orderable with server SKUs", () => {
  assert.deepEqual(Object.keys(PRINT_PRODUCTS), [
    "print-30x40",
    "print-50x70",
    "print-70x100",
  ])
  assert.equal(printProductFor("print-50x70").sku, "poster-50x70")
  assert.equal(printProductFor("print-a3"), null)
})

test("protomaps road buckets map coarse kinds onto theme road keys", () => {
  assert.deepEqual(
    ROAD_BUCKETS.map((bucket) => [bucket.id, bucket.themeKey]),
    [
      ["poster_roads_other", "default"],
      ["poster_roads_minor", "residential"],
      ["poster_roads_major", "primary"],
      ["poster_roads_highway", "motorway"],
    ],
  )
  assert.equal(SOURCE_MAX_ZOOM, 15)
  assert.match(DEFAULT_TILE_URL, /\{z\}\/\{x\}\/\{y\}\.mvt$/)
  assert.ok(PARK_KINDS.includes("national_park"))
})

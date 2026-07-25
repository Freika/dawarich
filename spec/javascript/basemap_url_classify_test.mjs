import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/basemap_url.js",
    import.meta.url,
  ),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { classifyBasemapUrl } = await import(moduleUrl)

test("classifies a raster XYZ URL with a jpg extension as raster", () => {
  assert.equal(
    classifyBasemapUrl(
      "https://api.maptiler.com/maps/hybrid/256/{z}/{x}/{y}.jpg?key=abc",
    ),
    "raster",
  )
})

test("classifies png, jpeg, and webp XYZ URLs as raster", () => {
  assert.equal(
    classifyBasemapUrl("https://t.example/{z}/{x}/{y}.png"),
    "raster",
  )
  assert.equal(
    classifyBasemapUrl("https://t.example/{z}/{x}/{y}.jpeg"),
    "raster",
  )
  assert.equal(
    classifyBasemapUrl("https://t.example/{z}/{x}/{y}.webp"),
    "raster",
  )
})

test("classifies an XYZ MVT or PBF URL as vector", () => {
  assert.equal(
    classifyBasemapUrl("https://tiles.example/{z}/{x}/{y}.mvt"),
    "vector",
  )
  assert.equal(
    classifyBasemapUrl("https://tiles.example/{z}/{x}/{y}.pbf"),
    "vector",
  )
})

test("classifies an extensionless XYZ URL as vector", () => {
  assert.equal(
    classifyBasemapUrl("https://tiles.example/{z}/{x}/{y}"),
    "vector",
  )
})

test("classifies a URL whose path ends in json as a full style", () => {
  assert.equal(
    classifyBasemapUrl("https://api.maptiler.com/maps/streets/style.json"),
    "style",
  )
})

test("ignores the query string when detecting a style json path", () => {
  assert.equal(
    classifyBasemapUrl(
      "https://api.maptiler.com/maps/streets/style.json?key=abc",
    ),
    "style",
  )
})

test("ignores URL fragments when detecting a style json path", () => {
  assert.equal(
    classifyBasemapUrl(
      "https://api.maptiler.com/maps/streets/style.json#revision",
    ),
    "style",
  )
})

test("classifies a json XYZ tile template as vector, not a style", () => {
  assert.equal(
    classifyBasemapUrl("https://tiles.example/{z}/{x}/{y}.json"),
    "vector",
  )
})

test("does not classify a json XYZ tile template with a query string as a style", () => {
  assert.equal(
    classifyBasemapUrl("https://tiles.example/{z}/{x}/{y}.json?key=abc"),
    "vector",
  )
})

test("ignores the query string when detecting a raster extension", () => {
  assert.equal(
    classifyBasemapUrl("https://t.example/{z}/{x}/{y}.png?token=xyz&s=256"),
    "raster",
  )
})

test("detects extensions case-insensitively", () => {
  assert.equal(
    classifyBasemapUrl("https://t.example/{z}/{x}/{y}.PNG"),
    "raster",
  )
  assert.equal(classifyBasemapUrl("https://t.example/STYLE.JSON"), "style")
})

test("returns null for a URL with no placeholders and no json extension", () => {
  assert.equal(classifyBasemapUrl("https://tiles.example.com/basemap"), null)
})

test("returns null for an XYZ URL missing the x and y placeholders", () => {
  assert.equal(classifyBasemapUrl("https://tiles.example/{z}.png"), null)
})

test("returns null for empty, whitespace, or non-string input", () => {
  assert.equal(classifyBasemapUrl(""), null)
  assert.equal(classifyBasemapUrl("   "), null)
  assert.equal(classifyBasemapUrl(null), null)
  assert.equal(classifyBasemapUrl(undefined), null)
})

test("trims surrounding whitespace before classifying", () => {
  assert.equal(
    classifyBasemapUrl("  https://t.example/{z}/{x}/{y}.png  "),
    "raster",
  )
})

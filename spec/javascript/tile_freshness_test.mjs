import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/tile_freshness.js",
    import.meta.url,
  ),
  "utf8",
)
let loads = 0
const loadPage = () => {
  loads += 1
  return import(
    `data:text/javascript;base64,${Buffer.from(source).toString("base64")}#${loads}`
  )
}

const tileUrl = (path) => new URL(path, "http://dawarich.test")

test("tile URLs stay untouched until their tiles are refreshed", async () => {
  const { withTileVersion } = await loadPage()

  const url = withTileVersion(tileUrl("/api/v1/tiles/points/1/2/3.mvt?u=abc"))

  assert.equal(url.searchParams.get("_"), null)
  assert.equal(url.searchParams.get("u"), "abc")
})

test("a refresh gives only that tile path a new version", async () => {
  const { bumpTileVersion, withTileVersion } = await loadPage()

  bumpTileVersion("/api/v1/tiles/points/")
  const first = withTileVersion(tileUrl("/api/v1/tiles/points/1/2/3.mvt"))
  const tracks = withTileVersion(tileUrl("/api/v1/tiles/tracks/1/2/3.mvt"))
  bumpTileVersion("/api/v1/tiles/points/")
  const second = withTileVersion(tileUrl("/api/v1/tiles/points/1/2/3.mvt"))

  assert.ok(first.searchParams.get("_"))
  assert.notEqual(second.searchParams.get("_"), first.searchParams.get("_"))
  assert.equal(tracks.searchParams.get("_"), null)
})

test("a refresh never reuses a tile URL from an earlier page load", async () => {
  const earlier = await loadPage()
  const later = await loadPage()
  earlier.bumpTileVersion("/api/v1/tiles/tracks/")
  later.bumpTileVersion("/api/v1/tiles/tracks/")

  const path = "/api/v1/tiles/tracks/1/2/3.mvt"
  assert.notEqual(
    later.withTileVersion(tileUrl(path)).toString(),
    earlier.withTileVersion(tileUrl(path)).toString(),
  )
})

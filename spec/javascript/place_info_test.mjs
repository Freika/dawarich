import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (file) =>
  readFile(new URL(`../../app/javascript/${file}`, import.meta.url), "utf8")
const strip = (source) => source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const load = async () => {
  const source = strip(await read("maps_maplibre/components/place_info.js"))
  return import(
    `data:text/javascript;base64,${Buffer.from(`const translate = (key) => key; ${source}`).toString("base64")}`
  )
}

test("place info carries both API tags through GeoJSON and renders escaped coloured chips", async () => {
  const { buildPlaceInfo } = await load()
  const source = strip(await read("controllers/maps/maplibre/data_loader.js"))
  const { DataLoader } = await import(
    `data:text/javascript;base64,${Buffer.from(`const createCircle = () => []; ${source}`).toString("base64")}`
  )
  const tags = [
    { id: 1, name: 'Home <&"', icon: "🏠", color: "#123456" },
    {
      id: 2,
      name: "Work <script>",
      icon: "💼",
      color: '#fff;" onmouseover="bad',
    },
  ]
  const features = new DataLoader().placesToGeoJSON([
    {
      id: 42,
      latitude: 52.52,
      longitude: 13.405,
      tags,
      note: '<img src=x onerror="bad">',
    },
  ]).features
  for (const feature of features) {
    assert.deepEqual(JSON.parse(feature.properties.tags), tags)
    const { content } = buildPlaceInfo(feature.properties)
    assert.equal((content.match(/data-testid="place-tag"/g) || []).length, 2)
    assert.ok(content.includes("🏠 #Home &lt;&amp;&quot;"))
    assert.ok(content.includes("💼 #Work &lt;script&gt;"))
    assert.ok(content.includes("color: #123456"))
    assert.ok(content.includes("&lt;img"))
    assert.ok(!content.includes("onmouseover"))
  }
})

test("place info offers Open Edit and Delete with place routing and safe labels", async () => {
  const { buildPlaceInfo } = await load()
  const info = buildPlaceInfo({ id: 42, name: "Cafe & Tea", tags: "[]" })
  assert.equal(info.title, "Cafe & Tea")
  assert.deepEqual(info.actions, [
    {
      type: "button",
      handler: "openPlace",
      id: 42,
      entityType: "place",
      label: "places.open",
    },
    {
      type: "button",
      handler: "openPlace",
      id: 42,
      entityType: "place",
      label: "messages.edit",
    },
    {
      type: "button",
      handler: "openPlace",
      id: 42,
      entityType: "place",
      label: "messages.delete",
    },
  ])
  assert.deepEqual(buildPlaceInfo({ tags: "invalid" }).actions, [])
  assert.ok(
    !buildPlaceInfo({ tags: "null" }).content.includes(
      'data-testid="place-tag"',
    ),
  )
})

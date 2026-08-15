import assert from "node:assert/strict"
import { readdir, readFile } from "node:fs/promises"
import test from "node:test"

const viewsDir = new URL("../../app/views/map/maplibre/", import.meta.url)
const controllerUrl = new URL(
  "../../app/javascript/controllers/maps/maplibre_controller.js",
  import.meta.url,
)

async function boundTargetNames() {
  const names = new Set()
  for (const entry of await readdir(viewsDir)) {
    if (!entry.endsWith(".erb")) continue
    const source = await readFile(new URL(entry, viewsDir), "utf8")
    for (const match of source.matchAll(
      /data-maps--maplibre-target="([^"]+)"/g,
    )) {
      for (const name of match[1].split(/\s+/)) {
        if (name) names.add(name)
      }
    }
  }
  return names
}

async function declaredTargetNames() {
  const source = await readFile(controllerUrl, "utf8")
  const block = source.match(/static targets = \[([\s\S]*?)\]/)
  assert.ok(block, "maplibre_controller.js declares no static targets block")
  return new Set([...block[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]))
}

test("every target bound in the Map v2 views is declared by the controller", async () => {
  const bound = await boundTargetNames()
  const declared = await declaredTargetNames()
  const missing = [...bound].filter((name) => !declared.has(name))
  assert.deepEqual(
    missing,
    [],
    `Map v2 views bind Stimulus targets the maps--maplibre controller never declares, so their state silently stops syncing: ${missing.join(", ")}`,
  )
})

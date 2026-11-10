import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// The private Playwright suite calls these from page.evaluate. Nothing in the
// app calls them, so a dead-code sweep would otherwise delete them.
const CALLED_BY_E2E = {
  "maps_maplibre/managers/replay_manager.js": ["getCurrentDayPointCount"],
}

test("methods the private E2E suite calls still exist", async () => {
  const missing = []
  for (const [path, names] of Object.entries(CALLED_BY_E2E)) {
    const source = await readFile(
      new URL(`../../app/javascript/${path}`, import.meta.url),
      "utf8",
    )
    for (const name of names) {
      if (!new RegExp(`^  (async )?${name}\\(`, "m").test(source))
        missing.push(`${path}#${name}`)
    }
  }
  assert.deepEqual(missing, [])
})

// Methods the suite calls on the maps--maplibre controller. Several forward
// through FORWARDED_ACTIONS, so check the prototype rather than the source.
const MAP_CONTROLLER_METHODS = [
  "openVisitModal",
  "monthChanged",
  "toggleReplay",
  "loadTimelineFeed",
  "togglePlaces",
  "togglePointsEditing",
  "startSelectArea",
  "_getLoadedPoints",
]

test("map controller methods the private E2E suite calls still exist", async () => {
  const source = (
    await readFile(
      new URL(
        "../../app/javascript/controllers/maps/maplibre_controller.js",
        import.meta.url,
      ),
      "utf8",
    )
  ).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
  const { default: MapController } = await import(
    `data:text/javascript;base64,${Buffer.from(`class Controller {}\n${source}`).toString("base64")}`
  )
  const missing = MAP_CONTROLLER_METHODS.filter(
    (name) => typeof MapController.prototype[name] !== "function",
  )
  assert.deepEqual(missing, [])
})

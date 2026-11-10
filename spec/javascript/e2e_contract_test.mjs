import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// The private Playwright suite calls these from page.evaluate. Nothing in the
// app calls them, so a dead-code sweep would otherwise delete them.
const CALLED_BY_E2E = {
  "controllers/maps/maplibre_controller.js": ["openVisitModal"],
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

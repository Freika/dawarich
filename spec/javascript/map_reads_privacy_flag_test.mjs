import assert from "node:assert/strict"
import { readdir, readFile } from "node:fs/promises"
import { join } from "node:path"
import test from "node:test"

const root = new URL("../../", import.meta.url).pathname
const dirs = ["app/javascript/maps_maplibre", "app/javascript/controllers"]
const MAP_READ =
  /\/(points|tracks|visits|places|photos|timeline|locations|maps\/(hexagons|statistics))(\/[^/?`"']*)*\?/
const FLAG = /mask_privacy_zones|maskPrivacyZones/
const UNMASKED = new Set([
  "app/javascript/maps_maplibre/services/api_client.js#fetchPointsInArea",
  "app/javascript/maps_maplibre/services/api_client.js#fetchVisitsInArea",
  "app/javascript/maps_maplibre/components/visit_place_search.js#fetchResults",
  "app/javascript/controllers/public_stat_map_controller.js#loadStaticHexagons",
  "app/javascript/maps_maplibre/services/location_search_service.js#fetchSuggestions",
  "app/javascript/controllers/maps/maplibre_controller.js#loadFamilyHistory",
])

async function jsFiles(dir) {
  const entries = await readdir(join(root, dir), { withFileTypes: true })
  const nested = await Promise.all(
    entries.map((e) =>
      e.isDirectory()
        ? jsFiles(join(dir, e.name))
        : e.name.endsWith(".js")
          ? [join(dir, e.name)]
          : [],
    ),
  )
  return nested.flat()
}

function enclosingFunction(lines, index) {
  for (let i = index; i >= 0; i--) {
    const match = lines[i].match(/^\s{2}(?:static\s+)?(?:async\s+)?(\w+)\s*\(/)
    if (match && !["if", "for", "while", "switch"].includes(match[1])) {
      return { name: match[1], start: i }
    }
  }
  return { name: "?", start: 0 }
}

test("every map read fetch outside the allow-list carries the privacy flag", async () => {
  const offenders = []
  for (const file of (await Promise.all(dirs.map(jsFiles))).flat()) {
    const lines = (await readFile(join(root, file), "utf8")).split("\n")
    lines.forEach((line, index) => {
      if (!/fetch\(/.test(line)) return
      const call = lines.slice(index, index + 3).join(" ")
      const fn = enclosingFunction(lines, index)
      const body = lines.slice(fn.start, index + 3).join("\n")
      const url = call.match(/fetch\(\s*([^,)]+)/)?.[1] ?? ""
      const readsMap =
        MAP_READ.test(call) ||
        (/\$\{params\}|\?\$\{/.test(url) && MAP_READ.test(body))
      if (!readsMap || /method:\s*"(POST|PATCH|PUT|DELETE)"/.test(body)) return
      if (UNMASKED.has(`${file}#${fn.name}`) || FLAG.test(body)) return
      offenders.push(`${file}:${index + 1} (${fn.name})`)
    })
  }
  assert.deepEqual(offenders, [])
})

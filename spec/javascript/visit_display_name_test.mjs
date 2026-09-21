import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"
import vm from "node:vm"

const currentDir = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(currentDir, "../..")

async function loadClass(relativePath, className, context) {
  const source = (await readFile(path.join(repoRoot, relativePath), "utf8"))
    .replace(/^import[\s\S]*?from "[^"]+";?\n/gm, "")
    .replace(`export class ${className}`, `class ${className}`)
    .concat(`\nglobalThis.${className} = ${className}\n`)
  vm.createContext(context)
  vm.runInContext(source, context)
  return context[className]
}

const unplacedSuggestion = {
  id: 1,
  name: null,
  display_name: "Main Street 5",
  place: null,
  status: "suggested",
  started_at: "2026-09-01T10:00:00Z",
  ended_at: "2026-09-01T11:00:00Z",
  duration: 60,
}

const VisitCard = await loadClass(
  "app/javascript/maps_maplibre/components/visit_card.js",
  "VisitCard",
  {
    document: { documentElement: { lang: "en" } },
    translate: (key) => key,
    escapeHtml: (value) => (value == null ? "" : String(value)),
  },
)
const card = VisitCard.create(unplacedSuggestion)
assert.match(card, /Main Street 5/)
assert.doesNotMatch(card, /visits\.unnamed/)

const FilterManager = await loadClass(
  "app/javascript/controllers/maps/maplibre/filter_manager.js",
  "FilterManager",
  {},
)
let shown = null
const filterManager = new FilterManager({
  visitsToGeoJSON: (visits) => visits,
})
filterManager.setAllVisits([unplacedSuggestion])
filterManager.filterAndUpdateVisits("main street", "all", {
  update: (visits) => {
    shown = visits
  },
})
assert.deepEqual(
  shown.map((visit) => visit.id),
  [1],
)

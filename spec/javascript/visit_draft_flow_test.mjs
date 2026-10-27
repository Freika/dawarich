import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const helper = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/visit_draft.js",
    import.meta.url,
  ),
  "utf8",
)
const flow = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/visit_draft_flow.js",
    import.meta.url,
  ),
  "utf8",
)
const warnings = []
const context = vm.createContext({
  translate: (key) => key,
  Toast: { warning: (text) => warnings.push(text) },
  URLSearchParams,
})
vm.runInContext(
  (helper + flow.replace(/^import .*\n/gm, "")).replace(/export /g, "") +
    "\nglobalThis.exports = { selectionVisitDraft, prefillVisitFromClick }",
  context,
)
const { selectionVisitDraft, prefillVisitFromClick } = context.exports
const points = [
  { latitude: 52, longitude: 13, timestamp: 1700000000 },
  { latitude: 52, longitude: 13, timestamp: 1700003600 },
]

test("selection draft uses retained points and the server-provided user threshold", () => {
  const c = {
    areaSelectionManager: { selectedPoints: points },
    element: {
      querySelector: () => ({ dataset: { visitMergeThresholdMinutes: "60" } }),
    },
  }
  assert.equal(selectionVisitDraft(c).multipleStays, false)
  c.element.querySelector = () => null
  assert.equal(selectionVisitDraft(c).multipleStays, true)
  c.areaSelectionManager.selectedPoints = []
  assert.equal(selectionVisitDraft(c), null)
})

test("click history fetch uses a 100 metre box and the map date range", async () => {
  let request
  let applied
  const c = {
    startDateValue: "start",
    endDateValue: "end",
    api: {
      fetchPointsInArea: async (params) => {
        request = params
        return { points }
      },
    },
  }
  await prefillVisitFromClick(
    c,
    {
      draftForm: {
        applyHistory: (draft) => {
          applied = draft
          return true
        },
      },
    },
    52,
    13,
  )
  assert.equal(request.start_at, "start")
  assert.equal(request.end_at, "end")
  assert.ok(Math.abs(request.max_latitude - 52 - 0.00089932) < 0.000001)
  assert.ok(Math.abs(request.max_longitude - 13 - 0.00146074) < 0.000001)
  assert.equal(applied.startedAt, new Date(1700003600000).toISOString())
  assert.equal(warnings.at(-1), "visits.multiple_stays")
})

test("click history with no points retains the open form defaults", async () => {
  let applied
  await prefillVisitFromClick(
    { api: { fetchPointsInArea: async () => ({ points: [] }) } },
    {
      draftForm: {
        applyHistory: (draft) => {
          applied = draft
        },
      },
    },
    52,
    13,
  )
  assert.equal(applied, null)
})

import assert from "node:assert/strict"
import { test } from "node:test"
import { createSelectionActions } from "../../app-phoenix/assets/js/map/selection/actions.js"
import { createAreaSelection } from "../../app-phoenix/assets/js/map/selection/state.js"
import { miniDocument } from "../../app-phoenix/test/client/support/mini_dom.mjs"

const bounds = { minLng: 13.3, maxLng: 13.5, minLat: 52.4, maxLat: 52.6 }
const translate = (key, vars = {}) => `${key}${JSON.stringify(vars)}`

function selectionDom() {
  const document = miniDocument()
  const container = document.createElement("div")
  container.className = "hidden mt-4 space-y-2"
  const button = (attribute, text, className) => {
    const element = document.createElement("button")
    element.className = className
    element.setAttribute(attribute, "")
    const label = document.createElement("span")
    label.setAttribute(`${attribute}-text`, "")
    label.textContent = text
    element.append(label)
    return element
  }
  const visits = document.createElement("div")
  visits.className = "hidden mt-4 max-h-full overflow-y-auto"
  visits.setAttribute("data-map-selected-visits", "")
  container.append(
    button("data-map-delete-points", "Delete Selected Points", "btn"),
    button("data-map-delete-anomalies", "Delete Anomaly Points", "hidden btn"),
    visits,
  )
  return { document, container, visits }
}

function mapMock() {
  const handlers = new Map()
  return {
    handlers,
    dragPan: { enable() {}, disable() {} },
    boxZoom: { enable() {}, disable() {} },
    on: (type, fn) => handlers.set(type, fn),
    off: (type) => handlers.delete(type),
    getCanvas: () => ({ style: {} }),
    unproject: ([x, y]) => ({ lng: x, lat: y }),
  }
}

function selectionWith(points, visits, replies) {
  const pushed = []
  let loads = 0
  const map = mapMock()
  const selection = createAreaSelection({
    map,
    query: {
      select: async () => {
        loads++
        return { points, visits: loads === 1 ? visits : visits.slice(1) }
      },
    },
    getRange: () => ({}),
    pushEvent: (event, payload, reply) => {
      pushed.push([event, payload])
      reply(replies.shift())
    },
    onChange: () => {},
  })
  return { selection, map, pushed, loads: () => loads }
}

async function loaded(selection, map) {
  selection.start()
  map.handlers.get("mousedown")({
    point: { x: bounds.minLng, y: bounds.minLat },
  })
  map.handlers.get("mouseup")({ point: { x: bounds.maxLng, y: bounds.maxLat } })
  await selection.ready
}

const visitRows = [
  {
    id: 4,
    name: "Cafe",
    status: "suggested",
    started_at: "2026-10-16T08:00:00Z",
    ended_at: "2026-10-16T09:00:00Z",
    duration: 60,
  },
  {
    id: 5,
    name: "Gym",
    status: "suggested",
    started_at: "2026-10-16T10:00:00Z",
    ended_at: "2026-10-16T10:30:00Z",
    duration: 30,
  },
]

test("selected visits render Rails cards and an inline bulk merge for two checked", async () => {
  const ctx = selectionWith([{ id: 1 }], visitRows, [{ ok: true }])
  await loaded(ctx.selection, ctx.map)
  const { document, container, visits } = selectionDom()
  const actions = createSelectionActions({
    container,
    document,
    translate,
    selection: ctx.selection,
    confirm: () => true,
  })

  assert.equal(
    container.querySelector("[data-map-delete-points-text]").textContent,
    'selection.delete_points{"count":1}',
  )
  assert.equal(visits.classList.contains("hidden"), false)
  assert.equal(visits.querySelectorAll(".visit-card").length, 2)
  assert.equal(visits.querySelector("[data-bulk-merge]"), null)
  for (const id of ["4", "5"]) {
    const box = visits.querySelector(`[data-visit-select="${id}"]`)
    box.checked = true
    box.dispatch("change")
  }
  const merge = visits.querySelector("[data-bulk-merge]")
  assert.ok(merge)
  await merge.dispatch("click")
  await new Promise((resolve) => setImmediate(resolve))
  assert.deepEqual(ctx.pushed, [
    ["visits:bulk", { action: "merge", ids: ["4", "5"] }],
  ])
  assert.equal(ctx.loads(), 2)
  assert.equal(visits.querySelector('[data-visit-select="4"]'), null)
  assert.ok(visits.querySelector('[data-visit-select="5"]'))
  assert.equal(visits.querySelector("[data-bulk-merge]"), null)

  actions.destroy()
  assert.deepEqual(visits.children, [])
})

test("visit refusal keeps the selection and shows the error", async () => {
  const notices = []
  const ctx = selectionWith([], visitRows, [{ error: "missing" }])
  await loaded(ctx.selection, ctx.map)
  const { document, container } = selectionDom()
  createSelectionActions({
    container,
    document,
    translate,
    selection: ctx.selection,
    notify: (...args) => notices.push(args),
    confirm: () => true,
  })

  container.querySelector('[data-visit-delete="4"]').dispatch("click")
  await new Promise((resolve) => setImmediate(resolve))
  assert.deepEqual(ctx.pushed, [
    ["visits:bulk", { action: "delete", ids: ["4"] }],
  ])
  assert.equal(ctx.loads(), 1)
  assert.deepEqual(
    ctx.selection.state.visits.map((visit) => visit.id),
    [4, 5],
  )
  assert.equal(container.querySelector('[role="alert"]'), null)
  assert.equal(notices[0][0], "error")
  assert.equal(notices[0][1], "messages.failed_to_delete_visit")
})

test("anomaly delete shows its Rails button and sends only anomaly ids after confirmation", async () => {
  const points = [{ id: 1 }, { id: 2, anomaly: true }, { id: 3, anomaly: true }]
  const ctx = selectionWith(points, [], [{ ok: true, count: 2 }])
  await loaded(ctx.selection, ctx.map)
  const { document, container } = selectionDom()
  let asked = 0
  createSelectionActions({
    container,
    document,
    translate,
    selection: ctx.selection,
    confirm: () => ++asked > 1,
  })

  const button = container.querySelector("[data-map-delete-anomalies]")
  assert.equal(button.classList.contains("hidden"), false)
  button.dispatch("click")
  assert.deepEqual(ctx.pushed, [])
  button.dispatch("click")
  await new Promise((resolve) => setImmediate(resolve))
  assert.deepEqual(ctx.pushed, [["points:bulk_delete", { point_ids: [2, 3] }]])
  assert.deepEqual(
    ctx.selection.state.points.map((point) => point.id),
    [1],
  )
})

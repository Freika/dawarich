import assert from "node:assert/strict"
import { test } from "node:test"
import { createSelectionActions } from "../../app-phoenix/assets/js/map/selection/actions.js"
import { createAreaSelection } from "../../app-phoenix/assets/js/map/selection/state.js"

const bounds = { minLng: 13.3, maxLng: 13.5, minLat: 52.4, maxLat: 52.6 }

function element(tag) {
  const listeners = new Map()
  const node = {
    tag,
    children: [],
    textContent: "",
    attributes: {},
    checked: false,
    disabled: false,
    addEventListener: (type, fn) => listeners.set(type, fn),
    setAttribute(name, value) {
      node.attributes[name] = value
    },
    append(...children) {
      node.children.push(...children)
    },
    replaceChildren(...children) {
      node.children = children
    },
    listeners,
  }
  return node
}

const all = (node) => [node, ...node.children.flatMap(all)]
const find = (root, name, value) =>
  all(root).find((node) => node.attributes[name] === value)
const translate = (key, vars = {}) => `${key}${JSON.stringify(vars)}`

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
  const changes = []
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
    onChange: () => changes.push(loads),
  })
  return { selection, map, pushed, changes, loads: () => loads }
}

async function loaded(selection, map) {
  selection.start()
  map.handlers.get("mousedown")({
    point: { x: bounds.minLng, y: bounds.minLat },
  })
  map.handlers.get("mouseup")({ point: { x: bounds.maxLng, y: bounds.maxLat } })
  await selection.ready
}

test("selection actions confirm or merge checked visits and refresh the selection", async () => {
  const visits = [
    { id: 4, name: "Cafe", status: "suggested" },
    { id: 5, name: "Gym", status: "suggested" },
  ]
  const ctx = selectionWith([{ id: 1 }], visits, [{ ok: true }])
  await loaded(ctx.selection, ctx.map)
  const container = element("section")
  const actions = createSelectionActions({
    container,
    document: { createElement: element },
    translate,
    selection: ctx.selection,
    confirm: () => true,
  })

  assert.equal(find(container, "data-bulk", "merge"), undefined)
  for (const id of ["4", "5"]) {
    const box = find(container, "data-visit-select", id)
    box.checked = true
    box.listeners.get("change")()
  }
  await find(container, "data-bulk", "merge").listeners.get("click")()
  assert.deepEqual(ctx.pushed, [
    ["visits:bulk", { action: "merge", ids: ["4", "5"] }],
  ])
  assert.equal(ctx.loads(), 2)
  assert.equal(find(container, "data-visit-select", "4"), undefined)
  assert.ok(find(container, "data-visit-select", "5"))
  assert.equal(find(container, "data-bulk", "merge"), undefined)
  assert.ok(ctx.changes.length >= 2)

  actions.destroy()
  assert.deepEqual(container.children, [])
})

test("visit bulk refusal keeps the selection and shows the error", async () => {
  const visits = [
    { id: 4, name: "Cafe", status: "suggested" },
    { id: 5, name: "Gym", status: "suggested" },
  ]
  const ctx = selectionWith([], visits, [{ error: "missing" }])
  await loaded(ctx.selection, ctx.map)
  const container = element("section")
  createSelectionActions({
    container,
    document: { createElement: element },
    translate,
    selection: ctx.selection,
    confirm: () => true,
  })

  await find(container, "data-visit-delete", "4").listeners.get("click")()
  assert.deepEqual(ctx.pushed, [
    ["visits:bulk", { action: "delete", ids: ["4"] }],
  ])
  assert.equal(ctx.loads(), 1)
  assert.deepEqual(
    ctx.selection.state.visits.map((visit) => visit.id),
    [4, 5],
  )
  assert.ok(find(container, "role", "alert"))
})

test("anomaly delete sends only anomaly point ids after confirmation", async () => {
  const points = [{ id: 1 }, { id: 2, anomaly: true }, { id: 3, anomaly: true }]
  const ctx = selectionWith(points, [], [{ ok: true, count: 2 }])
  await loaded(ctx.selection, ctx.map)
  const container = element("section")
  let asked = 0
  createSelectionActions({
    container,
    document: { createElement: element },
    translate,
    selection: ctx.selection,
    confirm: () => ++asked > 1,
  })

  await find(container, "data-points", "anomalies").listeners.get("click")()
  assert.deepEqual(ctx.pushed, [])
  await find(container, "data-points", "anomalies").listeners.get("click")()
  assert.deepEqual(ctx.pushed, [["points:bulk_delete", { point_ids: [2, 3] }]])
  assert.deepEqual(
    ctx.selection.state.points.map((point) => point.id),
    [1],
  )
})

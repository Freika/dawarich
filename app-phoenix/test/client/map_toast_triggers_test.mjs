import assert from "node:assert/strict"
import test from "node:test"
import { createAreaSelection } from "../../assets/js/map/selection/state.js"
import { createMapRetry } from "../../assets/js/map/ui/retry.js"
import { miniDocument } from "./support/mini_dom.mjs"
import { Toast } from "../../assets/js/map/ui/toast.js"

test("selection reports instructions loading results failures and cancellation through Toast", async () => {
  const notices = []
  const events = new Map()
  let rows = { points: [{ id: 1 }], visits: [] }, failure = false
  const map = { dragPan: { enable() {}, disable() {} }, boxZoom: { enable() {}, disable() {} }, unproject: ([lng, lat]) => ({ lng, lat }), on(name, fn) { events.set(name, fn) }, off() {}, getCanvas: () => ({ style: {} }) }
  const selection = createAreaSelection({ map, query: { select: async () => { if (failure) throw new Error(); return rows } }, getRange: () => ({}), pushEvent() {}, notify: (...args) => notices.push(args), translate: key => key })
  selection.start()
  assert.deepEqual(notices.shift(), ["info", "messages.draw_a_rectangle_on_the_map_to_select_points"])
  selection.cancel()
  assert.deepEqual(notices.shift(), ["info", "messages.selection_cancelled"])
  selection.start()
  const draw = async () => {
    events.get("mousedown")({ point: { x: 1, y: 2 } })
    events.get("mouseup")({ point: { x: 3, y: 4 } })
    await selection.ready
  }
  notices.length = 0
  await draw()
  assert.deepEqual(notices, [["info", "messages.fetching_data_in_selected_area"], ["success", "selection.selected", { items: "selection.points" }]])
  selection.cancel(false)
  rows = { points: [], visits: [] }
  selection.start()
  notices.length = 0
  await draw()
  assert.equal(notices[1][1], "messages.no_data_found_in_selected_area")
  assert.equal(selection.state.active, false)
  selection.start()
  notices.length = 0
  failure = true
  await draw()
  assert.equal(notices[1][0], "error")
  assert.equal(notices[1][1], "messages.failed_to_fetch_data_in_selected_area")
})

test("data failure retry uses Rails persistent Toast and its retry action", t => {
  t.mock.timers.enable({ apis: ["setTimeout"] })
  const document = miniDocument(), create = document.createElement
  document.createElement = tag => { const node = create(tag); Object.defineProperty(node, "parentNode", { get: () => node.parent }); return node }
  document.body = document.createElement("body")
  document.head = document.createElement("head")
  document.getElementById = () => null
  globalThis.document = document
  Toast.container = null
  let runs = 0
  const root = document.createElement("main")
  root.ownerDocument = document
  const retry = createMapRetry({ root, translate: key => key, run: () => runs++ })
  retry.fail("point_tiles_failed")
  const toast = document.body.querySelector(".toast-error")
  assert.ok(toast)
  assert.equal(toast.children[0].textContent, "messages.failed_to_load_map_tiles")
  t.mock.timers.tick(10000)
  assert.equal(toast.classList.contains("removing"), false)
  toast.children[1].click()
  assert.equal(runs, 1)
  retry.destroy()
})

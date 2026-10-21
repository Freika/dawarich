import assert from "node:assert/strict"
import { test } from "node:test"
import { createMapRetry } from "../../app-phoenix/assets/js/map/ui/retry.js"
import { Toast } from "../../app-phoenix/assets/js/map/ui/toast.js"
import { toastDocument } from "../../app-phoenix/test/client/support/toast_dom.mjs"

function fixture(t) {
  t.mock.timers.enable({ apis: ["setTimeout"] })
  const previousDocument = globalThis.document
  const previousContainer = Toast.container
  const document = toastDocument()
  globalThis.document = document
  Toast.container = null
  t.after(() => {
    globalThis.document = previousDocument
    Toast.container = previousContainer
  })
  const root = document.createElement("main")
  root.ownerDocument = document
  document.body.appendChild(root)
  return { root, document, toasts: () => document.body.querySelectorAll(".toast") }
}

test("native map failures expose one bounded retry and perform the failed read again", async t => {
  const { root, document, toasts } = fixture(t)
  const calls = []
  const retry = createMapRetry({ root, translate: key => key, run: async code => calls.push(code) })
  t.after(() => retry.destroy())
  retry.fail("point_tiles_failed")
  retry.fail("point_tiles_failed")
  assert.equal(toasts().length, 1)
  const toast = toasts()[0]
  assert.equal(toast.className, "toast toast-error")
  assert.equal(toast.parentNode, Toast.container)
  assert.equal(Toast.container.parentNode, document.body)
  assert.equal(toast.children[0].textContent, "messages.failed_to_load_map_tiles")
  assert.match(toast.children[0].style.cssText, /overflow-wrap: anywhere/)
  assert.match(Toast.container.style.cssText, /pointer-events: none/)
  assert.match(document.head.textContent, /\.toast-container > \.toast button\s*\{\s*pointer-events: auto/)
  const buttons = toast.querySelectorAll("button")
  assert.equal(buttons.length, 1)
  assert.equal(buttons[0].textContent, "messages.retry")
  t.mock.timers.tick(20000)
  assert.equal(toast.classList.contains("removing"), false)
  buttons[0].click()
  buttons[0].click()
  await Promise.resolve()
  assert.deepEqual(calls, ["point_tiles_failed"])
  assert.equal(toast.classList.contains("removing"), true)
  t.mock.timers.tick(300)
  assert.equal(toasts().length, 0)
})

test("native retry retains a failed read and retires listeners on teardown", async t => {
  const { root, toasts } = fixture(t)
  const calls = []
  const retry = createMapRetry({ root, translate: key => key, run: async code => {
    calls.push(code)
    if (calls.length === 1) throw new Error("unavailable")
    return "failed"
  } })
  t.after(() => retry.destroy())
  retry.fail("scratch_tiles_failed")
  const first = toasts()[0]
  assert.equal(first.children[0].textContent, "messages.failed_to_load_visited_countries")
  first.querySelector("button").click()
  await Promise.resolve()
  t.mock.timers.tick(300)
  assert.equal(toasts().length, 1)
  const second = toasts()[0]
  assert.notEqual(second, first)
  second.querySelector("button").click()
  await Promise.resolve()
  t.mock.timers.tick(300)
  assert.equal(toasts().length, 1)
  const retained = toasts()[0]
  t.mock.timers.tick(20000)
  assert.equal(retained.classList.contains("removing"), false)
  assert.deepEqual(calls, ["scratch_tiles_failed", "scratch_tiles_failed"])
  retry.destroy()
  for (const toast of [first, second, retained]) toast.querySelector("button").click()
  retry.fail("point_tiles_failed")
  await Promise.resolve()
  assert.equal(calls.length, 2)
  assert.equal(retained.classList.contains("removing"), true)
  t.mock.timers.tick(300)
  assert.equal(toasts().length, 0)
})

test("visited-country metadata failures retain a persistent action that reruns the failed read", async t => {
  const { root, toasts } = fixture(t)
  const calls = []
  const retry = createMapRetry({ root, translate: key => key, run: async code => calls.push(code) })
  t.after(() => retry.destroy())
  retry.fail("map_refresh_failed")
  retry.fail("map_refresh_failed")
  assert.equal(toasts().length, 1)
  const toast = toasts()[0]
  assert.equal(toast.children[0].textContent, "messages.failed_to_load_location_data_please_try_again")
  const button = toast.querySelector("button")
  assert.ok(button)
  t.mock.timers.tick(20000)
  assert.equal(toast.classList.contains("removing"), false)
  button.click()
  await Promise.resolve()
  assert.deepEqual(calls, ["map_refresh_failed"])
  t.mock.timers.tick(300)
  assert.equal(toasts().length, 0)
})

test("native retry remains inside map hook ownership during shell patches", async t => {
  const { document, toasts } = fixture(t)
  const { fixture: hostFixture } = await import("./support/native_m6_host_fixture.mjs")
  const f = hostFixture()
  f.element.ownerDocument = document
  f.root.ownerDocument = document
  await f.owner.mount()
  try {
    f.map.emit("error", { sourceId: "points-mvt-source", error: new Error("tile unavailable") })
    f.root.replaceChildren()
    await new Promise(setImmediate)
    assert.equal(toasts().length, 1)
    const toast = toasts()[0]
    assert.equal(toast.className, "toast toast-error")
    assert.equal(toast.parentNode.parentNode, document.body)
    assert.equal(toast.querySelectorAll("button").length, 1)
    let retries = 0
    f.map.refreshTiles = () => retries++
    f.owner.destroy()
    assert.equal(toast.classList.contains("removing"), true)
    toast.querySelector("button").click()
    f.map.emit("error", { sourceId: "points-mvt-source", error: new Error("late failure") })
    await new Promise(setImmediate)
    assert.equal(retries, 0)
    assert.equal(f.listeners.get("error").size, 0)
    assert.equal(toast.classList.contains("removing"), true)
    t.mock.timers.tick(300)
    assert.equal(toasts().length, 0)
  } finally { f.owner.destroy() }
})

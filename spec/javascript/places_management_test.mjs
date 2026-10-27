import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const root = new URL("../../", import.meta.url)

test("create-place deep links start creation once and preserve other URL parameters", async () => {
  const source = await readFile(
    new URL(
      "app/javascript/controllers/maps/maplibre/create_place_link.js",
      root,
    ),
    "utf8",
  )
  const { consumeCreatePlaceLink } = await import(
    `data:text/javascript,${encodeURIComponent(source)}`
  )
  let calls = 0
  const location = {
    href: "http://localhost/map/v2?create_place=1&panel=timeline#map",
  }
  const state = { retained: true }
  const history = {
    state,
    replaceState(nextState, _, url) {
      assert.equal(nextState, state)
      location.href = url
    },
  }
  const manager = {
    startCreatePlace() {
      calls++
    },
  }
  consumeCreatePlaceLink(manager, location, history)
  consumeCreatePlaceLink(manager, location, history)
  assert.equal(calls, 1)
  assert.equal(location.href, "http://localhost/map/v2?panel=timeline#map")
})

test("bulk selection synchronizes page checkboxes, forms and aggregated delete consequences", async () => {
  const source = (
    await readFile(
      new URL(
        "app/javascript/controllers/places_selection_controller.js",
        root,
      ),
      "utf8",
    )
  )
    .replace(/^import .*$/gm, "")
    .replace("export default class", "globalThis.Selection = class")
  const context = {
    Controller: class {},
    window: { confirm: () => false },
    document: { createElement: () => ({ dataset: {} }) },
  }
  vm.createContext(context)
  vm.runInContext(source, context)
  const controller = new context.Selection()
  controller.rowTargets = [
    {
      checked: true,
      value: "1",
      dataset: { visits: "3", geofence: "1", privacy: "1" },
    },
    {
      checked: false,
      value: "2",
      dataset: { visits: "8", geofence: "0", privacy: "0" },
    },
  ]
  controller.allTarget = { checked: false }
  controller.countTarget = {}
  controller.buttonTargets = [{ disabled: true }]
  const fields = []
  controller.formTargets = [
    { querySelectorAll: () => [], append: (field) => fields.push(field) },
  ]
  controller.survivorTarget = {
    options: [
      { value: "1", disabled: false },
      { value: "2", disabled: false },
    ],
    value: "1",
  }
  controller.hasSurvivorTarget = true
  controller.deleteMessageValue =
    "Delete %{places}; visits %{visits}; geofences %{geofences}; privacy %{privacy}"
  controller.update()
  assert.equal(fields[0].value, "1")
  assert.equal(controller.allTarget.indeterminate, true)
  assert.equal(controller.buttonTargets[0].disabled, false)
  assert.equal(controller.survivorTarget.options[1].disabled, true)
  let message
  let prevented = false
  context.window.confirm = (value) => {
    message = value
    return false
  }
  controller.confirmDelete({
    preventDefault() {
      prevented = true
    },
  })
  assert.equal(message, "Delete 1; visits 3; geofences 1; privacy 1")
  assert.equal(prevented, true)
  controller.toggleAll({ target: { checked: true } })
  assert.equal(
    controller.rowTargets.every((row) => row.checked),
    true,
  )
  assert.equal(controller.countTarget.textContent, 2)
})

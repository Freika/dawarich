import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/duplicate_group_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(
  'import { Controller } from "@hotwired/stimulus"',
  "class Controller {}",
)
const { default: DuplicateGroupController } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

function card() {
  const attributes = new Set()
  return {
    toggleAttribute: (name, on) =>
      on ? attributes.add(name) : attributes.delete(name),
    has: (name) => attributes.has(name),
  }
}

function group(places) {
  const cards = places.map(() => card())
  const input = (value, checked, index) => ({
    value,
    checked,
    closest: () => cards[index],
  })
  const controller = new DuplicateGroupController()
  controller.keepTargets = places.map((p, i) => input(p.id, p.keep, i))
  controller.includeTargets = places.map((p, i) => input(p.id, p.include, i))
  controller.submitTarget = { disabled: false }
  return { controller, cards }
}

test("the kept place is always part of the merge", () => {
  const { controller, cards } = group([
    { id: "1", keep: false, include: true },
    { id: "2", keep: true, include: false },
  ])

  controller.sync()

  assert.equal(controller.includeTargets[1].checked, true)
  assert.ok(cards[1].has("data-keep"))
  assert.equal(controller.submitTarget.disabled, false)
})

test("a skipped place fades and nothing to merge disables the button", () => {
  const { controller, cards } = group([
    { id: "1", keep: true, include: true },
    { id: "2", keep: false, include: false },
  ])

  controller.sync()

  assert.ok(cards[1].has("data-skipped"))
  assert.equal(controller.submitTarget.disabled, true)
})

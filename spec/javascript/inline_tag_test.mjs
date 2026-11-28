import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

async function setup() {
  const source = await readFile(
    new URL(
      "../../app/javascript/controllers/inline_tag_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
  const { default: InlineTagController } = await import(
    `data:text/javascript;base64,${Buffer.from(
      `class Controller {}; ${source.replace(/^import .*\n/gm, "")}`,
    ).toString("base64")}`
  )
  const controller = new InlineTagController()
  let submissions = 0
  controller.formTarget = { requestSubmit: () => submissions++ }
  controller.nameTarget = { value: "Garden", focus() {} }
  controller.iconTarget = { value: "🌿" }
  controller.detailsTarget = { open: true }
  return { controller, submissions: () => submissions }
}

test("inline tag submits its own Turbo form without submitting the place", async () => {
  const { controller, submissions } = await setup()
  controller.create()
  assert.equal(submissions(), 1)
})

test("a successful inline tag clears only the tag inputs and closes its disclosure", async () => {
  const { controller } = await setup()
  controller.complete({
    target: controller.formTarget,
    detail: { success: true },
  })
  assert.equal(controller.nameTarget.value, "")
  assert.equal(controller.iconTarget.value, "")
  assert.equal(controller.detailsTarget.open, false)
})

test("an invalid inline tag keeps its inputs and disclosure open for correction", async () => {
  const { controller } = await setup()
  controller.complete({
    target: controller.formTarget,
    detail: { success: false },
  })
  assert.equal(controller.nameTarget.value, "Garden")
  assert.equal(controller.iconTarget.value, "🌿")
  assert.equal(controller.detailsTarget.open, true)
})

test("saving the place cannot clear an unfinished inline tag", async () => {
  const { controller } = await setup()
  controller.complete({ target: {}, detail: { success: true } })
  assert.equal(controller.nameTarget.value, "Garden")
  assert.equal(controller.detailsTarget.open, true)
})

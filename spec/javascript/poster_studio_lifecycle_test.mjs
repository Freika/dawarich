import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/poster_studio_editor_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const prelude = `
class Controller {}
const translate = (key) => key
`
const moduleUrl = `data:text/javascript;base64,${Buffer.from(`${prelude}\n${source}`).toString("base64")}`
const { default: PosterStudioController } = await import(moduleUrl)

test("poster studio cannot switch to video during a range reload", () => {
  const calls = []
  const controller = new PosterStudioController()
  controller.rangeLoading = true
  controller.provider = { id: "map" }
  controller.close = () => calls.push("close")
  const originalDocument = globalThis.document
  globalThis.document = { dispatchEvent: () => calls.push("dispatch") }

  try {
    controller.switchToVideo()
  } finally {
    globalThis.document = originalDocument
  }

  assert.deepEqual(calls, [])
})

test("poster range reload disables its studio switch", () => {
  const controller = new PosterStudioController()
  controller.hasLoadButtonTarget = false
  controller.hasSwitchButtonTarget = true
  controller.switchButtonTarget = { disabled: false }

  controller.setLoadBusy(true)

  assert.equal(controller.rangeLoading, true)
  assert.equal(controller.switchButtonTarget.disabled, true)
})

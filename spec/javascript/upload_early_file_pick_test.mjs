import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/upload_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import .*\n/gm, "")
const { default: UploadController } = await import(
  `data:text/javascript;base64,${Buffer.from(`class Controller {}\n${source}`).toString("base64")}`
)

function controllerWithFiles(files) {
  const controller = new UploadController()
  const input = new EventTarget()
  input.files = files
  controller.inputTarget = input
  controller.hasFormTarget = false
  controller.hasSubmitTarget = true
  controller.submitTarget = { disabled: false }
  controller.element = { querySelectorAll: () => [] }
  let uploads = 0
  controller.upload = () => {
    uploads++
  }
  return { controller, input, uploads: () => uploads }
}

test("a file picked before the upload controller connects starts one upload", () => {
  const fixture = controllerWithFiles([{ name: "early.gpx" }])
  fixture.controller.connect()
  assert.equal(fixture.uploads(), 1)
  fixture.input.dispatchEvent(new Event("change"))
  assert.equal(fixture.uploads(), 1)
})

test("a file picked after connection starts one upload", () => {
  const fixture = controllerWithFiles([])
  fixture.controller.connect()
  assert.equal(fixture.uploads(), 0)
  fixture.input.files = [{ name: "later.gpx" }]
  fixture.input.dispatchEvent(new Event("change"))
  assert.equal(fixture.uploads(), 1)
})

test("reconnecting with the same selected file does not upload it again", () => {
  const fixture = controllerWithFiles([{ name: "selected.gpx" }])
  fixture.controller.connect()
  fixture.controller.disconnect()
  fixture.controller.connect()
  fixture.input.dispatchEvent(new Event("change"))
  assert.equal(fixture.uploads(), 1)
})

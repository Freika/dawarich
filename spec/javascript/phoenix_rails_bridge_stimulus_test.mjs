import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL("../../app-phoenix/priv/static/js/rails_bridge.js", import.meta.url),
  "utf8",
)
globalThis.window = {}
await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

const island = (owned) => ({
  getControllerForElementAndIdentifier: (element, identifier) =>
    owned.get(element)?.[identifier] ?? null,
})

test("window.Stimulus finds a controller in whichever island owns the element, as Rails' global application does", () => {
  const form = {}
  const map = {}
  const upload = { name: "upload" }
  const shell = { name: "maps" }
  window.StimulusIslands.add(island(new Map([[map, { maps: shell }]])))
  window.StimulusIslands.add(island(new Map([[form, { upload }]])))

  assert.equal(
    window.Stimulus.getControllerForElementAndIdentifier(form, "upload"),
    upload,
  )
  assert.equal(
    window.Stimulus.getControllerForElementAndIdentifier(map, "maps"),
    shell,
  )
  assert.equal(
    window.Stimulus.getControllerForElementAndIdentifier(form, "maps"),
    null,
  )
})

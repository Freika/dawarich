import assert from "node:assert/strict"
import { test } from "node:test"
import { createStyleControls } from "../../app-phoenix/assets/js/map/ui/style_controls.js"

const deferred = () => {
  let resolve
  let reject
  const promise = new Promise((res, rej) => {
    resolve = res
    reject = rej
  })
  return { promise, resolve, reject }
}

function fixture() {
  const styles = []
  const fallbacks = []
  const loads = new Map()
  const controls = createStyleControls({
    map: { setStyle: (style) => styles.push(style.name) },
    loadStyle: (url) => {
      const request = deferred()
      loads.set(url, request)
      return request.promise
    },
    defaultStyleUrl: "/styles/light.json",
    onFallback: (reason) => fallbacks.push(reason),
  })
  return { controls, styles, fallbacks, loads }
}

test("failed custom style restores source fallback without duplicate layers", async () => {
  const { controls, styles, fallbacks, loads } = fixture()
  const applied = controls.apply("https://custom.example.test/style.json")
  loads.get("https://custom.example.test/style.json").reject(new Error("404"))
  await Promise.resolve()
  loads.get("/styles/light.json").resolve({ name: "light" })
  assert.equal(await applied, "fallback")
  assert.deepEqual(styles, ["light"])
  assert.deepEqual(fallbacks, ["custom_style_load_failed"])
})

test("an older style response cannot replace a newer selection", async () => {
  const { controls, styles, loads } = fixture()
  const older = controls.apply("/styles/dark.json")
  const newer = controls.apply("/styles/white.json")
  loads.get("/styles/white.json").resolve({ name: "white" })
  assert.equal(await newer, "applied")
  loads.get("/styles/dark.json").resolve({ name: "dark" })
  assert.equal(await older, "stale")
  assert.deepEqual(styles, ["white"])
  controls.destroy()
  const late = controls.apply("/styles/black.json")
  assert.equal(await late, "stale")
  assert.equal(loads.has("/styles/black.json"), false)
})

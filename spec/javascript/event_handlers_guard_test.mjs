import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/event_handlers.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(withoutImports).toString("base64")}`
const { shouldShowPointPopup } = await import(moduleUrl)

test("a real single point shows its popup", () => {
  assert.equal(shouldShowPointPopup({ id: 42 }), true)
  assert.equal(shouldShowPointPopup({ id: 42, count: 1 }), true)
})

test("aggregate features without an id show no popup", () => {
  assert.equal(shouldShowPointPopup({}), false)
  assert.equal(shouldShowPointPopup({ count: 250 }), false)
})

test("merged cells carrying an arbitrary representative show no popup", () => {
  assert.equal(shouldShowPointPopup({ id: 42, count: 2 }), false)
})

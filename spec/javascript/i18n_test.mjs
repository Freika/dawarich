import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL("../../app/javascript/i18n.js", import.meta.url),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`

test("translates strings, interpolation, and count-based plural forms", async () => {
  const payload = {
    greeting: "Hello %{name}",
    visits: { one: "%{count} visit", other: "%{count} visits" },
  }
  globalThis.document = {
    getElementById: () => ({ textContent: JSON.stringify(payload) }),
  }

  try {
    const { translate } = await import(moduleUrl)

    assert.equal(translate("greeting", { name: "Ada" }), "Hello Ada")
    assert.equal(translate("visits", { count: 1 }), "1 visit")
    assert.equal(translate("visits", { count: 2 }), "2 visits")
    assert.equal(translate("missing.key"), "missing.key")
  } finally {
    delete globalThis.document
  }
})

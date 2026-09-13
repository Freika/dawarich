import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// The real translate() against the key shape the locale files define,
// exercising one/other plural selection and %{layers} interpolation.
const fixture = {
  map: {
    tiled_rendering: {
      inactive_note: {
        one: "Inactive while %{layers} is on — it needs the full point set.",
        other:
          "Inactive while %{layers} are on — those need the full point set.",
      },
    },
  },
}

globalThis.document = {
  getElementById: () => ({ textContent: JSON.stringify(fixture) }),
}

const source = await readFile(
  new URL("../../app/javascript/i18n.js", import.meta.url),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { translate } = await import(moduleUrl)

test("singular blocker uses the one-form with interpolation", () => {
  assert.equal(
    translate("map.tiled_rendering.inactive_note", {
      layers: "Routes",
      count: 1,
    }),
    "Inactive while Routes is on — it needs the full point set.",
  )
})

test("multiple blockers use the other-form with interpolation", () => {
  assert.equal(
    translate("map.tiled_rendering.inactive_note", {
      layers: "Routes, Scratch map",
      count: 2,
    }),
    "Inactive while Routes, Scratch map are on — those need the full point set.",
  )
})

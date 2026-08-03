import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// The class imports "i18n" and "./theme_utils", neither of which node can
// resolve as a bare/relative specifier here. No method runs at definition time,
// so dropping the imports is enough to reach formatDateShort, which is a pure
// function of its argument.
const source = await readFile(
  new URL("../../app/javascript/maps/location_search.js", import.meta.url),
  "utf8",
)
const stubbed = `${source.replace(/^import .*$/gm, "")}
export const formatDateShort = LocationSearch.prototype.formatDateShort
`
const moduleUrl = `data:text/javascript;base64,${Buffer.from(stubbed).toString("base64")}`
const { formatDateShort } = await import(moduleUrl)

test("formatDateShort renders day before month", () => {
  // 3 August, not 8 March. A locale derived from <html lang="en"> resolves to
  // en-US and silently swaps these two components.
  assert.equal(formatDateShort("2026-08-03T12:00:00"), "03/08/2026")
})

test("formatDateShort zero-pads single-digit days and months", () => {
  assert.equal(formatDateShort("2026-01-09T12:00:00"), "09/01/2026")
})

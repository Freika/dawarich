import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/month_grid.js",
    import.meta.url,
  ),
  "utf8",
)
const { monthGridStart } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

const iso = (date) =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`

test("starts the month grid on Monday like the server for a Monday week start", () => {
  assert.equal(iso(monthGridStart(2026, 9, 1)), "2026-09-28")
  assert.equal(iso(monthGridStart(2026, 3, 1)), "2026-03-30")
  assert.equal(iso(monthGridStart(2024, 0, 1)), "2024-01-01")
})

test("starts the month grid on Sunday like the server for a Sunday week start", () => {
  assert.equal(iso(monthGridStart(2026, 9, 0)), "2026-09-27")
  assert.equal(iso(monthGridStart(2026, 3, 0)), "2026-03-29")
  assert.equal(iso(monthGridStart(2026, 2, 0)), "2026-03-01")
})

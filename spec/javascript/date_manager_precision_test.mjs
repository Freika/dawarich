import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/date_manager.js",
    import.meta.url,
  ),
  "utf8",
)
const { DateManager } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

test("map initialization preserves the precise trip boundaries", () => {
  for (const value of [
    "2024-11-27T18:16:21+01:00",
    "2024-11-29T10:45:12+01:00",
  ]) {
    const date = new Date(value)
    assert.equal(
      new Date(DateManager.formatDateForAPI(date)).getTime(),
      date.getTime(),
    )
  }
})

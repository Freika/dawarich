import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/trip_maplibre_controller.js",
    import.meta.url,
  ),
  "utf8",
)

test("trip routes use the saved route gap settings", () => {
  assert.match(
    source,
    /addDayRoutes\(this\.pointsByDay, \{\s*distanceThresholdMeters: this\.metersBetweenRoutesValue,\s*timeThresholdMinutes: this\.minutesBetweenRoutesValue,/,
  )
})

const sharedSource = await readFile(
  new URL(
    "../../app/javascript/controllers/shared_trip_map_controller.js",
    import.meta.url,
  ),
  "utf8",
)

test("shared trip routes use the owner's route gap settings", () => {
  assert.match(
    sharedSource,
    /addDayRoutes\(pointsByDay, \{\s*distanceThresholdMeters: this\.metersBetweenRoutesValue,\s*timeThresholdMinutes: this\.minutesBetweenRoutesValue,/,
  )
})

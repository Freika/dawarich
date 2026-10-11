import assert from "node:assert/strict"
import test from "node:test"
import { mapSettings } from "../../app-phoenix/assets/js/map/ui/host_settings.js"

test("saved track gaps replace the native route grouping thresholds without a reload", () => {
  const current = {routeOptions: {distanceThresholdMeters: 500, timeThresholdMinutes: 30}, distanceUnit: "km"}
  const next = mapSettings({maps: {distance_unit: "mi"}, meters_between_routes: 750, minutes_between_routes: 45}, current)
  assert.deepEqual(next.routeOptions, {distanceThresholdMeters: 750, timeThresholdMinutes: 45})
  assert.equal(next.distanceUnit, "mi")
  assert.deepEqual(current.routeOptions, {distanceThresholdMeters: 500, timeThresholdMinutes: 30})
  assert.deepEqual(mapSettings({}, next).routeOptions, next.routeOptions)
  assert.deepEqual(mapSettings({meters_between_routes: "500", minutes_between_routes: "30"}, next).routeOptions, current.routeOptions)
})

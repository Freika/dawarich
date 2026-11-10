import assert from "node:assert/strict"
import test from "node:test"
import { snapshotInitialDateRange } from "controllers/maps/maplibre/map_bootstrap"

test("the load-time range is kept in the server's and the API's format", () => {
  const controller = {
    startDateValue: "2024-06-01T00:00",
    endDateValue: "2999-06-30T23:59",
  }

  snapshotInitialDateRange(controller)

  assert.match(controller.startDateValue, /^2024-06-01T00:00:00[+-]\d\d:\d\d$/)
  assert.deepEqual(controller.defaultDateRange, {
    startValue: controller.startDateValue,
    endValue: controller.endDateValue,
    startDate: "2024-06-01",
    endDate: "2999-06-30",
    reachesNow: true,
  })
})

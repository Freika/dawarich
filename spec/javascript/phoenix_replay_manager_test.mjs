import assert from "node:assert/strict"
import { test } from "node:test"
import { ReplayManager } from "../../app-phoenix/assets/js/map/replay/manager.js"

process.env.TZ = "Europe/Berlin"

const point = (timestamp) => ({
  geometry: { coordinates: [0, 0] },
  properties: { timestamp },
})

test("replay manager indexes 05:00Z as 22:00 in the profile timezone", () => {
  const manager = new ReplayManager({ timezone: "America/Los_Angeles" })
  manager.setPoints([
    point("2020-04-18T03:00:00Z"),
    point("2020-04-18T04:00:00Z"),
    point("2020-04-18T05:00:00Z"),
  ])
  assert.equal(manager.minuteOfDay(new Date("2020-04-18T05:00:00Z")), 1320)
})

test("replay manager defaults minutes to UTC without a profile timezone", () => {
  const manager = new ReplayManager()
  manager.setPoints([point("2020-04-18T05:00:00Z")])
  assert.equal(manager.minuteOfDay(new Date("2020-04-18T05:00:00Z")), 300)
  assert.equal(manager.getCurrentDayLengthMinutes(), 1440)
})

test("replay manager uses elapsed minutes across the fall-back hour", () => {
  const manager = new ReplayManager({ timezone: "America/Los_Angeles" })
  manager.setPoints([
    point("2020-11-01T08:50:00Z"),
    point("2020-11-01T09:10:00Z"),
    point("2020-11-02T07:40:00Z"),
  ])
  assert.equal(manager.minuteOfDay(new Date("2020-11-01T08:50:00Z")), 110)
  assert.equal(manager.minuteOfDay(new Date("2020-11-01T09:10:00Z")), 130)
  assert.equal(manager.getCurrentDayLengthMinutes(), 1500)
  assert.ok(manager.getDataDensity(48)[47] > 0)
  assert.equal(manager.formatCurrentMinute(110), "01:50 PDT")
  assert.equal(manager.formatCurrentMinute(130), "01:10 PST")
})

test("replay manager uses the shortened spring-forward day", () => {
  const manager = new ReplayManager({ timezone: "America/Los_Angeles" })
  manager.setPoints([point("2020-03-08T10:30:00Z")])
  assert.equal(manager.minuteOfDay(new Date("2020-03-08T10:30:00Z")), 150)
  assert.equal(manager.getCurrentDayLengthMinutes(), 1380)
  assert.equal(manager.formatCurrentMinute(150), "03:30")
  assert.equal(
    new ReplayManager({ noDataLabel: "No data" }).getCurrentDayDisplay(),
    "No data",
  )
})

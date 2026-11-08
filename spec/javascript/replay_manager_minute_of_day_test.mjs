import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/maps_maplibre/managers/replay_manager.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import[\s\S]*?from "[^"]+"\n/m, "")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { ReplayManager } = await import(moduleUrl)

const date = new Date("2025-01-15T00:00:00Z")
const browserMinute = date.getHours() * 60 + date.getMinutes()

function countFormatterBuilds(run) {
  const RealDateTimeFormat = Intl.DateTimeFormat
  let builds = 0
  Intl.DateTimeFormat = class extends RealDateTimeFormat {
    constructor(...args) {
      builds += 1
      super(...args)
    }
  }
  try {
    run()
  } finally {
    Intl.DateTimeFormat = RealDateTimeFormat
  }
  return builds
}

test("uses the configured timezone east of UTC", () => {
  const manager = new ReplayManager({ timezone: "Asia/Tokyo" })
  assert.equal(manager.minuteOfDay(date), 540)
})

test("uses the configured timezone west of UTC", () => {
  const manager = new ReplayManager({ timezone: "America/Los_Angeles" })
  assert.equal(manager.minuteOfDay(date), 960)
})

test("follows a timezone changed on the same manager", () => {
  const manager = new ReplayManager({ timezone: "Asia/Tokyo" })
  assert.equal(manager.minuteOfDay(date), 540)

  manager.timezone = "America/Los_Angeles"
  assert.equal(manager.minuteOfDay(date), 960)
})

test("falls back to browser time for an invalid timezone", () => {
  const manager = new ReplayManager({ timezone: "Not/AZone" })
  assert.equal(manager.minuteOfDay(date), browserMinute)
})

test("does not keep a formatter after the timezone becomes invalid", () => {
  const manager = new ReplayManager({ timezone: "Asia/Tokyo" })
  manager.minuteOfDay(date)

  manager.timezone = "Not/AZone"
  assert.equal(manager.minuteOfDay(date), browserMinute)

  manager.timezone = "America/Los_Angeles"
  assert.equal(manager.minuteOfDay(date), 960)
})

test("day key uses the configured date east of UTC", () => {
  const manager = new ReplayManager({ timezone: "Asia/Tokyo" })
  assert.equal(manager.dayKey(new Date("2025-01-15T20:00:00Z")), "2025-01-16")
})

test("day key uses the configured date west of UTC", () => {
  const manager = new ReplayManager({ timezone: "America/Los_Angeles" })
  assert.equal(manager.dayKey(new Date("2025-01-15T03:00:00Z")), "2025-01-14")
})

test("day key is null for an invalid date", () => {
  const manager = new ReplayManager({ timezone: "Asia/Tokyo" })
  assert.equal(manager.dayKey(new Date("not a date")), null)
})

test("builds one formatter across many calls", () => {
  const manager = new ReplayManager({ timezone: "Asia/Tokyo" })
  const builds = countFormatterBuilds(() => {
    for (let call = 0; call < 500; call += 1) manager.minuteOfDay(date)
  })
  assert.equal(builds, 1)
})

test("tries an invalid timezone only once across many calls", () => {
  const manager = new ReplayManager({ timezone: "Not/AZone" })
  const builds = countFormatterBuilds(() => {
    for (let call = 0; call < 500; call += 1) manager.minuteOfDay(date)
  })
  assert.equal(builds, 1)
})

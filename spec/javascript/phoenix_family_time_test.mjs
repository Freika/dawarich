import assert from "node:assert/strict"
import { test } from "node:test"
import { familyLastSeen } from "../../app-phoenix/assets/js/map/family/time.js"

test("family relative labels preserve distance buckets and localized template", () => {
  const words = Object.fromEntries(
    [
      "less_than_x_minutes",
      "x_minutes",
      "about_x_hours",
      "x_days",
      "about_x_months",
      "x_months",
      "about_x_years",
      "over_x_years",
      "almost_x_years",
    ].map((k) => [k, { one: `${k} %{count}`, other: `${k} %{count}` }]),
  )
  const labels = { words, ago: "vor %{time}", middot: "·" }
  const now = Date.UTC(2026, 9, 10)
  for (const [minutes, key, count] of [
    [0, "less_than_x_minutes", 1],
    [5, "x_minutes", 5],
    [46, "about_x_hours", 1],
    [91, "about_x_hours", 2],
    [1450, "x_days", 1],
    [43201, "about_x_months", 1],
    [86401, "x_months", 2],
    [600000, "about_x_years", 1],
  ]) {
    assert.equal(
      familyLastSeen({ timestamp: now / 1000 - minutes * 60 }, labels, now),
      `· vor ${key} ${count}`,
    )
  }
})

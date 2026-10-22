import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/trip_plan.js",
    import.meta.url,
  ),
  "utf8",
)
const { planDayCount, planMarkers, planDayColorExpression, planBounds } =
  await import(
    `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
  )

const stop = (day, number, coordinates, name = `Stop ${number}`) => ({
  type: "Feature",
  geometry: { type: "Point", coordinates },
  properties: { kind: "stop", day, number, name },
})
const plan = {
  type: "FeatureCollection",
  features: [
    stop(0, 1, [12.41, 51.31]),
    stop(0, 3, [12.39, 51.32]),
    stop(1, 1, [12.38, 51.35]),
    {
      type: "Feature",
      geometry: { type: "Point", coordinates: [12.37, 51.34] },
      properties: { kind: "stay", name: "Hotel" },
    },
  ],
}
const palette = ["#111111", "#222222"]

test("counts the days that have located stops", () => {
  assert.equal(planDayCount(plan), 2)
})

test("numbers each stop marker and colours it by its day", () => {
  assert.deepEqual(
    planMarkers(plan, palette).map(({ number, color, name }) => [
      number,
      color,
      name,
    ]),
    [
      [1, "#111111", "Stop 1"],
      [3, "#111111", "Stop 3"],
      [1, "#222222", "Stop 1"],
    ],
  )
})

test("colours map features by day for the style expression", () => {
  assert.deepEqual(planDayColorExpression(palette), [
    "match",
    ["get", "day"],
    0,
    "#111111",
    1,
    "#222222",
    "#111111",
  ])
})

test("frames every located feature", () => {
  assert.deepEqual(planBounds(plan), [
    [12.37, 51.31],
    [12.41, 51.35],
  ])
})

import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/flight_arcs.js",
    import.meta.url,
  ),
  "utf8",
)
const { greatCircleLines } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

const maxLongitudeStep = (lines) =>
  Math.max(
    ...lines.flatMap((line) =>
      line.slice(1).map((coord, i) => Math.abs(coord[0] - line[i][0])),
    ),
  )

for (const [name, coordinates] of [
  [
    "dense eastbound",
    [
      [179.9, -55.6],
      [-179.9, -55.6],
    ],
  ],
  [
    "dense westbound",
    [
      [-179.9, -55.6],
      [179.9, -55.6],
    ],
  ],
  [
    "sparse eastbound",
    [
      [176.1, -55.6],
      [-176.1, -55.6],
    ],
  ],
  [
    "out and back",
    [
      [179.5, -55.6],
      [-179.5, -55.6],
      [179.5, -55.7],
    ],
  ],
]) {
  test(`a ${name} line crosses 180° the short way`, () => {
    const lines = greatCircleLines(coordinates)

    assert.ok(maxLongitudeStep(lines) <= 180)
  })
}

test("a line that does not cross 180° keeps its longitudes", () => {
  const coordinates = [
    [13.4, 52.5],
    [13.5, 52.6],
  ]

  assert.deepEqual(greatCircleLines(coordinates), [coordinates])
})

test("unwrapping leaves the input coordinates untouched", () => {
  const coordinates = [
    [179.9, -55.6],
    [-179.9, -55.6],
  ]
  const before = JSON.stringify(coordinates)

  greatCircleLines(coordinates)

  assert.equal(JSON.stringify(coordinates), before)
})

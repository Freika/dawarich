import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

async function loadController() {
  const source = await readFile(
    new URL(
      "../../app/javascript/controllers/map_matching_demo_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
  const withoutImports = source.replace(/^import .*$\n/gm, "")
  const dependencies = `
    class Controller {}
    const maplibregl = {}
    const getCurrentTheme = () => "light"
    const getMapStyle = async () => ({})
  `
  const url = `data:text/javascript;base64,${Buffer.from(`${dependencies}\n${withoutImports}`).toString("base64")}`
  return await import(`${url}#${Date.now()}-${Math.random()}`)
}

class FakeClassList {
  constructor() {
    this.values = new Set()
  }

  toggle(name, enabled) {
    if (enabled) this.values.add(name)
    else this.values.delete(name)
  }

  has(name) {
    return this.values.has(name)
  }
}

function pathLengthKm(coordinates) {
  const earthRadiusKm = 6371
  const radians = (degrees) => (degrees * Math.PI) / 180

  return coordinates.slice(1).reduce((distance, point, index) => {
    const previous = coordinates[index]
    const latitudeDelta = radians(point[1] - previous[1])
    const longitudeDelta = radians(point[0] - previous[0])
    const previousLatitude = radians(previous[1])
    const latitude = radians(point[1])
    const haversine =
      Math.sin(latitudeDelta / 2) ** 2 +
      Math.cos(previousLatitude) *
        Math.cos(latitude) *
        Math.sin(longitudeDelta / 2) ** 2

    return (
      distance +
      2 *
        earthRadiusKm *
        Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine))
    )
  }, 0)
}

test("the Berlin demo route is between two and three kilometres", async () => {
  const { MATCHED_PATH } = await loadController()

  assert.equal(MATCHED_PATH.length, 164)
  assert.deepEqual(MATCHED_PATH[0], [13.413474, 52.521815])
  assert.deepEqual(MATCHED_PATH.at(-1), [13.377699, 52.51627])
  assert.ok(pathLengthKm(MATCHED_PATH) >= 2)
  assert.ok(pathLengthKm(MATCHED_PATH) <= 3)
  assert.ok(
    Math.max(
      ...MATCHED_PATH.slice(1).map((point, index) =>
        pathLengthKm([MATCHED_PATH[index], point]),
      ),
    ) < 0.2,
  )
})

test("the route switch updates the map and pressed state", async () => {
  const { default: MapMatchingDemoController } = await loadController()
  const controller = new MapMatchingDemoController()
  const buttons = ["original", "matched"].map((mode) => ({
    dataset: { mode },
    attributes: {},
    classList: new FakeClassList(),
    setAttribute(name, value) {
      this.attributes[name] = value
    },
  }))
  const paintChanges = []
  controller.mode = "matched"
  controller.buttonTargets = buttons
  controller.routeReady = true
  controller.map = {
    setPaintProperty(layer, property, value) {
      paintChanges.push({ layer, property, value })
    },
  }

  controller.showMode("original")

  assert.equal(buttons[0].attributes["aria-pressed"], "true")
  assert.equal(buttons[1].attributes["aria-pressed"], "false")
  assert.equal(buttons[0].classList.has("btn-warning"), true)
  assert.equal(buttons[1].classList.has("btn-success"), false)
  assert.deepEqual(paintChanges.at(-1), {
    layer: "map-matching-demo-matched",
    property: "line-opacity",
    value: 0,
  })
})

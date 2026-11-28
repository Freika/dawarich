import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// Mirrors MapLibre: compact mode opens itself the first time there is text.
class FakeAttributionControl {
  constructor() {
    const classes = new Set()
    this._container = {
      classList: {
        add: (...names) => {
          for (const n of names) classes.add(n)
        },
        remove: (...names) => {
          for (const n of names) classes.delete(n)
        },
        contains: (name) => classes.has(name),
      },
    }
    this._updateCompact = () => {
      if (!classes.has("maplibregl-compact")) {
        classes.add("maplibregl-compact", "maplibregl-compact-show")
      }
    }
    this._updateCompactMinimize = () =>
      classes.delete("maplibregl-compact-show")
  }
}

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/collapsed_attribution.js",
    import.meta.url,
  ),
  "utf8",
)
globalThis.__fakeMaplibre = { AttributionControl: FakeAttributionControl }
const { collapsedAttributionControl } = await import(
  `data:text/javascript;base64,${Buffer.from(
    source.replace(
      /^import .* from "maplibre-gl"\n/m,
      "const maplibregl = globalThis.__fakeMaplibre\n",
    ),
  ).toString("base64")}`
)

test("the attribution starts collapsed", () => {
  const control = collapsedAttributionControl()
  control._updateCompact()
  const classes = control._container.classList
  assert.ok(classes.contains("maplibregl-compact"))
  assert.ok(!classes.contains("maplibregl-compact-show"))
})

test("an attribution the reader opened stays open on later updates", () => {
  const control = collapsedAttributionControl()
  control._updateCompact()
  control._container.classList.add("maplibregl-compact-show")
  control._updateCompact()
  assert.ok(control._container.classList.contains("maplibregl-compact-show"))
})

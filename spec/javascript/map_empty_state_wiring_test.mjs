import assert from "node:assert/strict"
import test from "node:test"
import { strippedSource } from "./support/stripped_source.mjs"

// buildMapFeatures constructs every manager; each import is replaced by a
// stub that only records its constructor arguments, so the test sees what the
// map hands to RangeStatistics without loading MapLibre.
const stubs = `
class Stub {
  constructor(...args) { this.args = args }
  attachViewportRefetch() {}
  initialize() {}
  static getSetting() { return false }
}
const RangeStatistics = Stub, PlacePanelBridge = Stub,
  TimelineSegmentHover = Stub, ApiClient = Stub, SearchManager = Stub,
  SettingsManager = Stub, AreaSelectionManager = Stub, DataLoader = Stub,
  EventHandlers = Stub, FilterManager = Stub, LayerManager = Stub,
  LayerVisibilityManager = Stub, MapDataManager = Stub, PlacesManager = Stub,
  VisitsManager = Stub
const consumeCreatePlaceLink = () => {}
`
const source = await strippedSource(
  "controllers/maps/maplibre/map_bootstrap.js",
)
const { buildMapFeatures } = await import(
  `data:text/javascript;base64,${Buffer.from(stubs + source).toString("base64")}`
)

function mapPage() {
  const classes = new Set(["hidden"])
  const emptyState = {
    classList: {
      toggle: (name, force) =>
        force ? classes.add(name) : classes.delete(name),
      contains: (name) => classes.has(name),
    },
  }
  const elements = {
    '[data-testid="map-range-statistics"]': {},
    '[data-testid="map-empty-state"]': emptyState,
  }
  const controller = {
    element: { querySelector: (selector) => elements[selector] ?? null },
    settings: {},
    timelineBridge: { connect() {} },
    hasSearchInputTarget: true,
    hasSearchResultsTarget: true,
  }
  buildMapFeatures(controller)
  const onData = controller.rangeStatistics.args[3]
  return { onData, emptyState }
}

test("an empty period shows the empty-state pill", () => {
  const { onData, emptyState } = mapPage()
  onData({ points: 0 })
  assert.equal(emptyState.classList.contains("hidden"), false)
})

test("a period with points, or one still loading, hides the pill", () => {
  const { onData, emptyState } = mapPage()
  onData({ points: 0 })
  onData({ points: 12 })
  assert.equal(emptyState.classList.contains("hidden"), true)
  onData({ points: 0 })
  onData(null)
  assert.equal(emptyState.classList.contains("hidden"), true)
})

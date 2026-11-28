import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/shared_live_map_controller.js",
    import.meta.url,
  ),
  "utf8",
)
const stubbedSource = source
  .replace(
    'import { Controller } from "@hotwired/stimulus"',
    "class Controller {}",
  )
  .replace(
    'import { createConsumer } from "@rails/actioncable"',
    "const createConsumer = () => ({})",
  )
  .replace(
    'import { formatDateTime, formatTime, translate } from "i18n"',
    'const formatDateTime = () => ""; const formatTime = () => ""; const translate = (key) => key',
  )
  .replace('import * as maplibregl from "maplibre-gl"', "const maplibregl = {}")
  .replace(
    'import { RecentPointLayer } from "maps_maplibre/layers/recent_point_layer"',
    "const RecentPointLayer = class {}",
  )
  .replace(
    'import { getMapStyle } from "maps_maplibre/utils/style_manager"',
    "const getMapStyle = async () => ({})",
  )
const { default: SharedLiveMapController } = await import(
  `data:text/javascript;base64,${Buffer.from(stubbedSource).toString("base64")}`
)

function fakeBadge(hidden) {
  const classes = new Set(hidden ? ["hidden"] : [])
  return {
    classList: {
      toggle: (name, force) =>
        force ? classes.add(name) : classes.delete(name),
    },
    isHidden: () => classes.has("hidden"),
  }
}

function buildController() {
  const controller = new SharedLiveMapController()
  Object.assign(controller, {
    hasLastSeenTarget: true,
    lastSeenTarget: { textContent: "" },
    hasLiveBadgeTarget: true,
    liveBadgeTarget: fakeBadge(false),
    hasLastKnownBadgeTarget: true,
    lastKnownBadgeTarget: fakeBadge(true),
    startRelativeTicker() {},
    relativeTime: () => "",
  })
  return controller
}

const now = () => Math.floor(Date.now() / 1000)

test("a location at most 15 minutes old keeps the Live badge", () => {
  const controller = buildController()

  controller.setLastSeen(now() - 60)

  assert.equal(controller.liveBadgeTarget.isHidden(), false)
  assert.equal(controller.lastKnownBadgeTarget.isHidden(), true)
})

test("a location older than 15 minutes shows the Last known badge", () => {
  const controller = buildController()

  controller.setLastSeen(now() - 16 * 60)

  assert.equal(controller.liveBadgeTarget.isHidden(), true)
  assert.equal(controller.lastKnownBadgeTarget.isHidden(), false)
})

test("a fresh location switches the badge back to Live", () => {
  const controller = buildController()
  controller.setLastSeen(now() - 16 * 60)

  controller.setLastSeen(now())

  assert.equal(controller.liveBadgeTarget.isHidden(), false)
  assert.equal(controller.lastKnownBadgeTarget.isHidden(), true)
})
